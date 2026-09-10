import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxlingo/models/image_translation_models.dart';
import 'package:foxlingo/platform/overlay_controller.dart';
import 'package:foxlingo/platform/translation_bridge.dart';
import 'package:foxlingo/widgets/translation_overlay_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native error during preparation exposes a close button', (
    tester,
  ) async {
    final bridge = _TestBridge();
    final flags = <String>[];
    const channel = MethodChannel('x-slayer/overlay');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
        if (call.method == 'updateFlag') {
          flags.add((call.arguments as Map)['flag'] as String);
        }
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(TranslationOverlayApp(bridge: bridge));
    bridge.emit(const {'version': 1, 'type': 'handshake', 'sessionId': 's1'});
    await tester.pump();
    bridge.emit(const {
      'version': 1,
      'type': 'state',
      'sessionId': 's1',
      'requestId': 'r1',
      'payload': {'state': 'capturing'},
    });
    await tester.pump();
    bridge.emit(const {
      'version': 1,
      'type': 'prepareCapture',
      'sessionId': 's1',
      'requestId': 'r1',
    });
    await tester.pump();
    bridge.emit(const {
      'version': 1,
      'type': 'state',
      'sessionId': 's1',
      'payload': {'state': 'error', 'errorMessage': 'Capture failed'},
    });
    await tester.pumpAndSettle();
    expect(find.text('Capture failed'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(flags.last, 'defaultFlag');
    await tester.tap(find.text('Close'));
    expect(bridge.sent.last['type'], 'dismiss');
    await bridge.close();
  });

  testWidgets(
    'each full-screen transition restores the latest dragged position',
    (tester) async {
      final bridge = _TestBridge();
      var position = <String, double>{'x': 10, 'y': 20};
      const main = MethodChannel('x-slayer/overlay_channel');
      const overlay = MethodChannel('x-slayer/overlay');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(main, (
        call,
      ) async {
        if (call.method == 'getOverlayPosition') return position;
        if (call.method == 'moveOverlay') {
          final args = call.arguments as Map;
          position = {
            'x': (args['x'] as num).toDouble(),
            'y': (args['y'] as num).toDouble(),
          };
        }
        return true;
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        overlay,
        (_) async => true,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          main,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          overlay,
          null,
        );
      });
      await tester.pumpWidget(TranslationOverlayApp(bridge: bridge));
      bridge.emit(const {'version': 1, 'type': 'handshake', 'sessionId': 's1'});
      await tester.pump();
      bridge.emit(const {
        'version': 1,
        'type': 'state',
        'sessionId': 's1',
        'payload': {'state': 'ready'},
      });
      await tester.pumpAndSettle();
      for (var i = 1; i <= 2; i++) {
        final dragged = <String, double>{'x': i * 100.0, 'y': i * 50.0};
        position = dragged;
        bridge.emit({
          'version': 1,
          'type': 'state',
          'sessionId': 's1',
          'requestId': 'r$i',
          'payload': {'state': 'translating'},
        });
        await tester.pumpAndSettle();
        expect(position, {'x': 0.0, 'y': 0.0});
        bridge.emit(const {
          'version': 1,
          'type': 'state',
          'sessionId': 's1',
          'payload': {'state': 'ready'},
        });
        await tester.pumpAndSettle();
        expect(position, dragged);
      }
      await bridge.close();
    },
  );

  test('clamps center-right bubble coordinates to the visible display', () {
    const displaySize = Size(1080, 1920);
    final top = OverlayPositioning.clampBubblePosition(
      const OverlayPosition(-20, -1000),
      displaySize,
    );
    expect(top.x, 0);
    expect(top.y, -932);
    final bottom = OverlayPositioning.clampBubblePosition(
      const OverlayPosition(2000, 1000),
      displaySize,
    );
    expect(bottom.x, 1024);
    expect(bottom.y, 932);
  });

  testWidgets('result message changes the overlay to a closable result', (
    tester,
  ) async {
    final bridge = _TestBridge();
    final windowCalls = <MethodCall>[];
    final overlayChannel = const MethodChannel('x-slayer/overlay');
    final mainChannel = const MethodChannel('x-slayer/overlay_channel');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      overlayChannel,
      (call) async {
        windowCalls.add(call);
        return true;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      mainChannel,
      (call) async {
        windowCalls.add(call);
        if (call.method == 'getOverlayPosition') {
          return <String, double>{'x': 100, 'y': 20};
        }
        return true;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        overlayChannel,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        mainChannel,
        null,
      );
    });
    await tester.pumpWidget(TranslationOverlayApp(bridge: bridge));
    await tester.pumpAndSettle();

    bridge.emit(const {'version': 1, 'type': 'handshake', 'sessionId': 's1'});
    await tester.pump();
    bridge.emit(const {
      'version': 1,
      'type': 'state',
      'sessionId': 's1',
      'requestId': 'r1',
      'payload': {'state': 'translating', 'locale': 'en'},
    });
    await tester.pump();
    bridge.emit({
      'version': 1,
      'type': 'result',
      'sessionId': 's1',
      'requestId': 'r1',
      'payload': <String, dynamic>{
        'result': const ImageTranslationResult(
          imageSize: Size(100, 50),
          regions: [
            ImageTextRegion(
              normalizedRect: Rect.fromLTRB(0, 0, 1, 1),
              sourceText: 'source',
              translatedText: 'translated',
            ),
          ],
        ).toJson(),
      },
    });
    await tester.pump();
    await tester.pump();

    expect(find.text('Close'), findsOneWidget);
    expect(find.text('translated'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(bridge.sent.last['type'], 'dismiss');

    bridge.emit(const {
      'version': 1,
      'type': 'state',
      'sessionId': 's1',
      'payload': {'state': 'ready', 'locale': 'en'},
    });
    await tester.pump();
    bridge.emit(const {
      'version': 1,
      'type': 'state',
      'sessionId': 's1',
      'requestId': 'r2',
      'payload': {'state': 'translating', 'locale': 'en'},
    });
    await tester.pump();
    bridge.emit(const {
      'version': 1,
      'type': 'result',
      'sessionId': 's1',
      'requestId': 'r2',
      'payload': {
        'result': {
          'imageSize': [100, 50],
          'regions': [],
        },
      },
    });
    await tester.pump();
    await tester.pump();
    expect(find.text('No text was recognized in this image.'), findsOneWidget);
    expect(
      windowCalls.any(
        (call) =>
            call.method == 'resizeOverlay' &&
            (call.arguments as Map)['width'] == 56 &&
            (call.arguments as Map)['height'] == 56 &&
            (call.arguments as Map)['enableDrag'] == true,
      ),
      isTrue,
    );
    expect(
      windowCalls.any(
        (call) =>
            call.method == 'moveOverlay' &&
            (call.arguments as Map)['x'] == 100 &&
            (call.arguments as Map)['y'] == 20,
      ),
      isTrue,
    );
    await bridge.close();
  });

  testWidgets('ready after prepare restores the bubble and drops the request', (
    tester,
  ) async {
    final bridge = _TestBridge();
    await tester.pumpWidget(TranslationOverlayApp(bridge: bridge));
    await tester.pump();
    bridge.emit(const {'version': 1, 'type': 'handshake', 'sessionId': 's1'});
    await tester.pump();
    bridge.emit(const {
      'version': 1,
      'type': 'state',
      'sessionId': 's1',
      'requestId': 'r1',
      'payload': {'state': 'capturing', 'locale': 'en'},
    });
    await tester.pump();
    bridge.emit(const {
      'version': 1,
      'type': 'prepareCapture',
      'sessionId': 's1',
      'requestId': 'r1',
    });
    await tester.pump();
    bridge.emit(const {
      'version': 1,
      'type': 'state',
      'sessionId': 's1',
      'payload': {'state': 'ready', 'locale': 'en'},
    });
    await tester.pump();

    expect(find.byIcon(Icons.translate), findsOneWidget);
    await tester.tap(find.byIcon(Icons.translate));
    await tester.pump();
    expect(
      bridge.sent.where((message) => message['type'] == 'translate'),
      hasLength(1),
    );
    bridge.emit(const {
      'version': 1,
      'type': 'state',
      'sessionId': 's1',
      'requestId': 'r1',
      'payload': {'state': 'result', 'locale': 'en'},
    });
    await tester.pump();
    expect(find.byIcon(Icons.translate), findsOneWidget);
    bridge.emit(const {
      'version': 1,
      'type': 'result',
      'sessionId': 's1',
      'requestId': 'r1',
      'payload': {
        'result': {
          'imageSize': [100, 50],
          'regions': [],
        },
      },
    });
    await tester.pump();
    expect(find.byIcon(Icons.translate), findsOneWidget);
    await bridge.close();
  });
}

class _TestBridge extends TranslationBridge {
  _TestBridge()
    : super.main(
        channel: BasicMessageChannel<Object?>(
          'test.translation.overlay.${_nextId++}',
          const StandardMessageCodec(),
        ),
      );

  static int _nextId = 0;
  final StreamController<TranslationBridgeMessage> _messages =
      StreamController<TranslationBridgeMessage>.broadcast();
  final List<TranslationBridgeMessage> sent = [];

  @override
  Stream<TranslationBridgeMessage> get messages => _messages.stream;

  @override
  Future<void> send(TranslationBridgeMessage message) async {
    sent.add(message);
  }

  @override
  Future<Size?> displaySize() async => const Size(1080, 1920);

  void emit(TranslationBridgeMessage message) => _messages.add(message);

  Future<void> close() async {
    await _messages.close();
  }
}
