import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foxlingo/client/llm_translation_client.dart';
import 'package:foxlingo/models/translation_models.dart';
import 'package:foxlingo/utils/translation_settings.dart';

String _completionBody(String content) {
  return jsonEncode({
    'choices': [
      {
        'message': {'content': content},
      },
    ],
  });
}

Future<TranslationSettings> _llmSettings({String reasoningEffort = ''}) async {
  final settings = TranslationSettings();
  await settings.save(
    provider: TranslationProvider.llm,
    apiBaseUrl: TranslationSettings.defaultApiBaseUrl,
    apiKey: 'llm-test-key',
    model: TranslationSettings.defaultModel,
    systemPrompt: TranslationSettings.defaultSystemPrompt,
    targetLanguage: 'zh',
    googleApiKey: '',
    microsoftApiKey: '',
    microsoftRegion: '',
    reasoningEffort: reasoningEffort,
  );
  return settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('parses one translated line per source text', () {
    final client = LlmTranslationClient();
    final result = client.parseTextsForTest(
      'wolf\nfantasy\ndigital art',
      3,
    );

    expect(result, ['wolf', 'fantasy', 'digital art']);
  });

  test('rejects a line count mismatch', () {
    final client = LlmTranslationClient();
    expect(
      () => client.parseTextsForTest('only one', 2),
      throwsA(isA<StateError>()),
    );
  });

  test('sends temperature when reasoning effort is empty', () async {
    Map<String, dynamic>? body;
    final client = LlmTranslationClient(
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(_completionBody('Title\nBody'), 200);
      }),
    );

    await client.translateTexts(
      settings: await _llmSettings(),
      appLocale: const Locale('zh'),
      deviceLocale: const Locale('en'),
      texts: const ['Title', 'Body'],
    );

    expect(body?['temperature'], 0.2);
    expect(body?.containsKey('reasoning_effort'), isFalse);
  });

  test('sends reasoning_effort and omits temperature when set', () async {
    Map<String, dynamic>? body;
    final client = LlmTranslationClient(
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(_completionBody('Title\nBody'), 200);
      }),
    );

    await client.translateTexts(
      settings: await _llmSettings(reasoningEffort: 'high'),
      appLocale: const Locale('zh'),
      deviceLocale: const Locale('en'),
      texts: const ['Title', 'Body'],
    );

    expect(body?['reasoning_effort'], 'high');
    expect(body?.containsKey('temperature'), isFalse);
  });

  test('passes a custom reasoning effort value through', () async {
    Map<String, dynamic>? body;
    final client = LlmTranslationClient(
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(_completionBody('Title\nBody'), 200);
      }),
    );

    await client.translateTexts(
      settings: await _llmSettings(reasoningEffort: 'xhigh'),
      appLocale: const Locale('zh'),
      deviceLocale: const Locale('en'),
      texts: const ['Title', 'Body'],
    );

    expect(body?['reasoning_effort'], 'xhigh');
    expect(body?.containsKey('temperature'), isFalse);
  });

  test('strips think tags before parsing translated lines', () async {
    final client = LlmTranslationClient(
      httpClient: MockClient((request) async {
        return http.Response(
          _completionBody('<think>plan the lines</think>Title\nBody'),
          200,
        );
      }),
    );

    final result = await client.translateTexts(
      settings: await _llmSettings(reasoningEffort: 'low'),
      appLocale: const Locale('zh'),
      deviceLocale: const Locale('en'),
      texts: const ['Title', 'Body'],
    );

    expect(result, ['Title', 'Body']);
  });

  test('rejects a response that is only think content', () async {
    final settings = await _llmSettings();
    final client = LlmTranslationClient(
      httpClient: MockClient((request) async {
        return http.Response(
          _completionBody('<think>still thinking</think>'),
          200,
        );
      }),
    );

    expect(
      () => client.translateTexts(
        settings: settings,
        appLocale: const Locale('zh'),
        deviceLocale: const Locale('en'),
        texts: const ['Title'],
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('aborts an in-flight LLM request', () async {
    final settings = await _llmSettings();
    final abortCompleter = Completer<void>();
    final client = LlmTranslationClient(
      httpClient: MockClient.streaming((request, _) async {
        expect(request, isA<http.AbortableRequest>());
        final abortTrigger = (request as http.AbortableRequest).abortTrigger;
        expect(abortTrigger, same(abortCompleter.future));
        await abortTrigger;
        throw http.RequestAbortedException(request.url);
      }),
    );

    final translation = client.translateTexts(
      settings: settings,
      appLocale: const Locale('en'),
      deviceLocale: const Locale('en'),
      texts: const ['Title', 'Body'],
      abortTrigger: abortCompleter.future,
    );
    final expectation = expectLater(
      translation,
      throwsA(isA<http.RequestAbortedException>()),
    );

    abortCompleter.complete();
    await expectation;
  });
}
