import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxlingo/models/ocr_script.dart';
import 'package:foxlingo/models/translation_models.dart';
import 'package:foxlingo/utils/translation_settings.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('isConfigured reflects selected provider credentials', () async {
    final settings = TranslationSettings();

    await settings.save(
      provider: TranslationProvider.llm,
      apiBaseUrl: TranslationSettings.defaultApiBaseUrl,
      apiKey: 'llm-key',
      model: TranslationSettings.defaultModel,
      systemPrompt: TranslationSettings.defaultSystemPrompt,
      targetLanguage: 'follow_app',
      googleApiKey: '',
      microsoftApiKey: '',
      microsoftRegion: '',
    );
    expect(settings.isConfigured, isTrue);

    await settings.save(
      provider: TranslationProvider.google,
      apiBaseUrl: TranslationSettings.defaultApiBaseUrl,
      apiKey: '',
      model: TranslationSettings.defaultModel,
      systemPrompt: TranslationSettings.defaultSystemPrompt,
      targetLanguage: 'follow_app',
      googleApiKey: 'google-key',
      microsoftApiKey: '',
      microsoftRegion: '',
    );
    expect(settings.isConfigured, isTrue);

    await settings.save(
      provider: TranslationProvider.microsoft,
      apiBaseUrl: TranslationSettings.defaultApiBaseUrl,
      apiKey: '',
      model: TranslationSettings.defaultModel,
      systemPrompt: TranslationSettings.defaultSystemPrompt,
      targetLanguage: 'follow_app',
      googleApiKey: '',
      microsoftApiKey: 'ms-key',
      microsoftRegion: 'eastasia',
    );
    expect(settings.isConfigured, isTrue);

    await settings.save(
      provider: TranslationProvider.microsoft,
      apiBaseUrl: TranslationSettings.defaultApiBaseUrl,
      apiKey: '',
      model: TranslationSettings.defaultModel,
      systemPrompt: TranslationSettings.defaultSystemPrompt,
      targetLanguage: 'follow_app',
      googleApiKey: '',
      microsoftApiKey: 'ms-key',
      microsoftRegion: '',
    );
    expect(settings.isConfigured, isFalse);
  });

  test('resolveGoogle and Microsoft target language codes', () async {
    final settings = TranslationSettings();

    await settings.save(
      provider: TranslationProvider.google,
      apiBaseUrl: TranslationSettings.defaultApiBaseUrl,
      apiKey: '',
      model: TranslationSettings.defaultModel,
      systemPrompt: TranslationSettings.defaultSystemPrompt,
      targetLanguage: 'zh',
      googleApiKey: 'key',
      microsoftApiKey: '',
      microsoftRegion: '',
    );

    expect(
      settings.resolveGoogleTargetLanguageCode(
        appLocale: const Locale('en'),
        deviceLocale: const Locale('en'),
      ),
      'zh-CN',
    );
    expect(
      settings.resolveMicrosoftTargetLanguageCode(
        appLocale: const Locale('en'),
        deviceLocale: const Locale('en'),
      ),
      'zh-Hans',
    );

    await settings.save(
      provider: TranslationProvider.google,
      apiBaseUrl: TranslationSettings.defaultApiBaseUrl,
      apiKey: '',
      model: TranslationSettings.defaultModel,
      systemPrompt: TranslationSettings.defaultSystemPrompt,
      targetLanguage: 'follow_app',
      googleApiKey: 'key',
      microsoftApiKey: '',
      microsoftRegion: '',
    );

    expect(
      settings.resolveGoogleTargetLanguageCode(
        appLocale: const Locale('zh'),
        deviceLocale: const Locale('en'),
      ),
      'zh-CN',
    );
    expect(
      settings.resolveMicrosoftTargetLanguageCode(
        appLocale: const Locale('zh'),
        deviceLocale: const Locale('en'),
      ),
      'zh-Hans',
    );
  });

  test('backup json round-trips new provider fields and ocrScript', () async {
    final settings = TranslationSettings();

    await settings.save(
      provider: TranslationProvider.google,
      apiBaseUrl: 'https://example.com/v1',
      apiKey: 'llm-key',
      model: 'custom-model',
      systemPrompt: 'prompt',
      targetLanguage: 'en',
      googleApiKey: 'google-key',
      microsoftApiKey: 'ms-key',
      microsoftRegion: 'global',
      ocrScript: OcrScript.japanese,
    );

    final backup = settings.toBackupJson();
    expect(backup['provider'], 'google');
    expect(backup['googleApiKey'], 'google-key');
    expect(backup['microsoftRegion'], 'global');
    expect(backup['ocrScript'], 'japanese');

    final restored = TranslationSettings();
    await restored.applyBackupJson(backup);

    expect(restored.provider, TranslationProvider.google);
    expect(restored.googleApiKey, 'google-key');
    expect(restored.microsoftApiKey, 'ms-key');
    expect(restored.microsoftRegion, 'global');
    expect(restored.targetLanguage, 'en');
    expect(restored.ocrScript, OcrScript.japanese);
  });

  test('backup without provider defaults to llm and latin OCR', () async {
    final restored = TranslationSettings();
    await restored.applyBackupJson({
      'apiBaseUrl': 'https://example.com/v1',
      'apiKey': 'secret',
      'model': 'gpt-4o-mini',
      'systemPrompt': TranslationSettings.defaultSystemPrompt,
      'targetLanguage': 'zh',
    });

    expect(restored.provider, TranslationProvider.llm);
    expect(restored.apiKey, 'secret');
    expect(restored.ocrScript, OcrScript.latin);
  });

  test('persists ocrScript across load', () async {
    final settings = TranslationSettings();
    await settings.save(
      provider: TranslationProvider.llm,
      apiBaseUrl: TranslationSettings.defaultApiBaseUrl,
      apiKey: 'key',
      model: TranslationSettings.defaultModel,
      systemPrompt: TranslationSettings.defaultSystemPrompt,
      targetLanguage: 'follow_app',
      googleApiKey: '',
      microsoftApiKey: '',
      microsoftRegion: '',
      ocrScript: OcrScript.chinese,
    );

    final reloaded = TranslationSettings();
    await reloaded.load();
    expect(reloaded.ocrScript, OcrScript.chinese);
  });
}
