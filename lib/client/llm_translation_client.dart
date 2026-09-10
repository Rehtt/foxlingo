import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../utils/llm_response_utils.dart';
import '../utils/translation_settings.dart';

class LlmTranslationClient {
  LlmTranslationClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<List<String>> translateTexts({
    required TranslationSettings settings,
    required Locale? appLocale,
    required Locale deviceLocale,
    required List<String> texts,
    Future<void>? abortTrigger,
  }) async {
    if (texts.isEmpty) {
      return const [];
    }
    if (!settings.isConfigured) {
      throw StateError('Translation API key is not configured.');
    }

    final responseText = await _requestCompletion(
      apiBaseUrl: settings.apiBaseUrl,
      apiKey: settings.apiKey,
      model: settings.model,
      systemMessage: settings.buildSystemMessage(
        appLocale: appLocale,
        deviceLocale: deviceLocale,
      ),
      userMessage:
          'Translate each text on its own line. '
          'Return exactly ${texts.length} lines, one translated text per line:\n'
          '${texts.join('\n')}',
      abortTrigger: abortTrigger,
    );

    return _parseLineResponse(responseText, texts.length);
  }

  @visibleForTesting
  List<String> parseTextsForTest(String responseText, int expectedCount) {
    return _parseLineResponse(responseText, expectedCount);
  }

  static const Duration _testTimeout = Duration(seconds: 20);
  static const String _testUserMessage = 'Reply with the single word OK.';

  Future<String> testConnection({
    required String apiBaseUrl,
    required String apiKey,
    required String model,
    required String systemMessage,
  }) {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw StateError('Translation API key is not configured.');
    }

    return _requestCompletion(
      apiBaseUrl: apiBaseUrl.trim().isEmpty
          ? TranslationSettings.defaultApiBaseUrl
          : apiBaseUrl.trim(),
      apiKey: trimmedKey,
      model: model.trim().isEmpty
          ? TranslationSettings.defaultModel
          : model.trim(),
      systemMessage: systemMessage,
      userMessage: _testUserMessage,
    ).timeout(_testTimeout);
  }

  Future<String> _requestCompletion({
    required String apiBaseUrl,
    required String apiKey,
    required String model,
    required String systemMessage,
    required String userMessage,
    Future<void>? abortTrigger,
  }) async {
    final baseUrl = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseUrl/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemMessage},
        {'role': 'user', 'content': userMessage},
      ],
      'temperature': 0.2,
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
        'Translation request failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected translation response format.');
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw StateError('Translation response did not include choices.');
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      throw StateError('Unexpected translation choice format.');
    }

    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      throw StateError('Translation response did not include a message.');
    }

    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw StateError('Translation response did not include content.');
    }

    return LlmResponseUtils.stripCodeFence(content.trim());
  }

  List<String> _parseLineResponse(String responseText, int expectedCount) {
    final lines = responseText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length != expectedCount) {
      throw StateError(
        'Translation count mismatch: expected $expectedCount, got ${lines.length}.',
      );
    }
    return lines;
  }
}
