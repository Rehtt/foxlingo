import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foxlingo/client/traditional_translation_client.dart';
import 'package:foxlingo/models/translation_models.dart';
import 'package:foxlingo/utils/translation_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<TranslationSettings> googleSettings() async {
    final settings = TranslationSettings();
    await settings.save(
      provider: TranslationProvider.google,
      apiBaseUrl: TranslationSettings.defaultApiBaseUrl,
      apiKey: '',
      model: TranslationSettings.defaultModel,
      systemPrompt: TranslationSettings.defaultSystemPrompt,
      targetLanguage: 'zh',
      googleApiKey: 'google-test-key',
      microsoftApiKey: '',
      microsoftRegion: '',
    );
    return settings;
  }

  Future<TranslationSettings> microsoftSettings() async {
    final settings = TranslationSettings();
    await settings.save(
      provider: TranslationProvider.microsoft,
      apiBaseUrl: TranslationSettings.defaultApiBaseUrl,
      apiKey: '',
      model: TranslationSettings.defaultModel,
      systemPrompt: TranslationSettings.defaultSystemPrompt,
      targetLanguage: 'zh',
      googleApiKey: '',
      microsoftApiKey: 'ms-test-key',
      microsoftRegion: 'eastasia',
    );
    return settings;
  }

  test('translates texts via Google API', () async {
    final settings = await googleSettings();
    final client = TraditionalTranslationClient(
      httpClient: MockClient((request) async {
        expect(request.url.host, 'translation.googleapis.com');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['target'], 'zh-CN');
        expect(body['q'], ['Title', 'Body']);

        return _utf8Response({
          'data': {
            'translations': [
              {'translatedText': '标题'},
              {'translatedText': '正文'},
            ],
          },
        });
      }),
    );

    final translated = await client.translateTexts(
      settings: settings,
      appLocale: const Locale('en'),
      deviceLocale: const Locale('en'),
      texts: const ['Title', 'Body'],
    );

    expect(translated, ['标题', '正文']);
  });

  test('translates texts via Microsoft API', () async {
    final settings = await microsoftSettings();
    final client = TraditionalTranslationClient(
      httpClient: MockClient((request) async {
        expect(request.url.host, 'api.cognitive.microsofttranslator.com');
        expect(request.headers['Ocp-Apim-Subscription-Key'], 'ms-test-key');
        expect(request.headers['Ocp-Apim-Subscription-Region'], 'eastasia');

        return _utf8Response([
          {
            'translations': [
              {'text': '狼', 'to': 'zh-Hans'},
            ],
          },
          {
            'translations': [
              {'text': '奇幻', 'to': 'zh-Hans'},
            ],
          },
        ]);
      }),
    );

    final translated = await client.translateTexts(
      settings: settings,
      appLocale: const Locale('en'),
      deviceLocale: const Locale('en'),
      texts: const ['wolf', 'fantasy'],
    );

    expect(translated, ['狼', '奇幻']);
  });

  test('translateTexts batches strings with Google', () async {
    final settings = await googleSettings();
    final client = TraditionalTranslationClient(
      httpClient: MockClient((request) async {
        return _utf8Response({
          'data': {
            'translations': [
              {'translatedText': '一'},
              {'translatedText': '二'},
            ],
          },
        });
      }),
    );

    final translated = await client.translateTexts(
      settings: settings,
      appLocale: const Locale('en'),
      deviceLocale: const Locale('en'),
      texts: const ['one', 'two'],
    );

    expect(translated, ['一', '二']);
  });

  for (final provider in [
    TranslationProvider.google,
    TranslationProvider.microsoft,
  ]) {
    test('aborts an in-flight ${provider.name} request', () async {
      final settings = provider == TranslationProvider.google
          ? await googleSettings()
          : await microsoftSettings();
      final abortCompleter = Completer<void>();
      final client = TraditionalTranslationClient(
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
        texts: const ['wolf'],
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
}

http.Response _utf8Response(Object body) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
