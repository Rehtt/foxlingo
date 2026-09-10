// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'FoxLingo';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get settings => 'Settings';

  @override
  String get displayMode => 'Display mode';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => 'Chinese';

  @override
  String get showApiKey => 'Show API key';

  @override
  String get hideApiKey => 'Hide API key';

  @override
  String get overlayPermission => 'Overlay permission';

  @override
  String get overlayPermissionGranted =>
      'Granted. The overlay can appear over other apps.';

  @override
  String get overlayPermissionDenied =>
      'Not granted. Android needs this to draw translations over the screen.';

  @override
  String get requestOverlayPermission => 'Grant overlay permission';

  @override
  String get screenCapturePermission => 'Screen capture permission';

  @override
  String get screenCaptureNotImplemented =>
      'Screen capture is unavailable on this device.';

  @override
  String get screenCapturePermissionPending =>
      'Screen capture permission has not been granted for this session.';

  @override
  String get screenCapturePermissionCancelled =>
      'Screen capture permission was cancelled.';

  @override
  String get screenCapturePermissionDenied =>
      'Screen capture permission was not granted.';

  @override
  String get startTranslation => 'Start translation';

  @override
  String get stopTranslation => 'Stop translation';

  @override
  String get closeResult => 'Close';

  @override
  String get translationStarting => 'Starting translation session...';

  @override
  String get translationReady =>
      'Ready. Tap the floating button in another app to translate.';

  @override
  String get translationCapturing => 'Capturing the current screen...';

  @override
  String get translationResultReady =>
      'Translation result is shown in the overlay.';

  @override
  String get translationSessionError =>
      'The translation session needs attention.';

  @override
  String get overlaySettingsHint =>
      'Configure translation providers and OCR before starting.';

  @override
  String get translationSettings => 'Translation settings';

  @override
  String get translationProvider => 'Translation provider';

  @override
  String get translationProviderLlm => 'LLM (OpenAI-compatible)';

  @override
  String get translationProviderGoogle => 'Google Translate';

  @override
  String get translationProviderMicrosoft => 'Microsoft Translator';

  @override
  String get translationGoogleApiKey => 'Google Cloud API key';

  @override
  String get translationMicrosoftApiKey => 'Azure subscription key';

  @override
  String get translationMicrosoftRegion => 'Azure region';

  @override
  String get translationApiBaseUrl => 'API base URL';

  @override
  String get translationApiKey => 'API key';

  @override
  String get translationModel => 'Model';

  @override
  String get translationSystemPrompt => 'System prompt';

  @override
  String get translationTargetLanguage => 'Target language';

  @override
  String get translationTargetFollowApp => 'Follow app language';

  @override
  String get translationSettingsHint =>
      'The placeholder targetLanguage will be replaced with the resolved target language name.';

  @override
  String get ocrScript => 'OCR script';

  @override
  String get ocrScriptLatin => 'Latin';

  @override
  String get ocrScriptChinese => 'Chinese';

  @override
  String get ocrScriptJapanese => 'Japanese';

  @override
  String get ocrScriptKorean => 'Korean';

  @override
  String get imageTranslationRecognizing => 'Recognizing text (OCR)...';

  @override
  String imageTranslationTranslating(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count text blocks',
      one: '1 text block',
    );
    return 'Translating... ($_temp0)';
  }

  @override
  String get imageTranslationPrivacyNote =>
      'Image recognition runs on this device. Recognized text is sent to your selected translation provider.';

  @override
  String get imageTranslationNoText => 'No text was recognized in this image.';

  @override
  String get imageTranslationMethod => 'Image translation method';

  @override
  String get imageTranslationMethodOcr => 'On-device OCR + text translation';

  @override
  String get imageTranslationMethodLlm =>
      'Vision LLM (recognize and translate)';

  @override
  String get imageTranslationLlmApiBaseUrl => 'Image translation API base URL';

  @override
  String get imageTranslationLlmApiKey => 'Image translation API key';

  @override
  String get imageTranslationLlmModel => 'Image translation model';

  @override
  String get imageTranslationLlmFallbackHint =>
      'Leave blank to reuse the LLM settings of text translation.';

  @override
  String get imageTranslationLlmInProgress =>
      'Recognizing and translating with the vision model...';

  @override
  String get imageTranslationLlmPrivacyNote =>
      'The image is uploaded to the configured LLM API, which recognizes and translates the text.';

  @override
  String get imageTranslationLlmNotConfigured =>
      'Configure the image translation LLM API key in translation settings first.';

  @override
  String get imageTranslationLlmNoText =>
      'The model did not detect readable text in this image.';

  @override
  String get translationInProgress => 'Translating...';

  @override
  String get translationSaved => 'Translation settings saved.';

  @override
  String get translationTest => 'Test';

  @override
  String get imageTranslationTest => 'Test image translation';

  @override
  String get translationTestSuccess => 'Configuration works.';

  @override
  String translationTestSuccessWithResult(String result) {
    return 'Configuration works. Sample: $result';
  }

  @override
  String translationTestFailed(String error) {
    return 'Test failed: $error';
  }

  @override
  String translationFailed(String error) {
    return 'Translation failed: $error';
  }

  @override
  String get translationNoContent => 'No content to translate.';

  @override
  String get translationNotConfigured =>
      'Configure the selected translation provider in settings first.';

  @override
  String get checkUpdate => 'Check for updates';

  @override
  String get currentVersion => 'Current version';

  @override
  String get updateAvailable => 'Update available';

  @override
  String get updateLater => 'Later';

  @override
  String get updateDownload => 'Download';

  @override
  String get updateLatest => 'You are using the latest version';

  @override
  String get updateFailed => 'Unable to check for updates';

  @override
  String get updateOpenFailed => 'Unable to open the release page';

  @override
  String get updateApkHint =>
      'Choose the signed APK for your device on the release page.';
}
