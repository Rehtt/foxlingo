import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/ocr_script.dart';
import '../models/translation_models.dart';

enum ScreenTranslationMode { fullScreen, region }

class TranslationSettings extends ChangeNotifier {
  TranslationSettings({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  TranslationSettings.snapshot(TranslationSettings source)
    : _secureStorage = source._secureStorage,
      _provider = source._provider,
      _apiBaseUrl = source._apiBaseUrl,
      _apiKey = source._apiKey,
      _model = source._model,
      _systemPrompt = source._systemPrompt,
      _targetLanguage = source._targetLanguage,
      _googleApiKey = source._googleApiKey,
      _microsoftApiKey = source._microsoftApiKey,
      _microsoftRegion = source._microsoftRegion,
      _imageMethod = source._imageMethod,
      _imageLlmApiBaseUrl = source._imageLlmApiBaseUrl,
      _imageLlmApiKey = source._imageLlmApiKey,
      _imageLlmModel = source._imageLlmModel,
      _reasoningEffort = source._reasoningEffort,
      _ocrScript = source._ocrScript,
      _screenTranslationMode = source._screenTranslationMode;

  /// Copies the current values without reading or writing secure storage.
  /// A translation request owns this snapshot for its entire lifetime, so
  /// changing settings in the foreground cannot switch its provider halfway
  /// through a request.
  TranslationSettings snapshot() => TranslationSettings.snapshot(this);

  static const String defaultApiBaseUrl = 'https://api.openai.com/v1';
  static const String defaultModel = 'gpt-4o-mini';
  static const String defaultSystemPrompt =
      'You are a translator. Translate the user text into {targetLanguage}. '
      'Preserve formatting, names, and URLs. Return only the translated result '
      'in the exact output format requested.';

  static const String _providerKey = 'translation.provider';
  static const String _apiBaseUrlKey = 'translation.apiBaseUrl';
  static const String _apiKeyKey = 'translation.apiKey';
  static const String _modelKey = 'translation.model';
  static const String _systemPromptKey = 'translation.systemPrompt';
  static const String _targetLanguageKey = 'translation.targetLanguage';
  static const String _googleApiKeyKey = 'translation.googleApiKey';
  static const String _microsoftApiKeyKey = 'translation.microsoftApiKey';
  static const String _microsoftRegionKey = 'translation.microsoftRegion';
  static const String _imageMethodKey = 'translation.imageMethod';
  static const String _imageLlmApiBaseUrlKey = 'translation.imageLlmApiBaseUrl';
  static const String _imageLlmApiKeyKey = 'translation.imageLlmApiKey';
  static const String _imageLlmModelKey = 'translation.imageLlmModel';
  static const String _reasoningEffortKey = 'translation.reasoningEffort';
  static const String _ocrScriptKey = 'translation.ocrScript';
  static const String _screenTranslationModeKey =
      'translation.screenTranslationMode';

  final FlutterSecureStorage _secureStorage;

  TranslationProvider _provider = TranslationProvider.llm;
  String _apiBaseUrl = defaultApiBaseUrl;
  String _apiKey = '';
  String _model = defaultModel;
  String _systemPrompt = defaultSystemPrompt;
  String _targetLanguage = 'follow_app';
  String _googleApiKey = '';
  String _microsoftApiKey = '';
  String _microsoftRegion = '';
  ImageTranslationMethod _imageMethod = ImageTranslationMethod.ocr;
  String _imageLlmApiBaseUrl = '';
  String _imageLlmApiKey = '';
  String _imageLlmModel = '';
  String _reasoningEffort = '';
  OcrScript _ocrScript = OcrScript.latin;
  ScreenTranslationMode _screenTranslationMode =
      ScreenTranslationMode.fullScreen;

  TranslationProvider get provider => _provider;
  String get apiBaseUrl => _apiBaseUrl;
  String get apiKey => _apiKey;
  String get model => _model;
  String get systemPrompt => _systemPrompt;
  String get targetLanguage => _targetLanguage;
  String get googleApiKey => _googleApiKey;
  String get microsoftApiKey => _microsoftApiKey;
  String get microsoftRegion => _microsoftRegion;
  ImageTranslationMethod get imageMethod => _imageMethod;
  OcrScript get ocrScript => _ocrScript;
  ScreenTranslationMode get screenTranslationMode => _screenTranslationMode;

  /// Raw stored values; empty means "fall back to the text LLM settings".
  String get imageLlmApiBaseUrl => _imageLlmApiBaseUrl;
  String get imageLlmApiKey => _imageLlmApiKey;
  String get imageLlmModel => _imageLlmModel;
  String get reasoningEffort => _reasoningEffort;

  String get effectiveImageLlmApiBaseUrl =>
      _imageLlmApiBaseUrl.isEmpty ? _apiBaseUrl : _imageLlmApiBaseUrl;
  String get effectiveImageLlmApiKey =>
      _imageLlmApiKey.isEmpty ? _apiKey : _imageLlmApiKey;
  String get effectiveImageLlmModel =>
      _imageLlmModel.isEmpty ? _model : _imageLlmModel;

  bool get isConfigured => switch (_provider) {
    TranslationProvider.llm => _apiKey.isNotEmpty,
    TranslationProvider.google => _googleApiKey.isNotEmpty,
    TranslationProvider.microsoft =>
      _microsoftApiKey.isNotEmpty && _microsoftRegion.isNotEmpty,
  };

  bool get isImageLlmConfigured => effectiveImageLlmApiKey.isNotEmpty;

  Map<String, dynamic> toBackupJson({bool includeApiKey = true}) {
    return {
      'provider': _provider.name,
      'apiBaseUrl': _apiBaseUrl,
      if (includeApiKey) 'apiKey': _apiKey,
      'model': _model,
      'systemPrompt': _systemPrompt,
      'targetLanguage': _targetLanguage,
      if (includeApiKey) 'googleApiKey': _googleApiKey,
      if (includeApiKey) 'microsoftApiKey': _microsoftApiKey,
      'microsoftRegion': _microsoftRegion,
      'imageMethod': _imageMethod.name,
      'imageLlmApiBaseUrl': _imageLlmApiBaseUrl,
      if (includeApiKey) 'imageLlmApiKey': _imageLlmApiKey,
      'imageLlmModel': _imageLlmModel,
      'reasoningEffort': _reasoningEffort,
      'ocrScript': _ocrScript.name,
      'screenTranslationMode': _screenTranslationMode.name,
    };
  }

  Future<void> applyBackupJson(Map<String, dynamic> json) async {
    _provider = _normalizeProvider(json['provider']);
    _apiBaseUrl = _nonEmptyString(json['apiBaseUrl'], defaultApiBaseUrl);
    if (json.containsKey('apiKey')) {
      _apiKey = (json['apiKey'] as String? ?? '').trim();
    }
    _model = _nonEmptyString(json['model'], defaultModel);
    _systemPrompt = _nonEmptyString(json['systemPrompt'], defaultSystemPrompt);
    _targetLanguage = _normalizeTargetLanguage(json['targetLanguage']);
    if (json.containsKey('googleApiKey')) {
      _googleApiKey = (json['googleApiKey'] as String? ?? '').trim();
    }
    if (json.containsKey('microsoftApiKey')) {
      _microsoftApiKey = (json['microsoftApiKey'] as String? ?? '').trim();
    }
    _microsoftRegion = (json['microsoftRegion'] as String? ?? '').trim();
    _imageMethod = _normalizeImageMethod(json['imageMethod']);
    _imageLlmApiBaseUrl = (json['imageLlmApiBaseUrl'] as String? ?? '').trim();
    if (json.containsKey('imageLlmApiKey')) {
      _imageLlmApiKey = (json['imageLlmApiKey'] as String? ?? '').trim();
    }
    _imageLlmModel = (json['imageLlmModel'] as String? ?? '').trim();
    _reasoningEffort = (json['reasoningEffort'] as String? ?? '').trim();
    _ocrScript = _normalizeOcrScript(json['ocrScript']);
    _screenTranslationMode = _normalizeScreenTranslationMode(
      json['screenTranslationMode'],
    );

    await _persistAll();
    notifyListeners();
  }

  Future<void> load() async {
    _provider = _normalizeProvider(
      await _secureStorage.read(key: _providerKey),
    );
    _apiBaseUrl =
        await _secureStorage.read(key: _apiBaseUrlKey) ?? defaultApiBaseUrl;
    _apiKey = await _secureStorage.read(key: _apiKeyKey) ?? '';
    _model = await _secureStorage.read(key: _modelKey) ?? defaultModel;
    _systemPrompt =
        await _secureStorage.read(key: _systemPromptKey) ?? defaultSystemPrompt;
    _targetLanguage =
        await _secureStorage.read(key: _targetLanguageKey) ?? 'follow_app';
    _googleApiKey = await _secureStorage.read(key: _googleApiKeyKey) ?? '';
    _microsoftApiKey =
        await _secureStorage.read(key: _microsoftApiKeyKey) ?? '';
    _microsoftRegion =
        await _secureStorage.read(key: _microsoftRegionKey) ?? '';
    _imageMethod = _normalizeImageMethod(
      await _secureStorage.read(key: _imageMethodKey),
    );
    _imageLlmApiBaseUrl =
        await _secureStorage.read(key: _imageLlmApiBaseUrlKey) ?? '';
    _imageLlmApiKey = await _secureStorage.read(key: _imageLlmApiKeyKey) ?? '';
    _imageLlmModel = await _secureStorage.read(key: _imageLlmModelKey) ?? '';
    _reasoningEffort =
        await _secureStorage.read(key: _reasoningEffortKey) ?? '';
    _ocrScript = _normalizeOcrScript(
      await _secureStorage.read(key: _ocrScriptKey),
    );
    _screenTranslationMode = _normalizeScreenTranslationMode(
      await _secureStorage.read(key: _screenTranslationModeKey),
    );
    notifyListeners();
  }

  Future<void> save({
    required TranslationProvider provider,
    required String apiBaseUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String targetLanguage,
    required String googleApiKey,
    required String microsoftApiKey,
    required String microsoftRegion,
    ImageTranslationMethod imageMethod = ImageTranslationMethod.ocr,
    String imageLlmApiBaseUrl = '',
    String imageLlmApiKey = '',
    String imageLlmModel = '',
    String reasoningEffort = '',
    OcrScript ocrScript = OcrScript.latin,
  }) async {
    _provider = provider;
    _apiBaseUrl = apiBaseUrl.trim().isEmpty
        ? defaultApiBaseUrl
        : apiBaseUrl.trim();
    _apiKey = apiKey.trim();
    _model = model.trim().isEmpty ? defaultModel : model.trim();
    _systemPrompt = systemPrompt.trim().isEmpty
        ? defaultSystemPrompt
        : systemPrompt.trim();
    _targetLanguage = targetLanguage;
    _googleApiKey = googleApiKey.trim();
    _microsoftApiKey = microsoftApiKey.trim();
    _microsoftRegion = microsoftRegion.trim();
    _imageMethod = imageMethod;
    _imageLlmApiBaseUrl = imageLlmApiBaseUrl.trim();
    _imageLlmApiKey = imageLlmApiKey.trim();
    _imageLlmModel = imageLlmModel.trim();
    _reasoningEffort = reasoningEffort.trim();
    _ocrScript = ocrScript;

    await _persistAll();
    notifyListeners();
  }

  Future<void> setScreenTranslationMode(ScreenTranslationMode mode) async {
    if (_screenTranslationMode == mode) {
      return;
    }
    await _secureStorage.write(
      key: _screenTranslationModeKey,
      value: mode.name,
    );
    _screenTranslationMode = mode;
    notifyListeners();
  }

  Future<void> _persistAll() async {
    await _secureStorage.write(key: _providerKey, value: _provider.name);
    await _secureStorage.write(key: _apiBaseUrlKey, value: _apiBaseUrl);
    await _secureStorage.write(key: _apiKeyKey, value: _apiKey);
    await _secureStorage.write(key: _modelKey, value: _model);
    await _secureStorage.write(key: _systemPromptKey, value: _systemPrompt);
    await _secureStorage.write(key: _targetLanguageKey, value: _targetLanguage);
    await _secureStorage.write(key: _googleApiKeyKey, value: _googleApiKey);
    await _secureStorage.write(
      key: _microsoftApiKeyKey,
      value: _microsoftApiKey,
    );
    await _secureStorage.write(
      key: _microsoftRegionKey,
      value: _microsoftRegion,
    );
    await _secureStorage.write(key: _imageMethodKey, value: _imageMethod.name);
    await _secureStorage.write(
      key: _imageLlmApiBaseUrlKey,
      value: _imageLlmApiBaseUrl,
    );
    await _secureStorage.write(key: _imageLlmApiKeyKey, value: _imageLlmApiKey);
    await _secureStorage.write(key: _imageLlmModelKey, value: _imageLlmModel);
    await _secureStorage.write(
      key: _reasoningEffortKey,
      value: _reasoningEffort,
    );
    await _secureStorage.write(key: _ocrScriptKey, value: _ocrScript.name);
    await _secureStorage.write(
      key: _screenTranslationModeKey,
      value: _screenTranslationMode.name,
    );
  }

  String resolveTargetLanguageName({
    required Locale? appLocale,
    required Locale deviceLocale,
  }) {
    return targetLanguageNameFor(
      preference: _targetLanguage,
      appLocale: appLocale,
      deviceLocale: deviceLocale,
    );
  }

  /// Target language code for Google Cloud Translation API.
  String resolveGoogleTargetLanguageCode({
    required Locale? appLocale,
    required Locale deviceLocale,
  }) {
    return googleTargetLanguageCodeFor(
      preference: _targetLanguage,
      appLocale: appLocale,
      deviceLocale: deviceLocale,
    );
  }

  /// Target language code for Microsoft Azure Translator API.
  String resolveMicrosoftTargetLanguageCode({
    required Locale? appLocale,
    required Locale deviceLocale,
  }) {
    return microsoftTargetLanguageCodeFor(
      preference: _targetLanguage,
      appLocale: appLocale,
      deviceLocale: deviceLocale,
    );
  }

  String buildSystemMessage({
    required Locale? appLocale,
    required Locale deviceLocale,
  }) {
    return systemMessageFor(
      systemPrompt: _systemPrompt,
      preference: _targetLanguage,
      appLocale: appLocale,
      deviceLocale: deviceLocale,
    );
  }

  static String targetLanguageNameFor({
    required String preference,
    required Locale? appLocale,
    required Locale deviceLocale,
  }) {
    if (preference == 'en') {
      return 'English';
    }
    if (preference == 'zh') {
      return 'Simplified Chinese';
    }

    final locale = appLocale ?? deviceLocale;
    return locale.languageCode == 'zh' ? 'Simplified Chinese' : 'English';
  }

  static String googleTargetLanguageCodeFor({
    required String preference,
    required Locale? appLocale,
    required Locale deviceLocale,
  }) {
    return _targetLanguageCodeFor(
      preference: preference,
      appLocale: appLocale,
      deviceLocale: deviceLocale,
      google: true,
    );
  }

  static String microsoftTargetLanguageCodeFor({
    required String preference,
    required Locale? appLocale,
    required Locale deviceLocale,
  }) {
    return _targetLanguageCodeFor(
      preference: preference,
      appLocale: appLocale,
      deviceLocale: deviceLocale,
      google: false,
    );
  }

  static String systemMessageFor({
    required String systemPrompt,
    required String preference,
    required Locale? appLocale,
    required Locale deviceLocale,
  }) {
    final prompt = systemPrompt.trim().isEmpty
        ? defaultSystemPrompt
        : systemPrompt.trim();
    final targetLanguage = targetLanguageNameFor(
      preference: preference,
      appLocale: appLocale,
      deviceLocale: deviceLocale,
    );
    return prompt.replaceAll('{targetLanguage}', targetLanguage);
  }

  static String _targetLanguageCodeFor({
    required String preference,
    required Locale? appLocale,
    required Locale deviceLocale,
    required bool google,
  }) {
    if (preference == 'en') {
      return 'en';
    }
    if (preference == 'zh') {
      return google ? 'zh-CN' : 'zh-Hans';
    }

    final locale = appLocale ?? deviceLocale;
    if (locale.languageCode == 'zh') {
      return google ? 'zh-CN' : 'zh-Hans';
    }
    return 'en';
  }

  static String _nonEmptyString(Object? value, String fallback) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? fallback : text;
  }

  static String _normalizeTargetLanguage(Object? value) {
    return switch (value) {
      'en' => 'en',
      'zh' => 'zh',
      _ => 'follow_app',
    };
  }

  static TranslationProvider _normalizeProvider(Object? value) {
    return switch (value) {
      'google' => TranslationProvider.google,
      'microsoft' => TranslationProvider.microsoft,
      _ => TranslationProvider.llm,
    };
  }

  static ImageTranslationMethod _normalizeImageMethod(Object? value) {
    return switch (value) {
      'llm' => ImageTranslationMethod.llm,
      _ => ImageTranslationMethod.ocr,
    };
  }

  static OcrScript _normalizeOcrScript(Object? value) {
    return switch (value) {
      'chinese' => OcrScript.chinese,
      'japanese' => OcrScript.japanese,
      'korean' => OcrScript.korean,
      _ => OcrScript.latin,
    };
  }

  static ScreenTranslationMode _normalizeScreenTranslationMode(Object? value) {
    return switch (value) {
      'region' => ScreenTranslationMode.region,
      _ => ScreenTranslationMode.fullScreen,
    };
  }
}

class TranslationSettingsScope extends InheritedNotifier<TranslationSettings> {
  const TranslationSettingsScope({
    super.key,
    required TranslationSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static TranslationSettings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TranslationSettingsScope>();
    assert(scope != null, 'TranslationSettingsScope not found in widget tree.');
    return scope!.notifier!;
  }
}
