import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxlingo/client/image_translation_service.dart';
import 'package:foxlingo/controllers/screen_translation_controller.dart';
import 'package:foxlingo/models/image_translation_models.dart';
import 'package:foxlingo/models/screen_translation_models.dart';
import 'package:foxlingo/models/translation_models.dart';
import 'package:foxlingo/platform/overlay_controller.dart';
import 'package:foxlingo/platform/screen_capture_channel.dart';
import 'package:foxlingo/platform/translation_bridge.dart';
import 'package:foxlingo/utils/translation_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  for (final external in [false, true]) {
    test(
      'restart waits for ${external ? 'system' : 'client'} stop cleanup',
      () async {
        final capture = _FakeCapture();
        final overlay = _DelayedHideOverlay();
        final controller = _controller(
          await _configuredSettings(),
          capture,
          overlay,
        );
        addTearDown(controller.dispose);
        await controller.start();
        Future<void>? stopping;
        if (external) {
          capture.emitEvent(
            const ScreenCaptureEvent(state: ScreenCaptureSessionState.stopped),
          );
        } else {
          stopping = controller.stop();
        }
        await overlay.hiding.future;
        final restarting = controller.start();
        var secondStopFinished = false;
        final secondStop = controller.stop().then(
          (_) => secondStopFinished = true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(capture.startCalls, 1);
        expect(secondStopFinished, isFalse);
        overlay.release.complete();
        await stopping;
        await secondStop;
        await restarting;
        expect(controller.state, ScreenTranslationState.ready);
        expect(capture.startCalls, 2);
        expect(overlay.showCalls, 2);
      },
    );
  }

  for (final action in ['cancel', 'dismiss']) {
    test(
      'ignores previous request $action after a new translation starts',
      () async {
        final overlay = _FakeOverlay(autoPrepare: action == 'dismiss');
        final controller = _controller(
          await _configuredSettings(),
          _FakeCapture(),
          overlay,
          serviceFactory: () => _ImmediateService(
            const ImageTranslationResult(imageSize: Size(100, 50), regions: []),
          ),
        );
        addTearDown(controller.dispose);
        await controller.start();
        final first = controller.translate();
        await overlay.prepareSent.future;
        final old = overlay.sent.lastWhere(
          (m) => m['type'] == 'prepareCapture',
        );
        if (action == 'cancel') {
          await controller.cancelTranslation();
          await first;
        } else {
          await first;
          await controller.dismissResult();
        }
        final second = controller.translate();
        if (action == 'dismiss') await second;
        await Future<void>.delayed(Duration.zero);
        final current = overlay.sent.lastWhere(
          (m) => m['type'] == 'prepareCapture',
        );
        overlay.emit({
          'version': 1,
          'type': action,
          'sessionId': old['sessionId'],
          'requestId': old['requestId'],
        });
        await Future<void>.delayed(Duration.zero);
        expect(
          controller.state,
          action == 'cancel'
              ? ScreenTranslationState.capturing
              : ScreenTranslationState.result,
        );
        overlay.emit({
          'version': 1,
          'type': action,
          'sessionId': current['sessionId'],
          'requestId': current['requestId'],
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.state, ScreenTranslationState.ready);
        await second;
      },
    );
  }

  for (final restart in [false, true]) {
    test(
      'late native error cleanup cannot overwrite ${restart ? 'new session' : 'stop'}',
      () async {
        final capture = _FakeCapture();
        final overlay = _FakeOverlay();
        final oldService = _DelayedCloseService();
        var serviceCount = 0;
        final controller = _controller(
          await _configuredSettings(),
          capture,
          overlay,
          serviceFactory: () => serviceCount++ == 0
              ? oldService
              : _ImmediateService(
                  const ImageTranslationResult(
                    imageSize: Size(100, 50),
                    regions: [],
                  ),
                ),
        );
        addTearDown(controller.dispose);
        await controller.start();
        capture.emitEvent(
          const ScreenCaptureEvent(
            state: ScreenCaptureSessionState.error,
            errorCode: 'resize_failed',
            message: 'Old session failed.',
          ),
        );
        await oldService.closing.future;
        await controller.stop();
        if (restart) await controller.start();
        overlay.sent.clear();
        oldService.release.complete();
        await Future<void>.delayed(Duration.zero);
        expect(
          controller.state,
          restart
              ? ScreenTranslationState.ready
              : ScreenTranslationState.stopped,
        );
        expect(controller.errorCode, isNull);
        expect(overlay.sent, isEmpty);
        if (restart) {
          await controller.translate();
          expect(controller.state, ScreenTranslationState.result);
        }
      },
    );
  }

  for (final rotate in [false, true]) {
    test(
      'stop wins over pending ${rotate ? 'rotation' : 'cancel'} cleanup',
      () async {
        final capture = _FakeCapture();
        final overlay = _FakeOverlay(autoPrepare: false);
        final controller = _controller(
          await _configuredSettings(),
          capture,
          overlay,
        );
        await controller.start();
        final translation = controller.translate();
        await overlay.prepareSent.future;
        final cancellation = Completer<void>();
        capture.cancelResult = cancellation.future;
        Future<void>? cancelling;
        if (rotate) {
          capture.emitEvent(
            const ScreenCaptureEvent(
              state: ScreenCaptureSessionState.ready,
              geometryVersion: 2,
            ),
          );
          await Future<void>.delayed(Duration.zero);
        } else {
          cancelling = controller.cancelTranslation();
        }
        await controller.stop();
        cancellation.complete();
        await cancelling;
        await translation;
        await Future<void>.delayed(Duration.zero);
        expect(controller.state, ScreenTranslationState.stopped);
        await controller.start();
        expect(controller.state, ScreenTranslationState.ready);
        controller.dispose();
      },
    );
  }

  test(
    'late old translation cannot consume the next capture confirmation',
    () async {
      final capture = _FakeCapture();
      final overlay = _FakeOverlay();
      final service = _FakeService(
        result: const ImageTranslationResult(
          imageSize: Size(100, 50),
          regions: [],
        ),
      );
      final controller = _controller(
        await _configuredSettings(),
        capture,
        overlay,
        serviceFactory: () => service,
      );
      await controller.start();
      final first = controller.translate();
      await service.started.future;
      await controller.cancelTranslation();
      overlay.autoPrepare = false;
      final second = controller.translate();
      await Future<void>.delayed(Duration.zero);
      final preparation = overlay.sent.lastWhere(
        (m) => m['type'] == 'prepareCapture',
      );
      service.complete();
      await first;
      overlay.emit({
        'version': 1,
        'type': 'capturePrepared',
        'sessionId': preparation['sessionId'],
        'requestId': preparation['requestId'],
      });
      await Future<void>.delayed(Duration.zero);
      expect(capture.captureCalls, 2);
      await controller.cancelTranslation();
      service.complete();
      await second;
      controller.dispose();
    },
  );

  test(
    'completed result snapshots retain their frame and result request identity',
    () async {
      final overlay = _FakeOverlay();
      final controller = _controller(
        await _configuredSettings(),
        _FakeCapture(),
        overlay,
        serviceFactory: () => _ImmediateService(
          const ImageTranslationResult(imageSize: Size(100, 50), regions: []),
        ),
      );
      await controller.start();
      await controller.translate();
      final result = overlay.sent.lastWhere((m) => m['type'] == 'result');
      overlay.sent.clear();
      overlay.emit({
        'version': 1,
        'type': 'ready',
        'sessionId': result['sessionId'],
      });
      await Future<void>.delayed(Duration.zero);
      expect(overlay.sent.map((m) => m['type']), [
        'state',
        'capturedFrame',
        'result',
      ]);
      for (final message in overlay.sent) {
        expect(message['requestId'], result['requestId']);
        expect(message['requestId'], isNotNull);
      }
      controller.dispose();
    },
  );

  test(
    'does not request permissions when translation is not configured',
    () async {
      final capture = _FakeCapture();
      final overlay = _FakeOverlay();
      final controller = _controller(TranslationSettings(), capture, overlay);

      await expectLater(
        controller.start(),
        throwsA(isA<TranslationControllerException>()),
      );

      expect(controller.errorCode, 'translation_not_configured');
      expect(capture.permissionCalls, 0);
      expect(overlay.showCalls, 0);
      controller.dispose();
    },
  );

  test(
    'starts, captures a binary frame, and completes a translation',
    () async {
      final capture = _FakeCapture();
      final overlay = _FakeOverlay();
      final settings = await _configuredSettings();
      final service = _FakeService(
        result: const ImageTranslationResult(
          imageSize: Size(100, 50),
          regions: [
            ImageTextRegion(
              normalizedRect: Rect.fromLTRB(0, 0, 1, 1),
              sourceText: 'source',
              translatedText: '译文',
            ),
          ],
        ),
      );
      final controller = _controller(
        settings,
        capture,
        overlay,
        serviceFactory: () => service,
      );

      await controller.start(
        appLocale: const Locale('zh'),
        deviceLocale: const Locale('en'),
      );
      expect(controller.state, ScreenTranslationState.ready);
      expect(capture.startCalls, 1);
      expect(overlay.showCalls, 1);

      final translation = controller.translate();
      await service.started.future;
      service.complete();
      await translation;
      expect(controller.state, ScreenTranslationState.result);
      expect(service.receivedBytes, isA<Uint8List>());
      expect(
        overlay.sent.any(
          (message) =>
              message['type'] == 'capturedFrame' ||
              (message['type'] == 'state' &&
                  (message['payload'] as Map)['hasFrame'] == true),
        ),
        isTrue,
      );
      controller.dispose();
    },
  );

  test('cancelling a pending translation ignores its late result', () async {
    final capture = _FakeCapture();
    final overlay = _FakeOverlay();
    final settings = await _configuredSettings();
    final service = _FakeService(
      result: const ImageTranslationResult(
        imageSize: Size(100, 50),
        regions: [],
      ),
    );
    final controller = _controller(
      settings,
      capture,
      overlay,
      serviceFactory: () => service,
    );
    await controller.start();

    final translating = controller.translate();
    await service.started.future;
    expect(controller.state, ScreenTranslationState.translating);
    await controller.cancelTranslation();
    expect(controller.state, ScreenTranslationState.ready);

    service.complete();
    await translating;
    expect(controller.state, ScreenTranslationState.ready);
    expect(
      overlay.sent.where((message) => message['type'] == 'result'),
      isEmpty,
    );
    controller.dispose();
  });

  test('stop invalidates the session and prevents a late result', () async {
    final capture = _FakeCapture();
    final overlay = _FakeOverlay();
    final settings = await _configuredSettings();
    final service = _FakeService(
      result: const ImageTranslationResult(
        imageSize: Size(100, 50),
        regions: [],
      ),
    );
    final controller = _controller(
      settings,
      capture,
      overlay,
      serviceFactory: () => service,
    );
    await controller.start();
    final translating = controller.translate();
    await service.started.future;

    await controller.stop();
    service.complete();
    await translating;

    expect(controller.state, ScreenTranslationState.stopped);
    expect(capture.stopCalls, 1);
    expect(overlay.hideCalls, 1);
    controller.dispose();
  });

  test(
    'refresh during permission flow does not cancel a pending start',
    () async {
      final capture = _FakeCapture();
      final permission = Completer<ScreenCapturePermissionResult>();
      capture.permissionResult = permission.future;
      final overlay = _FakeOverlay();
      final controller = _controller(
        await _configuredSettings(),
        capture,
        overlay,
      );

      final starting = controller.start();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, ScreenTranslationState.starting);

      await controller.refresh();
      expect(controller.state, ScreenTranslationState.starting);

      permission.complete(const ScreenCapturePermissionResult(granted: true));
      await starting;
      expect(controller.state, ScreenTranslationState.ready);
      expect(
        overlay.sent.where((message) => message['type'] == 'handshake'),
        isNotEmpty,
      );
      controller.dispose();
    },
  );

  test(
    'a stale stopped refresh cannot cancel a session started meanwhile',
    () async {
      final capture = _FakeCapture();
      final stateRead = Completer<ScreenCaptureSessionInfo>();
      capture.sessionStateResult = stateRead.future;
      final controller = _controller(
        await _configuredSettings(),
        capture,
        _FakeOverlay(),
      );

      final refreshing = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      await controller.start();
      stateRead.complete(
        const ScreenCaptureSessionInfo(
          state: ScreenCaptureSessionState.stopped,
        ),
      );
      await refreshing;
      expect(controller.state, ScreenTranslationState.ready);
      controller.dispose();
    },
  );

  test('stopping during permission flow ignores late authorization', () async {
    final capture = _FakeCapture();
    final permission = Completer<ScreenCapturePermissionResult>();
    capture.permissionResult = permission.future;
    final controller = _controller(
      await _configuredSettings(),
      capture,
      _FakeOverlay(),
    );

    final starting = controller.start();
    await Future<void>.delayed(Duration.zero);
    await controller.stop();
    permission.complete(const ScreenCapturePermissionResult(granted: true));

    await expectLater(starting, throwsA(isA<Object>()));
    expect(controller.state, ScreenTranslationState.stopped);
    expect(capture.startCalls, 0);
    await controller.start();
    expect(controller.state, ScreenTranslationState.ready);
    controller.dispose();
  });

  test('a cached overlay can complete two session handshakes', () async {
    final capture = _FakeCapture();
    final overlay = _FakeOverlay();
    final controller = _controller(
      await _configuredSettings(),
      capture,
      overlay,
    );

    await controller.start();
    await controller.stop();
    await controller.start();

    expect(controller.state, ScreenTranslationState.ready);
    expect(
      overlay.sent.where((message) => message['type'] == 'handshake'),
      hasLength(2),
    );
    expect(capture.startCalls, 2);
    controller.dispose();
  });

  test('ready state is re-sent when display geometry changes', () async {
    final capture = _FakeCapture();
    final overlay = _FakeOverlay();
    final controller = _controller(
      await _configuredSettings(),
      capture,
      overlay,
    );

    await controller.start();
    final stateMessagesBefore = overlay.sent
        .where((message) => message['type'] == 'state')
        .length;
    capture.emitEvent(
      const ScreenCaptureEvent(
        state: ScreenCaptureSessionState.ready,
        width: 50,
        height: 100,
        geometryVersion: 2,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      overlay.sent.where((message) => message['type'] == 'state').length,
      greaterThan(stateMessagesBefore),
    );
    controller.dispose();
  });

  test(
    'dismissing a result releases it and permits another translation',
    () async {
      final capture = _FakeCapture();
      final overlay = _FakeOverlay();
      final result = const ImageTranslationResult(
        imageSize: Size(100, 50),
        regions: [],
      );
      final service = _ImmediateService(result);
      final controller = _controller(
        await _configuredSettings(),
        capture,
        overlay,
        serviceFactory: () => service,
      );

      await controller.start();
      await controller.translate();
      expect(controller.state, ScreenTranslationState.result);
      await controller.dismissResult();
      expect(controller.state, ScreenTranslationState.ready);
      await controller.translate();
      expect(controller.state, ScreenTranslationState.result);
      expect(service.translateCalls, 2);
      controller.dispose();
    },
  );

  test('openSettings from the current session brings the app forward', () async {
    final overlay = _FakeOverlay();
    final controller = _controller(
      await _configuredSettings(),
      _FakeCapture(),
      overlay,
    );
    addTearDown(controller.dispose);
    await controller.start();
    final sessionId = overlay.sent.firstWhere(
      (message) => message['type'] == 'handshake',
    )['sessionId'];
    var requests = 0;
    final subscription = controller.settingsRequests.listen((_) => requests++);
    addTearDown(subscription.cancel);

    overlay.emit({
      'version': 1,
      'type': 'openSettings',
      'sessionId': sessionId,
    });
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    expect(overlay.openAppCalls, 1);

    overlay.emit(const {
      'version': 1,
      'type': 'openSettings',
      'sessionId': 'other',
    });
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    expect(overlay.openAppCalls, 1);
  });

  test(
    'geometry change during capture returns to ready and ignores old work',
    () async {
      final capture = _FakeCapture();
      final overlay = _FakeOverlay(autoPrepare: false);
      final controller = _controller(
        await _configuredSettings(),
        capture,
        overlay,
        serviceFactory: () => _ImmediateService(
          const ImageTranslationResult(imageSize: Size(100, 50), regions: []),
        ),
      );
      await controller.start();
      final translating = controller.translate();
      await overlay.prepareSent.future;
      capture.emitEvent(
        const ScreenCaptureEvent(
          state: ScreenCaptureSessionState.ready,
          width: 50,
          height: 100,
          geometryVersion: 2,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await translating;
      expect(controller.state, ScreenTranslationState.ready);
      expect(
        overlay.sent.where((message) => message['type'] == 'result'),
        isEmpty,
      );
      controller.dispose();
    },
  );

  test('geometry change during translation ignores the abort error', () async {
    final capture = _FakeCapture();
    final overlay = _FakeOverlay();
    final service = _AbortOnTriggerService();
    final controller = _controller(
      await _configuredSettings(),
      capture,
      overlay,
      serviceFactory: () => service,
    );
    await controller.start();
    final translating = controller.translate();
    await service.started.future;

    capture.emitEvent(
      const ScreenCaptureEvent(
        state: ScreenCaptureSessionState.ready,
        width: 50,
        height: 100,
        geometryVersion: 2,
      ),
    );
    await translating;
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, ScreenTranslationState.ready);
    expect(controller.errorCode, isNull);
    expect(
      overlay.sent.where((message) => message['type'] == 'error'),
      isEmpty,
    );
    controller.dispose();
  });
}

ScreenTranslationController _controller(
  TranslationSettings settings,
  _FakeCapture capture,
  _FakeOverlay overlay, {
  ImageTranslationServiceFactory? serviceFactory,
}) {
  return ScreenTranslationController(
    settings: settings,
    screenCapture: capture,
    overlay: overlay,
    serviceFactory: serviceFactory,
    appLocale: () => const Locale('en'),
    deviceLocale: () => const Locale('en'),
  );
}

Future<TranslationSettings> _configuredSettings() async {
  final settings = TranslationSettings();
  await settings.save(
    provider: TranslationProvider.llm,
    apiBaseUrl: TranslationSettings.defaultApiBaseUrl,
    apiKey: 'test-key',
    model: TranslationSettings.defaultModel,
    systemPrompt: TranslationSettings.defaultSystemPrompt,
    targetLanguage: 'zh',
    googleApiKey: '',
    microsoftApiKey: '',
    microsoftRegion: '',
  );
  return settings;
}

class _FakeCapture implements ScreenCaptureGateway {
  final StreamController<ScreenCaptureEvent> _events =
      StreamController<ScreenCaptureEvent>.broadcast();
  int permissionCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int captureCalls = 0;
  Future<void>? cancelResult;
  Future<ScreenCapturePermissionResult>? permissionResult;
  Future<ScreenCaptureSessionInfo>? sessionStateResult;
  ScreenCaptureSessionInfo sessionState = const ScreenCaptureSessionInfo(
    state: ScreenCaptureSessionState.stopped,
  );

  @override
  Stream<ScreenCaptureEvent> get events => _events.stream;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<ScreenCapturePermissionResult> requestPermission() async {
    permissionCalls++;
    return permissionResult ??
        const ScreenCapturePermissionResult(granted: true);
  }

  @override
  Future<ScreenCaptureSessionInfo> startSession() async {
    startCalls++;
    _events.add(
      const ScreenCaptureEvent(
        state: ScreenCaptureSessionState.ready,
        width: 100,
        height: 50,
        geometryVersion: 1,
      ),
    );
    return const ScreenCaptureSessionInfo(
      state: ScreenCaptureSessionState.ready,
      width: 100,
      height: 50,
      geometryVersion: 1,
    );
  }

  @override
  Future<CapturedFrame> captureFrame() async {
    captureCalls++;
    return CapturedFrame(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      width: 100,
      height: 50,
      frameId: 1,
      geometryVersion: 1,
    );
  }

  @override
  Future<void> cancelCapture() async {
    await cancelResult;
  }

  @override
  Future<void> stopSession() async {
    stopCalls++;
  }

  @override
  Future<ScreenCaptureSessionInfo> getSessionState() async {
    return sessionStateResult ?? sessionState;
  }

  void emitEvent(ScreenCaptureEvent event) => _events.add(event);
}

class _FakeOverlay implements OverlayController {
  _FakeOverlay({this.autoPrepare = true});

  bool autoPrepare;
  void emit(TranslationBridgeMessage message) => _messages.add(message);
  final StreamController<TranslationBridgeMessage> _messages =
      StreamController<TranslationBridgeMessage>.broadcast();
  final List<TranslationBridgeMessage> sent = [];
  final Completer<void> prepareSent = Completer<void>();
  int showCalls = 0;
  int hideCalls = 0;
  int openAppCalls = 0;

  @override
  Stream<TranslationBridgeMessage> get messages => _messages.stream;

  @override
  Future<bool> isPermissionGranted() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> show() async => showCalls++;

  @override
  Future<void> hide() async => hideCalls++;

  @override
  Future<bool> bind() async {
    return true;
  }

  @override
  Future<void> openApp() async => openAppCalls++;

  @override
  Future<void> send(TranslationBridgeMessage message) async {
    sent.add(message);
    if (message['type'] == 'handshake') {
      _messages.add({
        'version': 1,
        'type': 'ready',
        'sessionId': message['sessionId'],
      });
    }
    if (message['type'] == 'prepareCapture') {
      if (!prepareSent.isCompleted) {
        prepareSent.complete();
      }
      if (autoPrepare) {
        _messages.add({
          'version': 1,
          'type': 'capturePrepared',
          'sessionId': message['sessionId'],
          'requestId': message['requestId'],
        });
      }
    }
  }
}

class _ImmediateService extends ImageTranslationService {
  _ImmediateService(this.result);

  final ImageTranslationResult result;
  int translateCalls = 0;

  @override
  Future<ImageTranslationResult> translate({
    required Uint8List imageBytes,
    required TranslationSettings settings,
    required Locale? appLocale,
    required Locale deviceLocale,
    Future<void>? abortTrigger,
    void Function(ImageTranslationProgress progress)? onProgress,
  }) async {
    translateCalls++;
    return result;
  }
}

class _AbortOnTriggerService extends ImageTranslationService {
  final Completer<void> started = Completer<void>();

  @override
  Future<ImageTranslationResult> translate({
    required Uint8List imageBytes,
    required TranslationSettings settings,
    required Locale? appLocale,
    required Locale deviceLocale,
    Future<void>? abortTrigger,
    void Function(ImageTranslationProgress progress)? onProgress,
  }) async {
    if (!started.isCompleted) started.complete();
    await abortTrigger;
    throw StateError('The request was aborted.');
  }
}

class _DelayedHideOverlay extends _FakeOverlay {
  final hiding = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> hide() async {
    await super.hide();
    if (!hiding.isCompleted) hiding.complete();
    await release.future;
  }
}

class _DelayedCloseService extends ImageTranslationService {
  final closing = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> close() async {
    if (!closing.isCompleted) closing.complete();
    await release.future;
  }
}

class _FakeService extends ImageTranslationService {
  _FakeService({required this.result});

  final ImageTranslationResult result;
  final Completer<void> started = Completer<void>();
  Completer<ImageTranslationResult>? _completion;
  Uint8List? receivedBytes;

  @override
  Future<ImageTranslationResult> translate({
    required Uint8List imageBytes,
    required TranslationSettings settings,
    required Locale? appLocale,
    required Locale deviceLocale,
    Future<void>? abortTrigger,
    void Function(ImageTranslationProgress progress)? onProgress,
  }) {
    receivedBytes = imageBytes;
    onProgress?.call(
      const ImageTranslationProgress(stage: ImageTranslationStage.translating),
    );
    if (!started.isCompleted) started.complete();
    _completion = Completer<ImageTranslationResult>();
    return _completion!.future;
  }

  void complete() {
    _completion?.complete(result);
  }
}
