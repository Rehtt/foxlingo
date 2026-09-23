import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxlingo/models/image_translation_models.dart';
import 'package:foxlingo/utils/image_region_crop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'crops the selected pixels and reports their snapped image bounds',
    () async {
      final bytes = await _makePng(100, 50);
      final crop = await cropImageToRegion(
        bytes,
        const Rect.fromLTRB(0.25, 0.2, 0.75, 0.8),
      );
      final codec = await ui.instantiateImageCodec(crop.bytes);
      final image = (await codec.getNextFrame()).image;
      expect(
        Size(image.width.toDouble(), image.height.toDouble()),
        const Size(50, 30),
      );
      expect(crop.normalizedRect, const Rect.fromLTRB(0.25, 0.2, 0.75, 0.8));
      image.dispose();
      codec.dispose();
    },
  );

  test('maps crop-relative text boxes into the complete screenshot', () {
    final result = mapImageTranslationResultToRegion(
      result: const ImageTranslationResult(
        imageSize: Size(50, 30),
        regions: [
          ImageTextRegion(
            normalizedRect: Rect.fromLTRB(0.2, 0.1, 0.6, 0.5),
            sourceText: 'Hello',
            translatedText: '你好',
          ),
          ImageTextRegion(
            normalizedRect: Rect.fromLTRB(-0.2, 0.2, 0.3, 0.5),
            sourceText: 'Edge',
            translatedText: '边缘',
          ),
        ],
      ),
      normalizedRegion: const Rect.fromLTRB(0.25, 0.2, 0.75, 0.8),
      fullImageSize: const Size(100, 50),
    );

    expect(result.imageSize, const Size(100, 50));
    expect(result.regions, hasLength(2));
    expect(
      result.regions.first.normalizedRect,
      const Rect.fromLTRB(0.35, 0.26, 0.55, 0.5),
    );
    expect(result.regions.last.normalizedRect.left, 0.25);
    expect(result.regions.last.normalizedRect.right, 0.4);
  });
}

Future<Uint8List> _makePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.white,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
