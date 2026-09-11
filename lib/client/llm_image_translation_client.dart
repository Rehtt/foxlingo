import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/image_translation_models.dart';
import '../utils/llm_response_utils.dart';
import '../utils/translation_settings.dart';

/// Translates image text with a vision-capable, OpenAI-compatible LLM.
///
/// The model receives the image and returns translated text blocks together
/// with bounding boxes normalized to a 0-1000 grid, which are converted to
/// the 0-1 normalized rects used by the overlay renderer.
class LlmImageTranslationClient {
  LlmImageTranslationClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static const int maxInputDimension = 2048;

  static const String _systemPromptTemplate =
      'You are an image text translator. Detect every distinct block of '
      'readable text in the image and translate each block into '
      '{targetLanguage}. Respond with a JSON array only. Each element must be '
      'an object of the form '
      '{"bbox":[x1,y1,x2,y2],"source":"<original text>","text":"<translated text>"}. '
      'The bbox values are integers from 0 to 1000 normalized to the image '
      'width and height, where (x1,y1) is the top-left corner and (x2,y2) is '
      'the bottom-right corner of a tight box around the text block '
      '(x1<x2, y1<y2). List the blocks in reading order. If the image '
      'contains no readable text, respond with []. Do not add explanations, '
      'markdown, or code fences.';

  static const String _userInstruction =
      'Extract and translate all text in this image.';

  final http.Client _httpClient;

  Future<ImageTranslationResult> translateImage({
    required Uint8List imageBytes,
    required TranslationSettings settings,
    required Locale? appLocale,
    required Locale deviceLocale,
    Future<void>? abortTrigger,
  }) async {
    if (!settings.isImageLlmConfigured) {
      throw StateError('Image translation LLM API key is not configured.');
    }

    final prepared = await _prepareImage(imageBytes);
    final targetLanguage = settings.resolveTargetLanguageName(
      appLocale: appLocale,
      deviceLocale: deviceLocale,
    );
    final responseText = await _requestCompletion(
      apiBaseUrl: settings.effectiveImageLlmApiBaseUrl,
      apiKey: settings.effectiveImageLlmApiKey,
      model: settings.effectiveImageLlmModel,
      reasoningEffort: settings.reasoningEffort,
      systemMessage: _systemPromptTemplate.replaceAll(
        '{targetLanguage}',
        targetLanguage,
      ),
      imageDataUrl:
          'data:${prepared.mimeType};base64,${base64Encode(prepared.bytes)}',
      abortTrigger: abortTrigger,
    );

    return ImageTranslationResult(
      imageSize: prepared.imageSize,
      regions: _parseRegions(responseText),
    );
  }

  @visibleForTesting
  List<ImageTextRegion> parseRegionsForTest(String responseText) {
    return _parseRegions(responseText);
  }

  static const Duration _testTimeout = Duration(seconds: 20);
  static const String _testSystemMessage =
      'Reply with a JSON array only. If the image contains no readable text, '
      'respond with [].';

