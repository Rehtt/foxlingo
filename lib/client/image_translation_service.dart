import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/image_translation_models.dart';
import '../models/ocr_script.dart';
import '../models/translation_models.dart';
import '../utils/translation_settings.dart';
import 'llm_image_translation_client.dart';
import 'translation_client.dart';

abstract interface class ImageTextRecognizer {
  Future<RecognizedImageText> recognize(
    Uint8List imageBytes, {
    Future<void>? abortTrigger,
  });

  Future<void> close();
}

class RecognizedImageTextRegion {
  const RecognizedImageTextRegion({
    required this.normalizedRect,
    required this.text,
  });

  final Rect normalizedRect;
  final String text;
}

class RecognizedImageText {
  const RecognizedImageText({
    required this.imageSize,
    required this.regions,
  });

  final Size imageSize;
  final List<RecognizedImageTextRegion> regions;

  double get imageAspectRatio => imageSize.width / imageSize.height;
}

class MlKitImageTextRecognizer implements ImageTextRecognizer {
  MlKitImageTextRecognizer({
    required TextRecognitionScript script,
    TextRecognizer? recognizer,
  }) : _recognizer = recognizer ?? TextRecognizer(script: script);

  static const int maxInputDimension = 2048;

  final TextRecognizer _recognizer;

  @override
  Future<RecognizedImageText> recognize(
    Uint8List imageBytes, {
    Future<void>? abortTrigger,
  }) async {
    var aborted = false;
    var completed = false;

    void onAbort() {
      if (completed || aborted) {
        return;
      }
      aborted = true;
      unawaited(
        _recognizer.close().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    }

    void throwIfAborted() {
      if (aborted) {
        throw const _ImageTranslationCancelled();
      }
    }

    if (abortTrigger != null) {
      unawaited(abortTrigger.then((_) => onAbort()));
    }

    throwIfAborted();
    final bitmap = await _decodeBitmap(
      imageBytes,
      isAborted: () => aborted,
    );
    try {
      throwIfAborted();
      final inputImage = InputImage.fromBitmap(
        bitmap: bitmap.bytes,
        width: bitmap.width,
        height: bitmap.height,
      );
      final RecognizedText recognized;
      try {
        recognized = await _recognizer.processImage(inputImage);
      } on Object {
        throwIfAborted();
        rethrow;
      }
      throwIfAborted();
      final imageSize = Size(
        bitmap.width.toDouble(),
        bitmap.height.toDouble(),
      );
      return RecognizedImageText(
        imageSize: imageSize,
        regions: normalizeRecognizedTextBlocks(
          blocks: recognized.blocks.map(
            (block) => RecognizedTextBlock(
              text: block.text,
              boundingBox: block.boundingBox,
            ),
          ),
          imageSize: imageSize,
        ),
      );
    } finally {
      completed = true;
      bitmap.dispose();
    }
  }

  @override
  Future<void> close() => _recognizer.close();

  Future<_DecodedBitmap> _decodeBitmap(
    Uint8List imageBytes, {
    required bool Function() isAborted,
  }) async {
    if (imageBytes.isEmpty) {
      throw StateError('Image data is empty.');
    }

    void throwIfAborted() {
      if (isAborted()) {
        throw const _ImageTranslationCancelled();
      }
    }

    throwIfAborted();
    final buffer = await ui.ImmutableBuffer.fromUint8List(imageBytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      throwIfAborted();
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final sourceWidth = descriptor.width;
      final sourceHeight = descriptor.height;
      if (sourceWidth <= 0 || sourceHeight <= 0) {
        throw StateError('Image dimensions are invalid.');
      }

      final longestSide = sourceWidth > sourceHeight
          ? sourceWidth
          : sourceHeight;
      final scale = longestSide > maxInputDimension
          ? maxInputDimension / longestSide
          : 1.0;
      final targetWidth = (sourceWidth * scale).round().clamp(1, sourceWidth);
      final targetHeight = (sourceHeight * scale).round().clamp(
        1,
        sourceHeight,
      );

      throwIfAborted();
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      throwIfAborted();
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        throw StateError('Unable to decode image pixels.');
      }

      throwIfAborted();
      return _DecodedBitmap(
        bytes: byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        width: image.width,
        height: image.height,
        image: image,
        codec: codec,
        descriptor: descriptor,
        buffer: buffer,
      );
    } catch (_) {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
      rethrow;
    }
  }
}

class RecognizedTextBlock {
  const RecognizedTextBlock({required this.text, required this.boundingBox});

  final String text;
  final Rect boundingBox;
}

@visibleForTesting
List<RecognizedImageTextRegion> normalizeRecognizedTextBlocks({
  required Iterable<RecognizedTextBlock> blocks,
  required Size imageSize,
}) {
  if (imageSize.width <= 0 || imageSize.height <= 0) {
    throw ArgumentError.value(imageSize, 'imageSize', 'must be positive');
  }

  final regions = <RecognizedImageTextRegion>[];
  for (final block in blocks) {
    final text = block.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) {
      continue;
    }

    final left = (block.boundingBox.left / imageSize.width).clamp(0.0, 1.0);
    final top = (block.boundingBox.top / imageSize.height).clamp(0.0, 1.0);
    final right = (block.boundingBox.right / imageSize.width).clamp(0.0, 1.0);
    final bottom = (block.boundingBox.bottom / imageSize.height).clamp(
      0.0,
      1.0,
    );
    if (right <= left || bottom <= top) {
      continue;
    }

    regions.add(
      RecognizedImageTextRegion(
        normalizedRect: Rect.fromLTRB(left, top, right, bottom),
        text: text,
      ),
    );
  }

  regions.sort((first, second) {
    final vertical = first.normalizedRect.top.compareTo(
      second.normalizedRect.top,
    );
    if (vertical != 0) {
      return vertical;
    }
    return first.normalizedRect.left.compareTo(second.normalizedRect.left);
  });
  return regions;
}

