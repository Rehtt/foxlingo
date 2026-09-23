// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../client/image_translation_service.dart';
import '../models/image_translation_models.dart';
import '../models/screen_translation_models.dart';
import '../models/translation_models.dart';
import '../platform/overlay_controller.dart';
import '../platform/screen_capture_channel.dart';
import '../platform/translation_bridge.dart';
import '../utils/translation_settings.dart';

enum ScreenTranslationState {
  stopped,
  starting,
  ready,
  capturing,
  translating,
  result,
  error,
}

class TranslationControllerException implements Exception {
  const TranslationControllerException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

typedef ImageTranslationServiceFactory = ImageTranslationService Function();

/// Owns the cross-application translation session independently of HomePage.
///
/// The controller is deliberately driven by small gateway interfaces. This
/// keeps the session rules testable without pretending that a fake overlay or
/// fake MediaProjection proves real Android behavior.
class ScreenTranslationController extends ChangeNotifier {
  ScreenTranslationController({
    required TranslationSettings settings,
    ScreenCaptureGateway? screenCapture,
    OverlayController? overlay,
    ImageTranslationServiceFactory? serviceFactory,
    Locale? Function()? appLocale,
    Locale Function()? deviceLocale,
  }) : _settings = settings,
       _screenCapture = screenCapture ?? const ScreenCaptureChannel(),
       _overlay = overlay ?? FlutterOverlayController(),
       _serviceFactory = serviceFactory ?? ImageTranslationService.new,
       _appLocale = appLocale,
       _deviceLocale = deviceLocale ?? _defaultDeviceLocale {
    _overlaySubscription = _overlay.messages.listen(_onOverlayMessage);
    _captureSubscription = _screenCapture.events.listen(_onCaptureEvent);
  }

  final TranslationSettings _settings;
  final ScreenCaptureGateway _screenCapture;
  final OverlayController _overlay;
  final ImageTranslationServiceFactory _serviceFactory;
  final Locale? Function()? _appLocale;
  final Locale Function() _deviceLocale;

  late final StreamSubscription<TranslationBridgeMessage> _overlaySubscription;
  late final StreamSubscription<ScreenCaptureEvent> _captureSubscription;

  ScreenTranslationState _state = ScreenTranslationState.stopped;
  String? _errorCode;
  String? _errorMessage;
  String? _sessionId;
  Locale? _sessionAppLocale;
  Locale? _sessionDeviceLocale;
  int _requestSequence = 0;
  int _sessionSequence = 0;
  int _lastGeometryVersion = 0;
  CapturedFrame? _currentFrame;
  ImageTranslationResult? _currentResult;
  String? _currentTaskRequestId;
  ImageTranslationService? _service;
  _TranslationRequest? _activeRequest;
  Completer<void>? _overlayReady;
  Future<void>? _startOperation;
  _StartAttempt? _startAttempt;
  bool _overlayShown = false;
  bool _captureSessionStarted = false;
  bool _stopping = false;
  Completer<void>? _stopCompletion;
  bool _captureSessionUnavailable = false;
  bool _disposed = false;
  final StreamController<void> _settingsRequests =
      StreamController<void>.broadcast();

  ScreenTranslationState get state => _state;
  String? get errorCode => _errorCode;
  String? get errorMessage => _errorMessage;
  bool get isSessionActive =>
      _sessionId != null && _state != ScreenTranslationState.stopped;
  Stream<void> get settingsRequests => _settingsRequests.stream;

  bool get isBusy => switch (_state) {
    ScreenTranslationState.starting ||
    ScreenTranslationState.capturing ||
    ScreenTranslationState.translating => true,
    _ => false,
  };

  Future<bool> isOverlayPermissionGranted() => _overlay.isPermissionGranted();

  Future<bool> requestOverlayPermission() => _overlay.requestPermission();

