import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxlingo/client/image_translation_service.dart';
import 'package:foxlingo/client/translation_client.dart';
import 'package:foxlingo/utils/translation_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('normalizes text, clamps bounds, drops invalid blocks, and sorts', () {
    final regions = normalizeRecognizedTextBlocks(
      imageSize: const Size(200, 100),
      blocks: const [
        RecognizedTextBlock(
          text: ' Second\n block ',
          boundingBox: Rect.fromLTRB(80, 50, 220, 110),
        ),
        RecognizedTextBlock(
          text: ' First   block ',
          boundingBox: Rect.fromLTRB(-10, 10, 90, 40),
        ),
        RecognizedTextBlock(
          text: ' ',
          boundingBox: Rect.fromLTRB(0, 0, 10, 10),
        ),
        RecognizedTextBlock(
          text: 'outside',
          boundingBox: Rect.fromLTRB(250, 0, 300, 20),
        ),
      ],
    );

    expect(regions, hasLength(2));
    expect(regions[0].text, 'First block');
    expect(regions[0].normalizedRect, const Rect.fromLTRB(0, 0.1, 0.45, 0.4));
    expect(regions[1].text, 'Second block');
    expect(regions[1].normalizedRect, const Rect.fromLTRB(0.4, 0.5, 1, 1));
  });

  test(
    'translates recognized blocks and preserves normalized regions',
    () async {
      final translator = _FakeTranslationClient(response: const ['第一', '第二']);
      final service = ImageTranslationService(
        recognizer: _ImmediateRecognizer(
          const RecognizedImageText(
            imageSize: Size(200, 100),
            regions: [
              RecognizedImageTextRegion(
                normalizedRect: Rect.fromLTRB(0, 0, 0.5, 0.2),
                text: 'first',
              ),
              RecognizedImageTextRegion(
                normalizedRect: Rect.fromLTRB(0.5, 0.2, 1, 0.4),
                text: 'second',
              ),
            ],
          ),
        ),
        translationClient: translator,
      );

      final result = await service.translate(
        imageBytes: Uint8List.fromList([1]),
        settings: TranslationSettings(),
        appLocale: const Locale('zh'),
        deviceLocale: const Locale('en'),
      );

      expect(translator.receivedTexts, ['first', 'second']);
      expect(result.imageAspectRatio, 2);
      expect(result.regions, hasLength(2));
      expect(result.regions[0].sourceText, 'first');
      expect(result.regions[0].translatedText, '第一');
      expect(
        result.regions[1].normalizedRect,
        const Rect.fromLTRB(0.5, 0.2, 1, 0.4),
      );
    },
  );

  test('empty OCR result skips translation', () async {
    final translator = _FakeTranslationClient(response: const []);
    final service = ImageTranslationService(
      recognizer: _ImmediateRecognizer(
        const RecognizedImageText(imageSize: Size(100, 100), regions: []),
      ),
      translationClient: translator,
    );

    final result = await service.translate(
      imageBytes: Uint8List.fromList([1]),
      settings: TranslationSettings(),
      appLocale: null,
      deviceLocale: const Locale('en'),
    );

    expect(result.regions, isEmpty);
    expect(translator.callCount, 0);
  });

  test('translation count mismatch is rejected', () async {
    final service = ImageTranslationService(
      recognizer: _ImmediateRecognizer(
        const RecognizedImageText(
          imageSize: Size(100, 100),
          regions: [
            RecognizedImageTextRegion(
              normalizedRect: Rect.fromLTRB(0, 0, 1, 1),
              text: 'one',
            ),
          ],
        ),
      ),
      translationClient: _FakeTranslationClient(response: const []),
    );

    expect(
      () => service.translate(
        imageBytes: Uint8List.fromList([1]),
        settings: TranslationSettings(),
        appLocale: null,
        deviceLocale: const Locale('en'),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('cancel during OCR prevents a translation request', () async {
    final recognizer = _PendingRecognizer();
    final translator = _FakeTranslationClient(response: const ['translated']);
    final service = ImageTranslationService(
      recognizer: recognizer,
      translationClient: translator,
    );
    final abort = Completer<void>();

    final operation = service.translate(
      imageBytes: Uint8List.fromList([1]),
      settings: TranslationSettings(),
      appLocale: null,
      deviceLocale: const Locale('en'),
      abortTrigger: abort.future,
    );
    abort.complete();

    await expectLater(operation, throwsA(anything));
    expect(translator.callCount, 0);
    recognizer.complete();
  });

  test('passes abort trigger through to cloud translation', () async {
    final abort = Completer<void>();
    final translator = _FakeTranslationClient(response: const ['translated']);
    final service = ImageTranslationService(
      recognizer: _ImmediateRecognizer(
        const RecognizedImageText(
          imageSize: Size(100, 100),
          regions: [
            RecognizedImageTextRegion(
              normalizedRect: Rect.fromLTRB(0, 0, 1, 1),
              text: 'source',
            ),
          ],
        ),
      ),
      translationClient: translator,
    );

    await service.translate(
      imageBytes: Uint8List.fromList([1]),
      settings: TranslationSettings(),
      appLocale: null,
      deviceLocale: const Locale('en'),
      abortTrigger: abort.future,
    );

    expect(translator.receivedAbortTrigger, same(abort.future));
  });
}

class _ImmediateRecognizer implements ImageTextRecognizer {
  const _ImmediateRecognizer(this.result);

  final RecognizedImageText result;

  @override
  Future<void> close() async {}

  @override
  Future<RecognizedImageText> recognize(
    Uint8List imageBytes, {
    Future<void>? abortTrigger,
  }) async => result;
}

class _PendingRecognizer implements ImageTextRecognizer {
  final Completer<RecognizedImageText> _completer =
      Completer<RecognizedImageText>();

  void complete() {
    _completer.complete(
      const RecognizedImageText(
        imageSize: Size(100, 100),
        regions: [
          RecognizedImageTextRegion(
            normalizedRect: Rect.fromLTRB(0, 0, 1, 1),
            text: 'source',
          ),
        ],
      ),
    );
  }

  @override
  Future<void> close() async {}

  @override
  Future<RecognizedImageText> recognize(
    Uint8List imageBytes, {
    Future<void>? abortTrigger,
  }) => _completer.future;
}

class _FakeTranslationClient extends TranslationClient {
  _FakeTranslationClient({required this.response});

  final List<String> response;
  int callCount = 0;
  List<String>? receivedTexts;
  Future<void>? receivedAbortTrigger;

  @override
  Future<List<String>> translateTexts({
    required TranslationSettings settings,
    required Locale? appLocale,
    required Locale deviceLocale,
    required List<String> texts,
    Future<void>? abortTrigger,
  }) async {
    callCount++;
    receivedTexts = texts;
    receivedAbortTrigger = abortTrigger;
    return response;
  }
}
