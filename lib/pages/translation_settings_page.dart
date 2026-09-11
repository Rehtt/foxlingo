import 'dart:async';

import 'package:flutter/material.dart';

import '../client/llm_image_translation_client.dart';
import '../client/llm_translation_client.dart';
import '../client/traditional_translation_client.dart';
import '../l10n/app_localizations.dart';
import '../models/ocr_script.dart';
import '../models/translation_models.dart';
import '../utils/app_settings.dart';
import '../utils/translation_settings.dart';

class TranslationSettingsPage extends StatefulWidget {
  const TranslationSettingsPage({
    super.key,
    required this.settings,
    this.embedded = false,
  });

  final TranslationSettings settings;
  final bool embedded;

  @override
  State<TranslationSettingsPage> createState() =>
      _TranslationSettingsPageState();
}

class _TranslationSettingsPageState extends State<TranslationSettingsPage> {
  late final TextEditingController _apiBaseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _systemPromptController;
  late final TextEditingController _googleApiKeyController;
  late final TextEditingController _microsoftApiKeyController;
  late final TextEditingController _microsoftRegionController;
  late final TextEditingController _imageLlmApiBaseUrlController;
  late final TextEditingController _imageLlmApiKeyController;
  late final TextEditingController _imageLlmModelController;
  late final TextEditingController _reasoningEffortController;
  late TranslationProvider _provider;
  late ImageTranslationMethod _imageMethod;
  late OcrScript _ocrScript;
  late String _targetLanguage;
  bool _obscureApiKey = true;
  bool _obscureGoogleApiKey = true;
  bool _obscureMicrosoftApiKey = true;
  bool _obscureImageLlmApiKey = true;
  bool _isSaving = false;
  bool _isTestingProvider = false;
  bool _isTestingImage = false;
  final LlmTranslationClient _llmClient = LlmTranslationClient();
  final TraditionalTranslationClient _traditionalClient =
      TraditionalTranslationClient();
  final LlmImageTranslationClient _imageLlmClient = LlmImageTranslationClient();

  bool get _isBusy => _isSaving || _isTestingProvider || _isTestingImage;

  @override
  void initState() {
    super.initState();
    _provider = widget.settings.provider;
    _apiBaseUrlController = TextEditingController(
      text: widget.settings.apiBaseUrl,
    );
    _apiKeyController = TextEditingController(text: widget.settings.apiKey);
    _modelController = TextEditingController(text: widget.settings.model);
    _systemPromptController = TextEditingController(
      text: widget.settings.systemPrompt,
    );
    _googleApiKeyController = TextEditingController(
      text: widget.settings.googleApiKey,
    );
    _microsoftApiKeyController = TextEditingController(
      text: widget.settings.microsoftApiKey,
    );
    _microsoftRegionController = TextEditingController(
      text: widget.settings.microsoftRegion,
    );
    _imageMethod = widget.settings.imageMethod;
    _ocrScript = widget.settings.ocrScript;
    _imageLlmApiBaseUrlController = TextEditingController(
      text: widget.settings.imageLlmApiBaseUrl,
    );
    _imageLlmApiKeyController = TextEditingController(
      text: widget.settings.imageLlmApiKey,
    );
    _imageLlmModelController = TextEditingController(
      text: widget.settings.imageLlmModel,
    );
    _reasoningEffortController = TextEditingController(
      text: widget.settings.reasoningEffort,
    );
    _targetLanguage = widget.settings.targetLanguage;
  }