  Future<void> start({Locale? appLocale, Locale? deviceLocale}) {
    final stopping = _stopCompletion;
    if (stopping != null) {
      final previousStart = _startOperation;
      return stopping.future.then((_) async {
        // A cancelled start can still be unwinding an authorization or show.
        await previousStart?.catchError((_) {});
        await start(appLocale: appLocale, deviceLocale: deviceLocale);
      });
    }
    final existing = _startOperation;
    if (existing != null) {
      return existing;
    }
    if (_state != ScreenTranslationState.stopped &&
        !(_state == ScreenTranslationState.error && _sessionId == null)) {
      return Future<void>.value();
    }

    final operation = _startInternal(
      appLocale: appLocale ?? _appLocale?.call(),
      deviceLocale: deviceLocale ?? _deviceLocale(),
    );
    _startOperation = operation;
    return operation.whenComplete(() {
      if (identical(_startOperation, operation)) {
        _startOperation = null;
      }
    });
  }

  Future<void> _startInternal({
    required Locale? appLocale,
    required Locale deviceLocale,
  }) async {
    _clearError();
    _setState(ScreenTranslationState.starting);
    final sessionId = 's${++_sessionSequence}';
    final attempt = _StartAttempt(sessionId);
    _startAttempt = attempt;
    _sessionId = sessionId;
    _sessionAppLocale = appLocale;
    _sessionDeviceLocale = deviceLocale;
    _lastGeometryVersion = 0;
    _captureSessionUnavailable = false;
    _captureSessionStarted = false;
    _overlayReady = Completer<void>();

    try {
      _validateConfiguration();

      var overlayGranted = await _overlay.isPermissionGranted();
      if (!overlayGranted) {
        overlayGranted = await _overlay.requestPermission();
      }
      if (!overlayGranted) {
        throw const TranslationControllerException(
          'overlay_permission_denied',
          'Overlay permission was not granted.',
        );
      }
      _ensureStartCurrent(attempt);

      try {
        await _screenCapture.requestNotificationPermission();
      } on Object {
        // Notification permission is independent from screen-capture consent.
      }
      _ensureStartCurrent(attempt);
      final permission = await _screenCapture.requestPermission();
      _ensureStartCurrent(attempt);
      if (!permission.granted) {
        throw TranslationControllerException(
          permission.cancelled
              ? 'screen_capture_cancelled'
              : 'screen_capture_denied',
          'Screen capture permission was not granted.',
        );
      }

      final session = await _screenCapture.startSession();
      if (!_isStartCurrent(attempt)) {
        await _screenCapture.stopSession().catchError((_) {});
        throw const _StaleTranslationRequest();
      }
      _lastGeometryVersion = session.geometryVersion;
      _captureSessionStarted = true;
      attempt.captureStarted = true;
      _service = _serviceFactory();

      await _overlay.show();
      if (!_isStartCurrent(attempt)) {
        await _overlay.hide().catchError((_) {});
        throw const _StaleTranslationRequest();
      }
      _ensureStartCurrent(attempt);
      _overlayShown = true;
      attempt.overlayShown = true;
      var bound = false;
      for (var bindAttempt = 0; bindAttempt < 20 && !bound; bindAttempt++) {
        _ensureStartCurrent(attempt);
        bound = await _overlay.bind();
        _ensureStartCurrent(attempt);
        if (!bound) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      if (!bound) {
        throw const TranslationControllerException(
          'overlay_unavailable',
          'The translation overlay could not be started.',
        );
      }

      await _awaitOverlayReady(attempt);
      _ensureStartCurrent(attempt);
      _startAttempt = null;
      _setState(ScreenTranslationState.ready);
      await _sendSnapshot();
    } on Object catch (error) {
      final ownsAttempt = identical(_startAttempt, attempt);
      if (ownsAttempt) {
        _startAttempt = null;
      }
      if (!attempt.resourcesCleaned) {
        if (attempt.captureStarted) {
          await _screenCapture.stopSession().catchError((_) {});
        }
        if (attempt.overlayShown) {
          await _overlay.hide().catchError((_) {});
        }
        attempt.resourcesCleaned = true;
      }
      if (ownsAttempt) {
        _overlayShown = false;
        _captureSessionStarted = false;
        await _service?.close().catchError((_) {});
        _service = null;
        _sessionId = null;
        _sessionAppLocale = null;
        _sessionDeviceLocale = null;
        _overlayReady = null;
        _lastGeometryVersion = 0;
        if (error is! _StaleTranslationRequest) {
          _setError(_controllerError(error));
        }
      }
      rethrow;
    }
  }

  Future<void> translate() async {
    if (_state != ScreenTranslationState.ready || _activeRequest != null) {
      return;
    }

    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }

    final request = _TranslationRequest(
      sessionId: sessionId,
      requestId: 'r${++_requestSequence}',
      settings: _settings.snapshot(),
      abort: Completer<void>(),
      appLocale: _sessionAppLocale,
      deviceLocale: _sessionDeviceLocale ?? _deviceLocale(),
      geometryVersionAtStart: _lastGeometryVersion,
    );
    _activeRequest = request;
    _currentTaskRequestId = request.requestId;
    _currentFrame = null;
    _currentResult = null;
    _clearError();
    _setState(ScreenTranslationState.capturing);

    try {
      await _sendSnapshot();
      _throwIfStale(request);
      await _send(
        _message(
          type: 'prepareCapture',
          sessionId: sessionId,
          requestId: request.requestId,
        ),
      );
      await Future.any<void>([
        request.capturePrepared.future,
        request.abort.future,
      ]).timeout(const Duration(seconds: 5));
      _throwIfStale(request);

      late final CapturedFrame frame;
      try {
        frame = await _screenCapture.captureFrame().timeout(
          const Duration(seconds: 6),
        );
      } on TimeoutException {
        await _screenCapture.cancelCapture().catchError((_) {});
        throw const TranslationControllerException(
          'capture_timeout',
          'Screen capture timed out. Please try again.',
        );
      }
      _throwIfStale(request);
      if (request.geometryVersionAtStart != 0 &&
          frame.geometryVersion != request.geometryVersionAtStart) {
        throw const TranslationControllerException(
          'geometry_changed',
          'The screen changed while it was being captured.',
        );
      }

      _currentFrame = frame;
      request.frameGeometryVersion = frame.geometryVersion;
      _lastGeometryVersion = frame.geometryVersion;
      _setState(ScreenTranslationState.translating);
      await _sendSnapshot();

      final service = _service ??= _serviceFactory();
      late final ImageTranslationResult result;
      try {
        result = await service
            .translate(
              imageBytes: frame.bytes,
              settings: request.settings,
              appLocale: request.appLocale,
              deviceLocale: request.deviceLocale,
              abortTrigger: request.abort.future,
              onProgress: (progress) {
                if (_activeRequest != request) {
                  return;
                }
                unawaited(
                  _send(
                    _message(
                      type: 'progress',
                      sessionId: sessionId,
                      requestId: request.requestId,
                      payload: <String, dynamic>{
                        'stage': progress.stage.name,
                        'regionCount': progress.regionCount,
                      },
                    ),
                  ),
                );
              },
            )
            .timeout(const Duration(seconds: 60));
      } on TimeoutException {
        _invalidateRequest(request);
        throw const TranslationControllerException(
          'translation_timeout',
          'Translation timed out after one minute.',
        );
      }
      _throwIfStale(request);

      _currentResult = result;
      _setState(ScreenTranslationState.result);
      await _send(
        _message(
          type: 'result',
          sessionId: sessionId,
          requestId: request.requestId,
          payload: <String, dynamic>{'result': result.toJson()},
        ),
      );
    } on Object catch (error) {
      if (_activeRequest != request || error is _StaleTranslationRequest) {
        return;
      }
      _setError(_controllerError(error));
      await _send(
        _message(
          type: 'error',
          sessionId: sessionId,
          requestId: request.requestId,
          payload: <String, dynamic>{
            'code': _errorCode,
            'message': _errorMessage,
          },
        ),
      );
    } finally {
      if (_activeRequest == request) {
        _activeRequest = null;
      }
    }
  }

