import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxlingo/models/image_translation_models.dart';

void main() {
  test('round-trips image translation JSON', () {
    const original = ImageTranslationResult(
      imageSize: Size(1920, 1080),
      regions: [
        ImageTextRegion(
          normalizedRect: Rect.fromLTRB(0.1, 0.2, 0.4, 0.3),
          sourceText: 'Hello',
          translatedText: '你好',
        ),
        ImageTextRegion(
          normalizedRect: Rect.fromLTRB(0.5, 0.6, 0.9, 0.8),
          sourceText: 'World',
          translatedText: '世界',
        ),
      ],
    );

    final restored = ImageTranslationResult.fromJson(original.toJson());

    expect(restored.imageSize, original.imageSize);
    expect(restored.regions, hasLength(2));
    expect(restored.regions[0].sourceText, 'Hello');
    expect(restored.regions[0].translatedText, '你好');
    expect(
      restored.regions[0].normalizedRect,
      const Rect.fromLTRB(0.1, 0.2, 0.4, 0.3),
    );
    expect(restored.regions[1].sourceText, 'World');
    expect(restored.imageAspectRatio, closeTo(1920 / 1080, 0.0001));
  });

  test('rejects malformed image size', () {
    expect(
      () => ImageTranslationResult.fromJson({
        'imageSize': [100],
        'regions': <Object>[],
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
