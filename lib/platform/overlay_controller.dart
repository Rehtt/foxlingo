import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'translation_bridge.dart';

abstract interface class OverlayController {
  Future<bool> isPermissionGranted();

  Future<bool> requestPermission();

  Future<void> show();

  Future<void> hide();

  Future<bool> bind();

  Stream<TranslationBridgeMessage> get messages;

  Future<void> send(TranslationBridgeMessage message);

  Future<void> openApp();
}

/// Position math for the 56dp bubble used by the overlay window.
///
/// The production window is opened with `centerRight` gravity. The plugin
/// therefore reports x as the distance from the right edge and y as the
/// offset from the vertical center, both in logical pixels.
class OverlayPositioning {
  const OverlayPositioning._();

  static const double bubbleSize = 56;

  static OverlayPosition clampBubblePosition(
    OverlayPosition position,
    Size displaySize,
  ) {
    final maxRightOffset = (displaySize.width - bubbleSize).clamp(
      0.0,
      double.infinity,
    );
    final maxVerticalOffset = ((displaySize.height - bubbleSize) / 2).clamp(
      0.0,
      double.infinity,
    );
    return OverlayPosition(
      position.x.clamp(0.0, maxRightOffset).toDouble(),
      position.y.clamp(-maxVerticalOffset, maxVerticalOffset).toDouble(),
    );
  }

  /// Converts a center-right overlay offset into a window-local bubble rect.
  static Rect bubbleRect(OverlayPosition position, Size windowSize) {
    final right = windowSize.width - position.x;
    final centerY = windowSize.height / 2 + position.y;
    final maxLeft = (windowSize.width - bubbleSize).clamp(0.0, double.infinity);
    final maxTop = (windowSize.height - bubbleSize).clamp(0.0, double.infinity);
    final left = (right - bubbleSize).clamp(0.0, maxLeft);
    final top = (centerY - bubbleSize / 2).clamp(0.0, maxTop);
    return Rect.fromLTWH(left, top, bubbleSize, bubbleSize);
  }
}

class FlutterOverlayController implements OverlayController {
  FlutterOverlayController({TranslationBridge? bridge})
    : _bridge = bridge ?? TranslationBridge.main();

  final TranslationBridge _bridge;

  @override
  Stream<TranslationBridgeMessage> get messages => _bridge.messages;

  @override
  Future<bool> isPermissionGranted() {
    return FlutterOverlayWindow.isPermissionGranted();
  }

  @override
  Future<bool> requestPermission() async {
    return await FlutterOverlayWindow.requestPermission() ?? false;
  }

  @override
  Future<void> show() async {
    await FlutterOverlayWindow.showOverlay(
      width: 56,
      height: 56,
      alignment: OverlayAlignment.centerRight,
      flag: OverlayFlag.defaultFlag,
      enableDrag: true,
      positionGravity: PositionGravity.none,
      overlayTitle: 'FoxLingo',
    );
  }

  @override
  Future<void> hide() async {
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Future<bool> bind() => _bridge.bindOverlay();

  @override
  Future<void> send(TranslationBridgeMessage message) async {
    await _bridge.send(message);
  }

  @override
  Future<void> openApp() => _bridge.openMainActivity();

  /// Releases the Dart-side channel when an injected controller is no longer
  /// used. The production controller lives for the process lifetime.
  void dispose() {
    _bridge.dispose();
  }
}