  Future<void> cancelTranslation() async {
    final request = _activeRequest;
    if (request == null ||
        (_state != ScreenTranslationState.capturing &&
            _state != ScreenTranslationState.translating)) {
      return;
    }
    _invalidateRequest(request);
    _activeRequest = null;
    if (_state == ScreenTranslationState.capturing) {
      await _screenCapture.cancelCapture().catchError((_) {});
    }
    if (_sessionId != request.sessionId ||
        _currentTaskRequestId != request.requestId ||
        (_state != ScreenTranslationState.capturing &&
            _state != ScreenTranslationState.translating)) {
      return;
    }
    _clearCurrentTask();
    _setState(ScreenTranslationState.ready);
    await _sendSnapshot();
  }

  Future<void> dismissResult() async {
    if (_state != ScreenTranslationState.result &&
        _state != ScreenTranslationState.error) {
      return;
    }
    final request = _activeRequest;
    if (request != null) {
      _invalidateRequest(request);
    }
    _activeRequest = null;
    _clearCurrentTask();
    _clearError();
    if (_captureSessionUnavailable) {
      await stop();
      return;
    }
    _setState(ScreenTranslationState.ready);
    await _sendSnapshot();
  }

  Future<void> stop() async {
    if (_stopping) {
      return _stopCompletion?.future;
    }
    if (_state == ScreenTranslationState.stopped &&
        _sessionId == null &&
        !_overlayShown) {
      return;
    }

    _stopping = true;
    final completion = Completer<void>();
    _stopCompletion = completion;
    final startAttempt = _startAttempt;
    if (startAttempt != null) {
      startAttempt.cancelled = true;
      _startAttempt = null;
    }
    final request = _activeRequest;
    if (request != null) {
      _invalidateRequest(request);
    }
    _activeRequest = null;
    final hadOverlay = _overlayShown;
    _overlayShown = false;
    _sessionId = null;
    _sessionAppLocale = null;
    _sessionDeviceLocale = null;
    _overlayReady = null;
    _lastGeometryVersion = 0;
    _captureSessionStarted = false;
    _captureSessionUnavailable = false;
    _clearCurrentTask();
    _clearError();
    _setState(ScreenTranslationState.stopped);

    try {
      if (hadOverlay) {
        await _overlay.send(_message(type: 'stopped')).catchError((_) {});
        await _overlay.hide().catchError((_) {});
      }
      await _screenCapture.stopSession().catchError((_) {});
      await _service?.close().catchError((_) {});
      _service = null;
      if (startAttempt != null) {
        startAttempt.resourcesCleaned = true;
      }
    } finally {
      _stopping = false;
      _stopCompletion = null;
      completion.complete();
    }
  }