enum ImageTranslationStage { recognizing, translating, llmTranslating }

class ImageTranslationProgress {
  const ImageTranslationProgress({required this.stage, this.regionCount = 0});

  final ImageTranslationStage stage;
  final int regionCount;
}

class ImageTranslationService {
  ImageTranslationService({
    ImageTextRecognizer? recognizer,
    TranslationClient? translationClient,
    LlmImageTranslationClient? llmImageClient,
  }) : _injectedRecognizer = recognizer,
       _translationClient = translationClient ?? TranslationClient(),
       _llmImageClient = llmImageClient ?? LlmImageTranslationClient();

  final ImageTextRecognizer? _injectedRecognizer;
  final TranslationClient _translationClient;
  final LlmImageTranslationClient _llmImageClient;
  ImageTextRecognizer? _ownedRecognizer;
  TextRecognitionScript? _ownedScript;

  Future<ImageTranslationResult> translate({
    required Uint8List imageBytes,
    required TranslationSettings settings,
    required Locale? appLocale,
    required Locale deviceLocale,
    Future<void>? abortTrigger,
    void Function(ImageTranslationProgress progress)? onProgress,
  }) async {
    if (settings.imageMethod == ImageTranslationMethod.llm) {
      onProgress?.call(
        const ImageTranslationProgress(
          stage: ImageTranslationStage.llmTranslating,
        ),
      );
      return _completeUnlessAborted(
        _llmImageClient.translateImage(
          imageBytes: imageBytes,
          settings: settings,
          appLocale: appLocale,
          deviceLocale: deviceLocale,
          abortTrigger: abortTrigger,
        ),
        abortTrigger,
      );
    }

    onProgress?.call(
      const ImageTranslationProgress(stage: ImageTranslationStage.recognizing),
    );
    final recognizer = await _recognizerFor(settings.ocrScript);
    final recognized = await _completeUnlessAborted(
      recognizer.recognize(imageBytes, abortTrigger: abortTrigger),
      abortTrigger,
    );
    if (recognized.regions.isEmpty) {
      return ImageTranslationResult(
        imageSize: recognized.imageSize,
        regions: const [],
      );
    }

    onProgress?.call(
      ImageTranslationProgress(
        stage: ImageTranslationStage.translating,
        regionCount: recognized.regions.length,
      ),
    );
    final translated = await _translationClient.translateTexts(
      settings: settings,
      appLocale: appLocale,
      deviceLocale: deviceLocale,
      texts: recognized.regions.map((region) => region.text).toList(),
      abortTrigger: abortTrigger,
    );
    if (translated.length != recognized.regions.length) {
      throw StateError(
        'Image translation count mismatch: expected '
        '${recognized.regions.length}, got ${translated.length}.',
      );
    }

    return ImageTranslationResult(
      imageSize: recognized.imageSize,
      regions: [
        for (var index = 0; index < recognized.regions.length; index++)
          ImageTextRegion(
            normalizedRect: recognized.regions[index].normalizedRect,
            sourceText: recognized.regions[index].text,
            translatedText: translated[index],
          ),
      ],
    );
  }

  Future<ImageTextRecognizer> _recognizerFor(OcrScript script) async {
    if (_injectedRecognizer != null) {
      return _injectedRecognizer;
    }

    final mlKitScript = script.mlKitScript;
    if (_ownedRecognizer != null && _ownedScript == mlKitScript) {
      return _ownedRecognizer!;
    }

    await _ownedRecognizer?.close();
    _ownedRecognizer = MlKitImageTextRecognizer(script: mlKitScript);
    _ownedScript = mlKitScript;
    return _ownedRecognizer!;
  }

  Future<void> close() async {
    await _ownedRecognizer?.close();
    _ownedRecognizer = null;
    _ownedScript = null;
    await _injectedRecognizer?.close();
  }
}

Future<T> _completeUnlessAborted<T>(
  Future<T> operation,
  Future<void>? abortTrigger,
) {
  if (abortTrigger == null) {
    return operation;
  }
  final completer = Completer<T>();
  operation.then(
    (value) {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
  );
  abortTrigger.then(
    (_) {
      if (!completer.isCompleted) {
        completer.completeError(
          const _ImageTranslationCancelled(),
          StackTrace.current,
        );
      }
    },
    onError: (Object _, StackTrace _) {},
  );
  return completer.future;
}

class _ImageTranslationCancelled implements Exception {
  const _ImageTranslationCancelled();
}

class _DecodedBitmap {
  const _DecodedBitmap({
    required this.bytes,
    required this.width,
    required this.height,
    required this.image,
    required this.codec,
    required this.descriptor,
    required this.buffer,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final ui.Image image;
  final ui.Codec codec;
  final ui.ImageDescriptor descriptor;
  final ui.ImmutableBuffer buffer;

  void dispose() {
    image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}
