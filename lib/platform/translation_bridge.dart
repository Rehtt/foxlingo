import 'dart:async';

import 'package:flutter/services.dart';

typedef TranslationBridgeMessage = Map<String, dynamic>;

/// The application-owned channel between the main and overlay Flutter engines.
///
/// Unlike flutter_overlay_window's legacy JSON channel, this channel uses the
/// standard codec so screenshot bytes remain Uint8List values instead of being
/// converted to Base64 or embedded in JSON.
class TranslationBridge {
  TranslationBridge.main({BasicMessageChannel<Object?>? channel})
    : this._(
        channel ??
            const BasicMessageChannel<Object?>(
              _channelName,
              StandardMessageCodec(),
            ),
        isMain: true,
      );

  TranslationBridge.overlay({BasicMessageChannel<Object?>? channel})
    : this._(
        channel ??
            const BasicMessageChannel<Object?>(
              _channelName,
              StandardMessageCodec(),
            ),
        isMain: false,
      );

  TranslationBridge._(this._channel, {required this.isMain}) {
    _channel.setMessageHandler(_handleMessage);
  }

  static const String _channelName = 'com.rehtt.foxlingo/translation_bridge';
  static const String _controlChannelName =
      'com.rehtt.foxlingo/translation_bridge_control';

  final BasicMessageChannel<Object?> _channel;
  final bool isMain;
  final StreamController<TranslationBridgeMessage> _messages =
      StreamController<TranslationBridgeMessage>.broadcast();
  final MethodChannel _controlChannel = const MethodChannel(
    _controlChannelName,
  );

  Stream<TranslationBridgeMessage> get messages => _messages.stream;

  Future<Object?> _handleMessage(Object? message) async {
    if (message is Map) {
      try {
        _messages.add(Map<String, dynamic>.from(message));
      } on Object {
        // Invalid messages are deliberately ignored. A malformed overlay
        // message must not tear down the translation session.
      }
    }
    return null;
  }

  Future<void> send(TranslationBridgeMessage message) async {
    await _channel.send(message);
  }

  /// Binds the cached overlay engine to the native bridge.
  ///
  /// The overlay plugin starts its engine asynchronously. The caller may
  /// retry this method until it returns true before waiting for `ready`.
  Future<bool> bindOverlay() async {
    if (!isMain) {
      return false;
    }
    try {
      return await _controlChannel.invokeMethod<bool>('bindOverlay') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Returns the real display size in logical pixels for the overlay engine.
  Future<Size?> displaySize() async {
    if (isMain) {
      return null;
    }
    try {
      final value = await _controlChannel.invokeMethod<Object?>('displaySize');
      if (value is! Map) {
        return null;
      }
      final width = value['width'];
      final height = value['height'];
      if (width is! num || height is! num || width <= 0 || height <= 0) {
        return null;
      }
      return Size(width.toDouble(), height.toDouble());
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  void dispose() {
    _channel.setMessageHandler(null);
    unawaited(_messages.close());
  }
}
