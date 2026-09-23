import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/translation_models.dart';
import '../utils/translation_settings.dart';

class TraditionalTranslationClient {
  TraditionalTranslationClient({http.Client? httpClient})
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

    return switch (settings.provider) {
      TranslationProvider.google => _translateWithGoogle(
        apiKey: settings.googleApiKey,
        target: settings.resolveGoogleTargetLanguageCode(
          appLocale: appLocale,
          deviceLocale: deviceLocale,
        ),
        texts: texts,
        abortTrigger: abortTrigger,
      ),
      TranslationProvider.microsoft => _translateWithMicrosoft(
        apiKey: settings.microsoftApiKey,
        region: settings.microsoftRegion,
        target: settings.resolveMicrosoftTargetLanguageCode(
          appLocale: appLocale,
          deviceLocale: deviceLocale,
        ),
        texts: texts,
        abortTrigger: abortTrigger,
      ),
      TranslationProvider.llm => throw StateError(
        'Traditional translation client does not support LLM provider.',
      ),
    };
  }

  static const Duration _testTimeout = Duration(seconds: 20);
  static const String _testPhrase = 'Hello';

  Future<String> testConnection({
    required TranslationProvider provider,
    required String googleApiKey,
    required String microsoftApiKey,
    required String microsoftRegion,
    required String targetLanguageCode,
  }) async {
    final translations = await switch (provider) {
      TranslationProvider.google => _translateWithGoogle(
        apiKey: googleApiKey.trim(),
        target: targetLanguageCode,
        texts: const [_testPhrase],
      ),
      TranslationProvider.microsoft => _translateWithMicrosoft(
        apiKey: microsoftApiKey.trim(),
        region: microsoftRegion.trim(),
        target: targetLanguageCode,
        texts: const [_testPhrase],
      ),
      TranslationProvider.llm => throw StateError(
        'Traditional translation client does not support LLM provider.',
      ),
    }.timeout(_testTimeout);

    if (translations.isEmpty) {
      throw StateError('Translation response did not include translations.');
    }
    return translations.first;
  }

  Future<List<String>> _translateWithGoogle({
    required String apiKey,
    required String target,
    required List<String> texts,
    Future<void>? abortTrigger,
  }) async {
    if (apiKey.isEmpty) {
      throw StateError('Translation API key is not configured.');
    }

    final uri = Uri.parse(
      'https://translation.googleapis.com/language/translate/v2'
      '?key=${Uri.encodeQueryComponent(apiKey)}',
    );
    final response = await _post(
      uri: uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'q': texts, 'target': target, 'format': 'text'}),
      abortTrigger: abortTrigger,
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

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Translation response did not include data.');
    }

    final translations = data['translations'];
    if (translations is! List) {
      throw StateError('Translation response did not include translations.');
    }

    return translations.map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw StateError('Unexpected translation entry format.');
      }
      final translatedText = entry['translatedText'];
      if (translatedText is! String) {
        throw StateError('Translation entry did not include translatedText.');
      }
      return translatedText;
    }).toList();
  }

  Future<List<String>> _translateWithMicrosoft({
    required String apiKey,
    required String region,
    required String target,
    required List<String> texts,
    Future<void>? abortTrigger,
  }) async {
    if (apiKey.isEmpty || region.isEmpty) {
      throw StateError('Translation API key is not configured.');
    }

    final uri = Uri.parse(
      'https://api.cognitive.microsofttranslator.com/translate'
      '?api-version=3.0&to=${Uri.encodeQueryComponent(target)}',
    );
    final response = await _post(
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Ocp-Apim-Subscription-Key': apiKey,
        'Ocp-Apim-Subscription-Region': region,
      },
      body: jsonEncode(texts.map((text) => {'Text': text}).toList()),
      abortTrigger: abortTrigger,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Translation request failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw StateError('Unexpected translation response format.');
    }

    if (decoded.length != texts.length) {
      throw StateError(
        'Translation count mismatch: expected ${texts.length}, got ${decoded.length}.',
      );
    }

    return decoded.map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw StateError('Unexpected translation entry format.');
      }
      final translations = entry['translations'];
      if (translations is! List || translations.isEmpty) {
        throw StateError('Translation entry did not include translations.');
      }
      final translation = translations.first;
      if (translation is! Map<String, dynamic>) {
        throw StateError('Unexpected translation format.');
      }
      final text = translation['text'];
      if (text is! String) {
        throw StateError('Translation did not include text.');
      }
      return text;
    }).toList();
  }

  Future<http.Response> _post({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final request =
        http.AbortableRequest('POST', uri, abortTrigger: abortTrigger)
          ..headers.addAll(headers)
          ..body = body;
    return http.Response.fromStream(await _httpClient.send(request));
  }
}
