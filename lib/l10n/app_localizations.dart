import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'FoxLingo'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @displayMode.
  ///
  /// In en, this message translates to:
  /// **'Display mode'**
  String get displayMode;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get languageChinese;

  /// No description provided for @showApiKey.
  ///
  /// In en, this message translates to:
  /// **'Show API key'**
  String get showApiKey;

  /// No description provided for @hideApiKey.
  ///
  /// In en, this message translates to:
  /// **'Hide API key'**
  String get hideApiKey;

  /// No description provided for @overlayPermission.
  ///
  /// In en, this message translates to:
  /// **'Overlay permission'**
  String get overlayPermission;

  /// No description provided for @overlayPermissionGranted.
  ///
  /// In en, this message translates to:
  /// **'Granted. The overlay can appear over other apps.'**
  String get overlayPermissionGranted;

  /// No description provided for @overlayPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Not granted. Android needs this to draw translations over the screen.'**
  String get overlayPermissionDenied;

  /// No description provided for @requestOverlayPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant overlay permission'**
  String get requestOverlayPermission;

  /// No description provided for @screenCapturePermission.
  ///
  /// In en, this message translates to:
  /// **'Screen capture permission'**
  String get screenCapturePermission;

  /// No description provided for @screenCaptureNotImplemented.
  ///
  /// In en, this message translates to:
  /// **'Screen capture is unavailable on this device.'**
  String get screenCaptureNotImplemented;

  /// No description provided for @screenCapturePermissionPending.
  ///
  /// In en, this message translates to:
  /// **'Screen capture permission has not been granted for this session.'**
  String get screenCapturePermissionPending;

  /// No description provided for @screenCapturePermissionCancelled.
  ///
  /// In en, this message translates to:
  /// **'Screen capture permission was cancelled.'**
  String get screenCapturePermissionCancelled;

  /// No description provided for @screenCapturePermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Screen capture permission was not granted.'**
  String get screenCapturePermissionDenied;

  /// No description provided for @startTranslation.
  ///
  /// In en, this message translates to:
  /// **'Start translation'**
  String get startTranslation;

  /// No description provided for @stopTranslation.
  ///
  /// In en, this message translates to:
  /// **'Stop translation'**
  String get stopTranslation;

  /// No description provided for @closeResult.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeResult;

  /// No description provided for @translationStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting translation session...'**
  String get translationStarting;

  /// No description provided for @translationReady.
  ///
  /// In en, this message translates to:
  /// **'Ready. Tap the floating button in another app to translate.'**
  String get translationReady;

  /// No description provided for @translationCapturing.
  ///
  /// In en, this message translates to:
  /// **'Capturing the current screen...'**
  String get translationCapturing;

  /// No description provided for @translationResultReady.
  ///
  /// In en, this message translates to:
  /// **'Translation result is shown in the overlay.'**
  String get translationResultReady;

  /// No description provided for @translationSessionError.
  ///
  /// In en, this message translates to:
  /// **'The translation session needs attention.'**
  String get translationSessionError;

  /// No description provided for @overlaySettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Configure translation providers and OCR before starting.'**
  String get overlaySettingsHint;

  /// No description provided for @translationSettings.
  ///
  /// In en, this message translates to:
  /// **'Translation settings'**
  String get translationSettings;

  /// No description provided for @translationProvider.
  ///
  /// In en, this message translates to:
  /// **'Translation provider'**
  String get translationProvider;

  /// No description provided for @translationProviderLlm.
  ///
  /// In en, this message translates to:
  /// **'LLM (OpenAI-compatible)'**
  String get translationProviderLlm;

  /// No description provided for @translationProviderGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google Translate'**
  String get translationProviderGoogle;

  /// No description provided for @translationProviderMicrosoft.
  ///
  /// In en, this message translates to:
  /// **'Microsoft Translator'**
  String get translationProviderMicrosoft;

  /// No description provided for @translationGoogleApiKey.
  ///
  /// In en, this message translates to:
  /// **'Google Cloud API key'**
  String get translationGoogleApiKey;

  /// No description provided for @translationMicrosoftApiKey.
  ///
  /// In en, this message translates to:
  /// **'Azure subscription key'**
  String get translationMicrosoftApiKey;

  /// No description provided for @translationMicrosoftRegion.
  ///
  /// In en, this message translates to:
  /// **'Azure region'**
  String get translationMicrosoftRegion;

  /// No description provided for @translationApiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'API base URL'**
  String get translationApiBaseUrl;

  /// No description provided for @translationApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get translationApiKey;

  /// No description provided for @translationModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get translationModel;

  /// No description provided for @translationSystemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System prompt'**
  String get translationSystemPrompt;

  /// No description provided for @translationTargetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Target language'**
  String get translationTargetLanguage;

  /// No description provided for @translationTargetFollowApp.
  ///
  /// In en, this message translates to:
  /// **'Follow app language'**
  String get translationTargetFollowApp;

  /// No description provided for @translationSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'The placeholder targetLanguage will be replaced with the resolved target language name.'**
  String get translationSettingsHint;

  /// No description provided for @ocrScript.
  ///
  /// In en, this message translates to:
  /// **'OCR script'**
  String get ocrScript;

  /// No description provided for @ocrScriptLatin.
  ///
  /// In en, this message translates to:
  /// **'Latin'**
  String get ocrScriptLatin;

  /// No description provided for @ocrScriptChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get ocrScriptChinese;

  /// No description provided for @ocrScriptJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get ocrScriptJapanese;

  /// No description provided for @ocrScriptKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get ocrScriptKorean;

  /// No description provided for @imageTranslationRecognizing.
  ///
  /// In en, this message translates to:
  /// **'Recognizing text (OCR)...'**
  String get imageTranslationRecognizing;

  /// No description provided for @imageTranslationTranslating.
  ///
  /// In en, this message translates to:
  /// **'Translating... ({count, plural, =1{1 text block} other{{count} text blocks}})'**
  String imageTranslationTranslating(int count);

  /// No description provided for @imageTranslationPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Image recognition runs on this device. Recognized text is sent to your selected translation provider.'**
  String get imageTranslationPrivacyNote;

  /// No description provided for @imageTranslationNoText.
  ///
  /// In en, this message translates to:
  /// **'No text was recognized in this image.'**
  String get imageTranslationNoText;

  /// No description provided for @imageTranslationMethod.
  ///
  /// In en, this message translates to:
  /// **'Image translation method'**
  String get imageTranslationMethod;

  /// No description provided for @imageTranslationMethodOcr.
  ///
  /// In en, this message translates to:
  /// **'On-device OCR + text translation'**
  String get imageTranslationMethodOcr;

  /// No description provided for @imageTranslationMethodLlm.
  ///
  /// In en, this message translates to:
  /// **'Vision LLM (recognize and translate)'**
  String get imageTranslationMethodLlm;

  /// No description provided for @imageTranslationLlmApiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Image translation API base URL'**
  String get imageTranslationLlmApiBaseUrl;

  /// No description provided for @imageTranslationLlmApiKey.
  ///
  /// In en, this message translates to:
  /// **'Image translation API key'**
  String get imageTranslationLlmApiKey;

  /// No description provided for @imageTranslationLlmModel.
  ///
  /// In en, this message translates to:
  /// **'Image translation model'**
  String get imageTranslationLlmModel;

  /// No description provided for @imageTranslationLlmFallbackHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to reuse the LLM settings of text translation.'**
  String get imageTranslationLlmFallbackHint;

  /// No description provided for @imageTranslationLlmInProgress.
  ///
  /// In en, this message translates to:
  /// **'Recognizing and translating with the vision model...'**
  String get imageTranslationLlmInProgress;

  /// No description provided for @imageTranslationLlmPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'The image is uploaded to the configured LLM API, which recognizes and translates the text.'**
  String get imageTranslationLlmPrivacyNote;

  /// No description provided for @imageTranslationLlmNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configure the image translation LLM API key in translation settings first.'**
  String get imageTranslationLlmNotConfigured;

  /// No description provided for @imageTranslationLlmNoText.
  ///
  /// In en, this message translates to:
  /// **'The model did not detect readable text in this image.'**
  String get imageTranslationLlmNoText;

  /// No description provided for @translationInProgress.
  ///
  /// In en, this message translates to:
  /// **'Translating...'**
  String get translationInProgress;

  /// No description provided for @translationSaved.
  ///
  /// In en, this message translates to:
  /// **'Translation settings saved.'**
  String get translationSaved;

  /// No description provided for @translationTest.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get translationTest;

  /// No description provided for @imageTranslationTest.
  ///
  /// In en, this message translates to:
  /// **'Test image translation'**
  String get imageTranslationTest;

  /// No description provided for @translationTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Configuration works.'**
  String get translationTestSuccess;

  /// No description provided for @translationTestSuccessWithResult.
  ///
  /// In en, this message translates to:
  /// **'Configuration works. Sample: {result}'**
  String translationTestSuccessWithResult(String result);

  /// No description provided for @translationTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Test failed: {error}'**
  String translationTestFailed(String error);

  /// No description provided for @translationFailed.
  ///
  /// In en, this message translates to:
  /// **'Translation failed: {error}'**
  String translationFailed(String error);

  /// No description provided for @translationNoContent.
  ///
  /// In en, this message translates to:
  /// **'No content to translate.'**
  String get translationNoContent;

  /// No description provided for @translationNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configure the selected translation provider in settings first.'**
  String get translationNotConfigured;

  /// No description provided for @checkUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkUpdate;

  /// No description provided for @currentVersion.
  ///
  /// In en, this message translates to:
  /// **'Current version'**
  String get currentVersion;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateAvailable;

  /// No description provided for @updateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// No description provided for @updateDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateDownload;

  /// No description provided for @updateLatest.
  ///
  /// In en, this message translates to:
  /// **'You are using the latest version'**
  String get updateLatest;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to check for updates'**
  String get updateFailed;

  /// No description provided for @updateOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open the release page'**
  String get updateOpenFailed;

  /// No description provided for @updateApkHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the signed APK for your device on the release page.'**
  String get updateApkHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
