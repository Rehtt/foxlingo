import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foxlingo/client/llm_translation_client.dart';
import 'package:foxlingo/models/translation_models.dart';
import 'package:foxlingo/utils/translation_settings.dart';

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

  test('aborts an in-flight LLM request', () async {
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
    );
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