  @override
  void dispose() {
    _apiBaseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _systemPromptController.dispose();
    _googleApiKeyController.dispose();
    _microsoftApiKeyController.dispose();
    _microsoftRegionController.dispose();
    _imageLlmApiBaseUrlController.dispose();
    _imageLlmApiKeyController.dispose();
    _imageLlmModelController.dispose();
    _reasoningEffortController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await widget.settings.save(
      provider: _provider,
      apiBaseUrl: _apiBaseUrlController.text,
      apiKey: _apiKeyController.text,
      model: _modelController.text,
      systemPrompt: _systemPromptController.text,
      targetLanguage: _targetLanguage,
      googleApiKey: _googleApiKeyController.text,
      microsoftApiKey: _microsoftApiKeyController.text,
      microsoftRegion: _microsoftRegionController.text,
      imageMethod: _imageMethod,
      imageLlmApiBaseUrl: _imageLlmApiBaseUrlController.text,
      imageLlmApiKey: _imageLlmApiKeyController.text,
      imageLlmModel: _imageLlmModelController.text,
      reasoningEffort: _reasoningEffortController.text,
      ocrScript: _ocrScript,
    );
    if (!mounted) {
      return;
    }

    setState(() => _isSaving = false);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatTestError(Object error) {
    final text = switch (error) {
      TimeoutException() => 'Request timed out.',
      StateError(:final message) => message,
      _ => error.toString(),
    }.trim();
    if (text.length <= 200) {
      return text;
    }
    return '${text.substring(0, 200).trimRight()}…';
  }

  Locale? get _appLocale => AppSettingsScope.of(context).locale;

  Locale get _deviceLocale => View.of(context).platformDispatcher.locale;

  String get _effectiveImageLlmApiBaseUrl {
    final imageUrl = _imageLlmApiBaseUrlController.text.trim();
    if (imageUrl.isNotEmpty) {
      return imageUrl;
    }
    final textUrl = _apiBaseUrlController.text.trim();
    return textUrl.isEmpty ? TranslationSettings.defaultApiBaseUrl : textUrl;
  }

  String get _effectiveImageLlmApiKey {
    final imageKey = _imageLlmApiKeyController.text.trim();
    return imageKey.isNotEmpty ? imageKey : _apiKeyController.text.trim();
  }

  String get _effectiveImageLlmModel {
    final imageModel = _imageLlmModelController.text.trim();
    if (imageModel.isNotEmpty) {
      return imageModel;
    }
    final textModel = _modelController.text.trim();
    return textModel.isEmpty ? TranslationSettings.defaultModel : textModel;
  }

  Future<void> _testProvider() async {
    final l10n = AppLocalizations.of(context);
    final isConfigured = switch (_provider) {
      TranslationProvider.llm => _apiKeyController.text.trim().isNotEmpty,
      TranslationProvider.google =>
        _googleApiKeyController.text.trim().isNotEmpty,
      TranslationProvider.microsoft =>
        _microsoftApiKeyController.text.trim().isNotEmpty &&
            _microsoftRegionController.text.trim().isNotEmpty,
    };
    if (!isConfigured) {
      _showSnackBar(l10n.translationNotConfigured);
      return;
    }

    setState(() => _isTestingProvider = true);
    try {
      final sample = await switch (_provider) {
        TranslationProvider.llm => _llmClient.testConnection(
          apiBaseUrl: _apiBaseUrlController.text,
          apiKey: _apiKeyController.text,
          model: _modelController.text,
          reasoningEffort: _reasoningEffortController.text,
          systemMessage: TranslationSettings.systemMessageFor(
            systemPrompt: _systemPromptController.text,
            preference: _targetLanguage,
            appLocale: _appLocale,
            deviceLocale: _deviceLocale,
          ),
        ),
        TranslationProvider.google => _traditionalClient.testConnection(
          provider: TranslationProvider.google,
          googleApiKey: _googleApiKeyController.text,
          microsoftApiKey: '',
          microsoftRegion: '',
          targetLanguageCode: TranslationSettings.googleTargetLanguageCodeFor(
            preference: _targetLanguage,
            appLocale: _appLocale,
            deviceLocale: _deviceLocale,
          ),
        ),
        TranslationProvider.microsoft => _traditionalClient.testConnection(
          provider: TranslationProvider.microsoft,
          googleApiKey: '',
          microsoftApiKey: _microsoftApiKeyController.text,
          microsoftRegion: _microsoftRegionController.text,
          targetLanguageCode:
              TranslationSettings.microsoftTargetLanguageCodeFor(
                preference: _targetLanguage,
                appLocale: _appLocale,
                deviceLocale: _deviceLocale,
              ),
        ),
      };
      if (!mounted) {
        return;
      }
      _showSnackBar(
        _provider == TranslationProvider.llm
            ? l10n.translationTestSuccess
            : l10n.translationTestSuccessWithResult(sample),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(l10n.translationTestFailed(_formatTestError(error)));
    } finally {
      if (mounted) {
        setState(() => _isTestingProvider = false);
      }
    }
  }

  Future<void> _testImageLlm() async {
    final l10n = AppLocalizations.of(context);
    if (_effectiveImageLlmApiKey.isEmpty) {
      _showSnackBar(l10n.imageTranslationLlmNotConfigured);
      return;
    }

    setState(() => _isTestingImage = true);
    try {
      await _imageLlmClient.testConnection(
        apiBaseUrl: _effectiveImageLlmApiBaseUrl,
        apiKey: _effectiveImageLlmApiKey,
        model: _effectiveImageLlmModel,
        reasoningEffort: _reasoningEffortController.text,
      );
      if (!mounted) {
        return;
      }
      _showSnackBar(l10n.translationTestSuccess);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(l10n.translationTestFailed(_formatTestError(error)));
    } finally {
      if (mounted) {
        setState(() => _isTestingImage = false);
      }
    }
  }

  Widget _buildTestButton({
    required bool isTesting,
    required VoidCallback? onPressed,
    required String label,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: isTesting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.network_check),
      label: Text(label),
    );
  }

  Widget _buildObscuredKeyField({
    required TextEditingController controller,
    required String labelText,
    required bool obscure,
    required VoidCallback onToggleObscure,
    required String showTooltip,
    required String hideTooltip,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: labelText,
        helperText: helperText,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: obscure ? showTooltip : hideTooltip,
          onPressed: onToggleObscure,
          icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
        ),
      ),
    );
  }

  Widget _buildReasoningEffortField(AppLocalizations l10n) {
    return DropdownMenu<String>(
      controller: _reasoningEffortController,
      requestFocusOnTap: true,
      expandedInsets: EdgeInsets.zero,
      label: Text(l10n.translationReasoningEffort),
      helperText: l10n.translationReasoningEffortHint,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      dropdownMenuEntries: [
        for (final value in llmReasoningEffortPresets)
          DropdownMenuEntry<String>(value: value, label: value),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(l10n.translationSettings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<TranslationProvider>(
            key: ValueKey(_provider),
            initialValue: _provider,
            decoration: InputDecoration(
              labelText: l10n.translationProvider,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: TranslationProvider.llm,
                child: Text(l10n.translationProviderLlm),
              ),
              DropdownMenuItem(
                value: TranslationProvider.google,
                child: Text(l10n.translationProviderGoogle),
              ),
              DropdownMenuItem(
                value: TranslationProvider.microsoft,
                child: Text(l10n.translationProviderMicrosoft),
              ),
            ],
            onChanged: _isBusy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _provider = value);
                    }
                  },
          ),
          const SizedBox(height: 16),
          if (_provider == TranslationProvider.llm) ...[
            TextFormField(
              controller: _apiBaseUrlController,
              decoration: InputDecoration(
                labelText: l10n.translationApiBaseUrl,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildObscuredKeyField(
              controller: _apiKeyController,
              labelText: l10n.translationApiKey,
              obscure: _obscureApiKey,
              onToggleObscure: () =>
                  setState(() => _obscureApiKey = !_obscureApiKey),
              showTooltip: l10n.showApiKey,
              hideTooltip: l10n.hideApiKey,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _modelController,
              decoration: InputDecoration(
                labelText: l10n.translationModel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildReasoningEffortField(l10n),
            const SizedBox(height: 16),
            TextFormField(
              controller: _systemPromptController,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: l10n.translationSystemPrompt,
                helperText: l10n.translationSettingsHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ] else if (_provider == TranslationProvider.google) ...[
            _buildObscuredKeyField(
              controller: _googleApiKeyController,
              labelText: l10n.translationGoogleApiKey,
              obscure: _obscureGoogleApiKey,
              onToggleObscure: () =>
                  setState(() => _obscureGoogleApiKey = !_obscureGoogleApiKey),
              showTooltip: l10n.showApiKey,
              hideTooltip: l10n.hideApiKey,
            ),
          ] else ...[
            _buildObscuredKeyField(
              controller: _microsoftApiKeyController,
              labelText: l10n.translationMicrosoftApiKey,
              obscure: _obscureMicrosoftApiKey,
              onToggleObscure: () => setState(
                () => _obscureMicrosoftApiKey = !_obscureMicrosoftApiKey,
              ),
              showTooltip: l10n.showApiKey,
              hideTooltip: l10n.hideApiKey,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _microsoftRegionController,
              decoration: InputDecoration(
                labelText: l10n.translationMicrosoftRegion,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildTestButton(
            isTesting: _isTestingProvider,
            onPressed: _isBusy ? null : _testProvider,
            label: l10n.translationTest,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(_targetLanguage),
            initialValue: _targetLanguage,
            decoration: InputDecoration(
              labelText: l10n.translationTargetLanguage,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: 'follow_app',
                child: Text(l10n.translationTargetFollowApp),
              ),
              DropdownMenuItem(value: 'en', child: Text(l10n.languageEnglish)),
              DropdownMenuItem(value: 'zh', child: Text(l10n.languageChinese)),
            ],
            onChanged: _isBusy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _targetLanguage = value);
                    }
                  },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ImageTranslationMethod>(
            key: ValueKey(_imageMethod),
            initialValue: _imageMethod,
            decoration: InputDecoration(
              labelText: l10n.imageTranslationMethod,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: ImageTranslationMethod.ocr,
                child: Text(l10n.imageTranslationMethodOcr),
              ),
              DropdownMenuItem(
                value: ImageTranslationMethod.llm,
                child: Text(l10n.imageTranslationMethodLlm),
              ),
            ],
            onChanged: _isBusy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _imageMethod = value);
                    }
                  },
          ),
          if (_imageMethod == ImageTranslationMethod.ocr) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<OcrScript>(
              key: ValueKey(_ocrScript),
              initialValue: _ocrScript,
              decoration: InputDecoration(
                labelText: l10n.ocrScript,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: OcrScript.latin,
                  child: Text(l10n.ocrScriptLatin),
                ),
                DropdownMenuItem(
                  value: OcrScript.chinese,
                  child: Text(l10n.ocrScriptChinese),
                ),
                DropdownMenuItem(
                  value: OcrScript.japanese,
                  child: Text(l10n.ocrScriptJapanese),
                ),
                DropdownMenuItem(
                  value: OcrScript.korean,
                  child: Text(l10n.ocrScriptKorean),
                ),
              ],
              onChanged: _isBusy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _ocrScript = value);
                      }
                    },
            ),
          ],
          if (_imageMethod == ImageTranslationMethod.llm) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _imageLlmApiBaseUrlController,
              decoration: InputDecoration(
                labelText: l10n.imageTranslationLlmApiBaseUrl,
                helperText: l10n.imageTranslationLlmFallbackHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildObscuredKeyField(
              controller: _imageLlmApiKeyController,
              labelText: l10n.imageTranslationLlmApiKey,
              obscure: _obscureImageLlmApiKey,
              onToggleObscure: () => setState(
                () => _obscureImageLlmApiKey = !_obscureImageLlmApiKey,
              ),
              showTooltip: l10n.showApiKey,
              hideTooltip: l10n.hideApiKey,
              helperText: l10n.imageTranslationLlmFallbackHint,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _imageLlmModelController,
              decoration: InputDecoration(
                labelText: l10n.imageTranslationLlmModel,
                helperText: l10n.imageTranslationLlmFallbackHint,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_provider != TranslationProvider.llm) ...[
              const SizedBox(height: 16),
              _buildReasoningEffortField(l10n),
            ],
            const SizedBox(height: 16),
            _buildTestButton(
              isTesting: _isTestingImage,
              onPressed: _isBusy ? null : _testImageLlm,
              label: l10n.imageTranslationTest,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _isBusy
                ? null
                : () async {
                    await _save();
                    if (!mounted) {
                      return;
                    }
                    _showSnackBar(l10n.translationSaved);
                  },
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
