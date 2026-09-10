import 'dart:typed_data';

enum ScreenCaptureSessionState { stopped, starting, ready, error }

class ScreenCapturePermissionResult {
  const ScreenCapturePermissionResult({
    required this.granted,
    this.cancelled = false,
  });

  final bool granted;
  final bool cancelled;
}

class ScreenCaptureSessionInfo {
  const ScreenCaptureSessionInfo({
    required this.state,
    this.width = 0,
    this.height = 0,
    this.geometryVersion = 0,
  });

  final ScreenCaptureSessionState state;
  final int width;
  final int height;
  final int geometryVersion;

  bool get isReady => state == ScreenCaptureSessionState.ready;
}

class ScreenCaptureEvent {
  const ScreenCaptureEvent({
    required this.state,
    this.width = 0,
    this.height = 0,
    this.geometryVersion = 0,
    this.errorCode,
    this.message,
  });

  final ScreenCaptureSessionState state;
  final int width;
  final int height;
  final int geometryVersion;
  final String? errorCode;
  final String? message;
}

class CapturedFrame {
  const CapturedFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.frameId,
    required this.geometryVersion,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int frameId;
  final int geometryVersion;
}