  Future<void> refresh() async {
    final observedSessionId = _sessionId;
    final observedState = _state;
    final observedCaptureSessionStarted = _captureSessionStarted;
    try {
      final session = await _screenCapture.getSessionState();
      if (session.state == ScreenCaptureSessionState.stopped &&
          _state != ScreenTranslationState.stopped &&
          !_stopping &&
          _sessionId == observedSessionId &&
          observedSessionId != null &&
          !(observedState == ScreenTranslationState.starting &&
              !observedCaptureSessionStarted)) {
        await _handleExternalStop();
      }
    } on Object {
      // A platform channel can be unavailable in a widget preview or test.
    }
  }

  bool _isStartCurrent(_StartAttempt attempt) {
    return identical(_startAttempt, attempt) &&
        !attempt.cancelled &&
        !_stopping &&
        _sessionId == attempt.sessionId;
  }

  void _ensureStartCurrent(_StartAttempt attempt) {
    if (!_isStartCurrent(attempt)) {
      throw const _StaleTranslationRequest();
    }
  }

  Future<void> _awaitOverlayReady(_StartAttempt attempt) async {
    final ready = _overlayReady;
    if (ready == null) {
      throw const TranslationControllerException(
        'overlay_unavailable',
        'The translation overlay could not be started.',
      );
    }
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!ready.isCompleted && DateTime.now().isBefore(deadline)) {
      _ensureStartCurrent(attempt);
      await _send(_message(type: 'handshake', sessionId: attempt.sessionId));
      if (ready.isCompleted) {
        return;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
      }
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 250)
            ? remaining
            : const Duration(milliseconds: 250),
      );
    }
    _ensureStartCurrent(attempt);
    if (!ready.isCompleted) {
      throw TimeoutException('The translation overlay did not become ready.');
    }
  }

  void _validateConfiguration() {
    if (_settings.imageMethod == ImageTranslationMethod.llm) {
      if (!_settings.isImageLlmConfigured ||
          _settings.effectiveImageLlmApiBaseUrl.trim().isEmpty ||
          _settings.effectiveImageLlmModel.trim().isEmpty) {
        throw const TranslationControllerException(
          'translation_not_configured',
          'Configure the image translation LLM before starting.',
        );
      }
    } else if (!_settings.isConfigured) {
      throw const TranslationControllerException(
        'translation_not_configured',
        'Configure the selected translation provider before starting.',
      );
    }
  }

  void _onOverlayMessage(TranslationBridgeMessage message) {
    if (message['version'] != 1) {
      return;
    }
    final type = message['type'];
    if (type is! String) {
      return;
    }
    final messageSession = message['sessionId'];
    if (type == 'ready') {
      if (_sessionId == null ||
          messageSession is! String ||
          messageSession != _sessionId) {
        return;
      }
      final ready = _overlayReady;
      if (ready != null && !ready.isCompleted) {
        ready.complete();
      }
      unawaited(_sendSnapshot());
      return;
    }
    if (_sessionId == null || messageSession != _sessionId) {
      return;
    }

    switch (type) {
      case 'translate':
        unawaited(translate());
      case 'cancel':
        if (message['requestId'] is String &&
            message['requestId'] == _activeRequest?.requestId) {
          unawaited(cancelTranslation());
        }
      case 'dismiss':
        if (message['requestId'] == _currentTaskRequestId) {
          unawaited(dismissResult());
        }
      case 'stop':
        unawaited(stop());
      case 'openSettings':
        unawaited(_handleOpenSettings());
      case 'capturePrepared':
        final requestId = message['requestId'];
        if (requestId == _activeRequest?.requestId) {
          final prepared = _activeRequest?.capturePrepared;
          if (prepared != null && !prepared.isCompleted) {
            prepared.complete();
          }
        }
    }
  }

  void _onCaptureEvent(ScreenCaptureEvent event) {
    final previousGeometryVersion = _lastGeometryVersion;
    _lastGeometryVersion = event.geometryVersion;
    if (event.state == ScreenCaptureSessionState.stopped &&
        _state == ScreenTranslationState.starting &&
        !_captureSessionStarted) {
      // A stopped query/event while the user is still completing permission
      // is the normal pre-session state. Do not cancel the start attempt.
      return;
    }
    if (event.state == ScreenCaptureSessionState.error) {
      if (_state != ScreenTranslationState.stopped && !_stopping) {
        unawaited(_handleExternalError(event));
      }
      return;
    }
    if (event.state == ScreenCaptureSessionState.stopped &&
        _state != ScreenTranslationState.stopped &&
        !_stopping) {
      unawaited(_handleExternalStop());
    }
    final request = _activeRequest;
    if (request != null &&
        event.geometryVersion != 0 &&
        request.geometryVersionAtStart != 0 &&
        event.geometryVersion != request.geometryVersionAtStart) {
      unawaited(_invalidateForGeometry(request));
    } else if (_currentFrame != null &&
        event.geometryVersion != 0 &&
        event.geometryVersion != _currentFrame!.geometryVersion &&
        (_state == ScreenTranslationState.result ||
            _state == ScreenTranslationState.error)) {
      _clearCurrentTask();
      _clearError();
      _setState(ScreenTranslationState.ready);
      unawaited(_sendSnapshot());
    } else if (_sessionId != null &&
        _state == ScreenTranslationState.ready &&
        event.geometryVersion != 0 &&
        event.geometryVersion != previousGeometryVersion) {
      // A ready bubble also needs a fresh bounds clamp after rotation.
      unawaited(_sendSnapshot());
    }
  }

  Future<void> _invalidateForGeometry(_TranslationRequest request) async {
    if (_activeRequest != request) {
      return;
    }
    _invalidateRequest(request);
    _activeRequest = null;
    await _screenCapture.cancelCapture().catchError((_) {});
    if (_sessionId != request.sessionId ||
        _currentTaskRequestId != request.requestId ||
        (_state != ScreenTranslationState.capturing &&
            _state != ScreenTranslationState.translating)) {
      return;
    }
    _clearCurrentTask();
    _clearError();
    _setState(ScreenTranslationState.ready);
    await _sendSnapshot();
  }

  Future<void> _handleOpenSettings() async {
    if (!_settingsRequests.isClosed) {
      _settingsRequests.add(null);
    }
    try {
      await _overlay.openApp();
    } on Object {
      // Bringing the Activity forward can fail in tests or after teardown.
    }
  }

  Future<void> _handleExternalStop() => stop();

  Future<void> _handleExternalError(ScreenCaptureEvent event) async {
    final sessionId = _sessionId;
    if (sessionId == null || _stopping) {
      return;
    }
    final startAttempt = _startAttempt;
    if (startAttempt != null) {
      startAttempt.cancelled = true;
      _startAttempt = null;
    }
    final request = _activeRequest;
    if (request != null) {
      _invalidateRequest(request);
    }
    _activeRequest = null;
    _captureSessionUnavailable = true;
    final service = _service;
    _service = null;
    await service?.close().catchError((_) {});
    if (_sessionId != sessionId || _stopping) {
      return;
    }
    _captureSessionStarted = false;
    if (startAttempt != null) {
      await _screenCapture.stopSession().catchError((_) {});
      if (_sessionId != sessionId || _stopping) {
        return;
      }
      startAttempt.resourcesCleaned = true;
    }
    if (startAttempt != null) {
      if (_overlayShown) {
        await _overlay.hide().catchError((_) {});
        if (_sessionId != sessionId || _stopping) {
          return;
        }
        _overlayShown = false;
      }
      _sessionId = null;
      _sessionAppLocale = null;
      _sessionDeviceLocale = null;
      _overlayReady = null;
      _lastGeometryVersion = 0;
    }
    _setError(
      TranslationControllerException(
        event.errorCode ?? 'screen_capture_error',
        event.message ?? 'Screen capture failed.',
      ),
    );
    await _sendSnapshot();
  }

  void _throwIfStale(_TranslationRequest request) {
    if (_activeRequest != request || request.abort.isCompleted) {
      throw const _StaleTranslationRequest();
    }
  }

  void _invalidateRequest(_TranslationRequest request) {
    if (!request.abort.isCompleted) {
      request.abort.complete();
    }
  }

  void _clearCurrentTask() {
    _currentTaskRequestId = null;
    _currentFrame = null;
    _currentResult = null;
  }

  void _setState(ScreenTranslationState state) {
    _state = state;
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _clearError() {
    _errorCode = null;
    _errorMessage = null;
  }

  void _setError(TranslationControllerException error) {
    _errorCode = error.code;
    _errorMessage = error.message;
    _setState(ScreenTranslationState.error);
  }

  TranslationControllerException _controllerError(Object error) {
    if (error is TranslationControllerException) {
      return error;
    }
    if (error is ScreenCaptureException) {
      return TranslationControllerException(error.code, error.message);
    }
    if (error is TimeoutException) {
      return const TranslationControllerException(
        'timeout',
        'The operation timed out. Please try again.',
      );
    }
    if (error is _StaleTranslationRequest) {
      return const TranslationControllerException(
        'cancelled',
        'The translation was cancelled.',
      );
    }
    return TranslationControllerException(
      'translation_failed',
      error.toString(),
    );
  }

  Future<void> _sendSnapshot() async {
    final sessionId = _sessionId;
    final requestId = _currentTaskRequestId;
    final frame = _currentFrame;
    final result = _currentResult;
    if (sessionId == null) {
      return;
    }
    await _send(
      _message(
        type: 'state',
        sessionId: sessionId,
        requestId: requestId,
        payload: <String, dynamic>{
          'state': _state.name,
          'locale':
              (_sessionAppLocale ?? _sessionDeviceLocale ?? _deviceLocale())
                  .languageCode,
          'errorCode': _errorCode,
          'errorMessage': _errorMessage,
          'hasFrame': _currentFrame != null,
          'hasResult': _currentResult != null,
        },
      ),
    );
    if (_sessionId != sessionId || _currentTaskRequestId != requestId) return;
    if (frame != null) {
      await _send(
        _message(
          type: 'capturedFrame',
          sessionId: sessionId,
          requestId: requestId,
          payload: <String, dynamic>{
            'bytes': frame.bytes,
            'width': frame.width,
            'height': frame.height,
            'frameId': frame.frameId,
            'geometryVersion': frame.geometryVersion,
          },
        ),
      );
    }
    if (_sessionId != sessionId || _currentTaskRequestId != requestId) return;
    if (result != null) {
      await _send(
        _message(
          type: 'result',
          sessionId: sessionId,
          requestId: requestId,
          payload: <String, dynamic>{'result': result.toJson()},
        ),
      );
    }
  }

  Future<void> _send(TranslationBridgeMessage message) async {
    try {
      await _overlay.send(message);
    } on Object {
      // Overlay shutdown is allowed to race with the last state message.
    }
  }

  TranslationBridgeMessage _message({
    required String type,
    String? sessionId,
    String? requestId,
    Map<String, dynamic>? payload,
  }) {
    return <String, dynamic>{
      'version': 1,
      'type': type,
      ...(sessionId == null
          ? const <String, dynamic>{}
          : {'sessionId': sessionId}),
      ...(requestId == null
          ? const <String, dynamic>{}
          : {'requestId': requestId}),
      ...(payload == null ? const <String, dynamic>{} : {'payload': payload}),
    };
  }

  static Locale _defaultDeviceLocale() {
    return PlatformDispatcher.instance.locale;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_overlaySubscription.cancel());
    unawaited(_captureSubscription.cancel());
    unawaited(_settingsRequests.close());
    final request = _activeRequest;
    if (request != null) {
      _invalidateRequest(request);
    }
    unawaited(_service?.close() ?? Future<void>.value());
    if (_overlay case final FlutterOverlayController overlay) {
      overlay.dispose();
    }
    super.dispose();
  }
}

class _TranslationRequest {
  _TranslationRequest({
    required this.sessionId,
    required this.requestId,
    required this.settings,
    required this.abort,
    required this.appLocale,
    required this.deviceLocale,
    required this.geometryVersionAtStart,
  });

  final String sessionId;
  final String requestId;
  final TranslationSettings settings;
  final Completer<void> abort;
  final Completer<void> capturePrepared = Completer<void>();
  final Locale? appLocale;
  final Locale deviceLocale;
  final int geometryVersionAtStart;
  int? frameGeometryVersion;
}

class _StartAttempt {
  _StartAttempt(this.sessionId);

  final String sessionId;
  bool cancelled = false;
  bool captureStarted = false;
  bool overlayShown = false;
  bool resourcesCleaned = false;
}

class _StaleTranslationRequest implements Exception {
  const _StaleTranslationRequest();
}