  /// 1x1 transparent PNG used only to verify the vision endpoint.
  static final Uint8List _testPngBytes = Uint8List.fromList(const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  Future<void> testConnection({
    required String apiBaseUrl,
    required String apiKey,
    required String model,
    String reasoningEffort = '',
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw StateError('Image translation LLM API key is not configured.');
    }

    await _requestCompletion(
      apiBaseUrl: apiBaseUrl.trim().isEmpty
          ? TranslationSettings.defaultApiBaseUrl
          : apiBaseUrl.trim(),
      apiKey: trimmedKey,
      model: model.trim().isEmpty
          ? TranslationSettings.defaultModel
          : model.trim(),
      reasoningEffort: reasoningEffort.trim(),
      systemMessage: _testSystemMessage,
      imageDataUrl: 'data:image/png;base64,${base64Encode(_testPngBytes)}',
    ).timeout(_testTimeout);
  }

  Future<String> _requestCompletion({
    required String apiBaseUrl,
    required String apiKey,
    required String model,
    required String systemMessage,
    required String imageDataUrl,
    String reasoningEffort = '',
    Future<void>? abortTrigger,
  }) async {
    final baseUrl = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseUrl/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemMessage},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _userInstruction},
            {
              'type': 'image_url',
              'image_url': {'url': imageDataUrl},
            },
          ],
        },
      ],
      if (reasoningEffort.isEmpty)
        'temperature': 0.1
      else
        'reasoning_effort': reasoningEffort,
    });

    final request =
        http.AbortableRequest('POST', uri, abortTrigger: abortTrigger)
          ..headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          })
          ..body = body;
    final response = await http.Response.fromStream(
      await _httpClient.send(request),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Image translation request failed (${response.statusCode}): '
        '${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected image translation response format.');
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw StateError('Image translation response did not include choices.');
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      throw StateError('Unexpected image translation choice format.');
    }

    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      throw StateError('Image translation response did not include a message.');
    }

    final content = message['content'];
    if (content is! String) {
      throw StateError('Image translation response did not include content.');
    }

    final withoutThink = LlmResponseUtils.stripThinkTags(content);
    if (withoutThink.isEmpty) {
      throw StateError('Image translation response did not include content.');
    }

    return LlmResponseUtils.stripCodeFence(withoutThink);
  }

  List<ImageTextRegion> _parseRegions(String responseText) {
    final jsonText = LlmResponseUtils.extractJsonArray(
      LlmResponseUtils.stripCodeFence(responseText),
    );
    final decoded = jsonDecode(jsonText);
    if (decoded is! List) {
      throw StateError('Image translation response was not a JSON array.');
    }

    final regions = <ImageTextRegion>[];
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }

      final text = entry['text'];
      if (text is! String || text.trim().isEmpty) {
        continue;
      }

      final rect = _normalizeBbox(entry['bbox']);
      if (rect == null) {
        continue;
      }

      final source = entry['source'];
      regions.add(
        ImageTextRegion(
          normalizedRect: rect,
          sourceText: source is String ? source.trim() : '',
          translatedText: text.trim(),
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

  Rect? _normalizeBbox(Object? value) {
    if (value is! List || value.length != 4) {
      return null;
    }

    final coordinates = <double>[];
    for (final element in value) {
      if (element is! num || !element.isFinite) {
        return null;
      }
      coordinates.add(element.toDouble());
    }

    // The prompt requests a 0-1000 grid, but tolerate models that respond
    // with 0-1 normalized floats instead.
    final scale = coordinates.every((coordinate) => coordinate <= 1.0)
        ? 1.0
        : 1000.0;
    final left = (coordinates[0] / scale).clamp(0.0, 1.0);
    final top = (coordinates[1] / scale).clamp(0.0, 1.0);
    final right = (coordinates[2] / scale).clamp(0.0, 1.0);
    final bottom = (coordinates[3] / scale).clamp(0.0, 1.0);
    if (right <= left || bottom <= top) {
      return null;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Prepares the payload image: JPEG/PNG within [maxInputDimension] are sent
  /// as-is; anything else (WebP, GIF, oversized images) is re-encoded as a
  /// PNG of the first frame so the API always receives a supported format.
  Future<_PreparedImage> _prepareImage(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      throw StateError('Image data is empty.');
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(imageBytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final sourceWidth = descriptor.width;
      final sourceHeight = descriptor.height;
      if (sourceWidth <= 0 || sourceHeight <= 0) {
        throw StateError('Image dimensions are invalid.');
      }

      final imageSize = Size(
        sourceWidth.toDouble(),
        sourceHeight.toDouble(),
      );
      final longestSide = sourceWidth > sourceHeight
          ? sourceWidth
          : sourceHeight;
      final mimeType = _detectMimeType(imageBytes);
      if (mimeType != null && longestSide <= maxInputDimension) {
        return _PreparedImage(
          bytes: imageBytes,
          mimeType: mimeType,
          imageSize: imageSize,
        );
      }

      final scale = longestSide > maxInputDimension
          ? maxInputDimension / longestSide
          : 1.0;
      final codec = await descriptor.instantiateCodec(
        targetWidth: (sourceWidth * scale).round().clamp(1, sourceWidth),
        targetHeight: (sourceHeight * scale).round().clamp(1, sourceHeight),
      );
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        try {
          final pngData = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (pngData == null) {
            throw StateError('Unable to encode image for upload.');
          }
          return _PreparedImage(
            bytes: pngData.buffer.asUint8List(
              pngData.offsetInBytes,
              pngData.lengthInBytes,
            ),
            mimeType: 'image/png',
            imageSize: imageSize,
          );
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  String? _detectMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    return null;
  }
}

class _PreparedImage {
  const _PreparedImage({
    required this.bytes,
    required this.mimeType,
    required this.imageSize,
  });

  final Uint8List bytes;
  final String mimeType;
  final Size imageSize;
}
