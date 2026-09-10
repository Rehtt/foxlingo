import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxlingo/models/image_translation_models.dart';
import 'package:foxlingo/widgets/image_translation_overlay.dart';

void main() {
  test('maps landscape and portrait images into a contained viewport', () {
    expect(
      containedImageRect(viewport: const Size(300, 300), imageAspectRatio: 2),
      const Rect.fromLTRB(0, 75, 300, 225),
    );
    expect(
      containedImageRect(viewport: const Size(300, 300), imageAspectRatio: 0.5),
      const Rect.fromLTRB(75, 0, 225, 300),
    );
    expect(
      containedImageRect(viewport: Size.zero, imageAspectRatio: 1),
      Rect.zero,
    );
  });

  test('source font estimate grows with the image-space box', () {
    final roomy = estimateSourceFontSize(
      sourceText: 'translated text',
      boxSize: const Size(240, 100),
    );
    final constrained = estimateSourceFontSize(
      sourceText: 'translated text',
      boxSize: const Size(70, 20),
    );

    expect(constrained, lessThan(roomy));
    expect(constrained, greaterThan(0));
  });

  testWidgets('positions translated text in the normalized image region', (
    tester,
  ) async {
    const result = ImageTranslationResult(
      imageSize: Size(400, 200),
      regions: [
        ImageTextRegion(
          normalizedRect: Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
          sourceText: 'source',
          translatedText: 'translated',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: ImageTranslationOverlay(result: result),
          ),
        ),
      ),
    );

    final textRect = tester.getRect(find.text('translated'));
    expect(textRect.center.dx, closeTo(400, 1));
    expect(textRect.center.dy, closeTo(300, 1));
  });

  testWidgets('tiny screen boxes still render readable text', (tester) async {
    const normalized = Rect.fromLTRB(0.1, 0.49, 0.9, 0.51);
    const result = ImageTranslationResult(
      imageSize: Size(1000, 1000),
      regions: [
        ImageTextRegion(
          normalizedRect: normalized,
          sourceText: 'source',
          translatedText: 'tiny-box',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: ImageTranslationOverlay(result: result),
          ),
        ),
      ),
    );

    final textRect = tester.getRect(find.text('tiny-box'));
    expect(textRect.width, greaterThan(0));
    expect(textRect.height, greaterThan(0));
  });

  testWidgets('translated text stays inside the mapped detection box', (
    tester,
  ) async {
    const normalized = Rect.fromLTRB(0.2, 0.2, 0.8, 0.4);
    const result = ImageTranslationResult(
      imageSize: Size(1000, 1000),
      regions: [
        ImageTextRegion(
          normalizedRect: normalized,
          sourceText: 'source',
          translatedText: 'bounded',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: ImageTranslationOverlay(result: result),
          ),
        ),
      ),
    );

    final overlayOrigin = tester.getTopLeft(find.byType(ImageTranslationOverlay));
    final imageRect = containedImageRect(
      viewport: const Size(300, 300),
      imageAspectRatio: 1,
    );
    final screenRect = screenSpaceRect(
      imageRect: imageRect,
      normalizedRect: normalized,
    ).shift(overlayOrigin);
    final textRect = tester.getRect(find.text('bounded'));

    expect(textRect.left, greaterThanOrEqualTo(screenRect.left - 0.5));
    expect(textRect.top, greaterThanOrEqualTo(screenRect.top - 0.5));
    expect(textRect.right, lessThanOrEqualTo(screenRect.right + 0.5));
    expect(textRect.bottom, lessThanOrEqualTo(screenRect.bottom + 0.5));
  });
}
