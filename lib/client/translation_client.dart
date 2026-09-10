import 'package:flutter/material.dart';

import '../models/translation_models.dart';
import '../utils/translation_settings.dart';
import 'llm_translation_client.dart';
import 'traditional_translation_client.dart';

class TranslationClient {
  TranslationClient({
    LlmTranslationClient? llmClient,
    TraditionalTranslationClient? traditionalClient,
  }) : _llmClient = llmClient ?? LlmTranslationClient(),
       _traditionalClient = traditionalClient ?? TraditionalTranslationClient();

  final LlmTranslationClient _llmClient;
  final TraditionalTranslationClient _traditionalClient;

  Future<List<String>> translateTexts({
    required TranslationSettings settings,
    required Locale? appLocale,
    required Locale deviceLocale,
    required List<String> texts,
    Future<void>? abortTrigger,
  }) {
    return switch (settings.provider) {
      TranslationProvider.llm => _llmClient.translateTexts(
        settings: settings,
        appLocale: appLocale,
        deviceLocale: deviceLocale,
        texts: texts,
        abortTrigger: abortTrigger,
      ),
      TranslationProvider.google ||
      TranslationProvider.microsoft => _traditionalClient.translateTexts(
        settings: settings,
        appLocale: appLocale,
        deviceLocale: deviceLocale,
        texts: texts,
        abortTrigger: abortTrigger,
      ),
    };
  }
}
