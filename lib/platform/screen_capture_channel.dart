import 'dart:async';
import 'package:flutter/services.dart';

import '../models/screen_translation_models.dart';

abstract interface class ScreenCaptureGateway {
  /// Requests the Android 13+ notification permission when needed.
  ///
  /// A denial is intentionally non-fatal: foreground-service rules still
  /// apply, but screen-capture permission has a separate user-facing result.
  Future<bool> requestNotificationPermission() => Future<bool>.value(true);

  Future<ScreenCapturePermissionResult> requestPermission();

  Future<ScreenCaptureSessionInfo> startSession();

  Future<CapturedFrame> captureFrame();

  Future<void> cancelCapture();

  Future<void> stopSession();

  Future<ScreenCaptureSessionInfo> getSessionState();

  Stream<ScreenCaptureEvent> get events;
}

class ScreenCaptureException implements Exception {
  const ScreenCaptureException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class ScreenCaptureUnavailableException extends ScreenCaptureException {
  const ScreenCaptureUnavailableException([
    String message = 'Screen capture is unavailable on this device.',
  ]) : super('unavailable', message);
}

class ScreenCaptureChannel implements ScreenCaptureGateway {
  const ScreenCaptureChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName),
      _events = const EventChannel(_eventsChannelName);

  static const String _channelName = 'com.rehtt.foxlingo/screen_capture';
  static const String _eventsChannelName =
      'com.rehtt.foxlingo/screen_capture_events';

  final MethodChannel _channel;
  final EventChannel _events;

  @override
  Stream<ScreenCaptureEvent> get events {
    return _events.receiveBroadcastStream().map(_parseEvent);
  }

  @override
  Future<bool> requestNotificationPermission() async {
    final value = await _invoke<Object?>('requestNotificationPermission');
    return value != false;
  }

  @override
  Future<ScreenCapturePermissionResult> requestPermission() async {
    final value = await _invoke<Object?>('requestPermission');
    if (value is bool) {
      return ScreenCapturePermissionResult(granted: value);
    }
    final map = _asMap(value, 'requestPermission');
    return ScreenCapturePermissionResult(
      granted: map['granted'] == true,
      cancelled: map['cancelled'] == true,
    );
  }

  @override
  Future<ScreenCaptureSessionInfo> startSession() async {
    return _parseSession(await _invoke<Object?>('startSession'));
  }

  @override
  Future<CapturedFrame> captureFrame() async {
    final map = _asMap(await _invoke<Object?>('captureFrame'), 'captureFrame');
    final bytes = map['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      throw const ScreenCaptureException(
        'capture_failed',
        'The screen capture did not return image data.',
      );
    }
    return CapturedFrame(
      bytes: bytes,
      width: _positiveInt(map['width'], 'width'),
      height: _positiveInt(map['height'], 'height'),
      frameId: _nonNegativeInt(map['frameId'], 'frameId'),
      geometryVersion: _nonNegativeInt(
        map['geometryVersion'],
        'geometryVersion',
      ),
    );
  }

  @override
  Future<void> cancelCapture() => _invoke<void>('cancelCapture');

  @override
  Future<void> stopSession() => _invoke<void>('stopSession');

  @override
  Future<ScreenCaptureSessionInfo> getSessionState() async {
    return _parseSession(await _invoke<Object?>('getSessionState'));
  }

  Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on PlatformException catch (error) {
      if (error.code == 'unimplemented') {
        throw ScreenCaptureUnavailableException(
          error.message ?? 'Screen capture is unavailable on this device.',
        );
      }
      throw ScreenCaptureException(
        error.code,
        error.message ?? 'Screen capture operation failed.',
      );
    }
  }

  static Map<String, dynamic> _asMap(Object? value, String operation) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    throw ScreenCaptureException(
      'invalid_response',
      'Screen capture returned an invalid response for $operation.',
    );
  }

  static int _positiveInt(Object? value, String field) {
    if (value is int && value > 0) {
      return value;
    }
    throw ScreenCaptureException(
      'invalid_response',
      'Screen capture returned an invalid $field.',
    );
  }

  static int _nonNegativeInt(Object? value, String field) {
    if (value is int && value >= 0) {
      return value;
    }
    throw ScreenCaptureException(
      'invalid_response',
      'Screen capture returned an invalid $field.',
    );
  }

  static ScreenCaptureSessionInfo _parseSession(Object? value) {
    final map = _asMap(value, 'session');
    final state = switch (map['state']) {
      'starting' => ScreenCaptureSessionState.starting,
      'ready' => ScreenCaptureSessionState.ready,
      'error' => ScreenCaptureSessionState.error,
      _ => ScreenCaptureSessionState.stopped,
    };
    return ScreenCaptureSessionInfo(
      state: state,
      width: map['width'] is int ? map['width'] as int : 0,
      height: map['height'] is int ? map['height'] as int : 0,
      geometryVersion: map['geometryVersion'] is int
          ? map['geometryVersion'] as int
          : 0,
    );
  }

  static ScreenCaptureEvent _parseEvent(Object? value) {
    final map = _asMap(value, 'event');
    final session = _parseSession(map);
    return ScreenCaptureEvent(
      state: session.state,
      width: session.width,
      height: session.height,
      geometryVersion: session.geometryVersion,
      errorCode: map['errorCode'] as String?,
      message: map['message'] as String?,
    );
  }
}
