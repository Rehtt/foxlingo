// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '狐译';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get settings => '设置';

  @override
  String get displayMode => '显示模式';

  @override
  String get system => '跟随系统';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get showApiKey => '显示 API Key';

  @override
  String get hideApiKey => '隐藏 API Key';

  @override
  String get overlayPermission => '悬浮窗权限';

  @override
  String get overlayPermissionGranted => '已授权。可以在其他应用上方显示译文。';

  @override
  String get overlayPermissionDenied => '未授权。需要此权限才能把译文覆盖到屏幕上。';

  @override
  String get requestOverlayPermission => '授予悬浮窗权限';

  @override
  String get screenCapturePermission => '录屏权限';

  @override
  String get screenCaptureNotImplemented => '此设备无法使用截屏功能。';

  @override
  String get screenCapturePermissionPending => '本次会话尚未授予录屏权限';

  @override
  String get screenCapturePermissionCancelled => '已取消录屏权限';

  @override
  String get screenCapturePermissionDenied => '未授予录屏权限';

  @override
  String get startTranslation => '开始翻译';

  @override
  String get stopTranslation => '停止翻译';

  @override
  String get closeResult => '关闭';

  @override
  String get translationStarting => '正在启动翻译会话…';

  @override
  String get translationReady => '已就绪。切换到其他应用后点击悬浮球即可翻译';

  @override
  String get translationCapturing => '正在截取当前屏幕…';

  @override
  String get translationResultReady => '翻译结果已显示在悬浮层中';

  @override
  String get translationSessionError => '翻译会话需要处理错误';

  @override
  String get overlaySettingsHint => '开始前请先配置翻译服务和 OCR。';

  @override
  String get translationSettings => '翻译设置';

  @override
  String get translationProvider => '翻译方式';

  @override
  String get translationProviderLlm => 'LLM（OpenAI 兼容）';

  @override
  String get translationProviderGoogle => 'Google 翻译';

  @override
  String get translationProviderMicrosoft => '微软翻译';

  @override
  String get translationGoogleApiKey => 'Google Cloud API Key';

  @override
  String get translationMicrosoftApiKey => 'Azure 订阅密钥';

  @override
  String get translationMicrosoftRegion => 'Azure 区域';

  @override
  String get translationApiBaseUrl => 'API 地址';

  @override
  String get translationApiKey => 'API Key';

  @override
  String get translationModel => '模型';

  @override
  String get translationReasoningEffort => '思考等级';

  @override
  String get translationReasoningEffortHint =>
      '留空则不发送。填写后请求会带 reasoning_effort，不再发送 temperature。也可手动输入服务商支持的其他值。';

  @override
  String get translationSystemPrompt => 'System 提示词';

  @override
  String get translationTargetLanguage => '目标语言';

  @override
  String get translationTargetFollowApp => '跟随 App 语言';

  @override
  String get translationSettingsHint => '提示词中的 targetLanguage 会被替换为实际目标语言名称';

  @override
  String get ocrScript => 'OCR 识别文字';

  @override
  String get ocrScriptLatin => '拉丁文';

  @override
  String get ocrScriptChinese => '中文';

  @override
  String get ocrScriptJapanese => '日文';

  @override
  String get ocrScriptKorean => '韩文';

  @override
  String get imageTranslationRecognizing => 'OCR 识别中…';

  @override
  String imageTranslationTranslating(int count) {
    return '翻译中…（共 $count 段文字）';
  }

  @override
  String get imageTranslationPrivacyNote => '图片在设备端识别，识别出的文字会发送至当前选择的翻译服务。';

  @override
  String get imageTranslationNoText => '未在图片中识别到文字。';

  @override
  String get imageTranslationMethod => '图片翻译方式';

  @override
  String get imageTranslationMethodOcr => '设备端 OCR + 文本翻译';

  @override
  String get imageTranslationMethodLlm => '视觉 LLM（识别并翻译）';

  @override
  String get imageTranslationLlmApiBaseUrl => '图片翻译 API 地址';

  @override
  String get imageTranslationLlmApiKey => '图片翻译 API Key';

  @override
  String get imageTranslationLlmModel => '图片翻译模型';

  @override
  String get imageTranslationLlmFallbackHint => '留空时沿用文本翻译的 LLM 配置。';

  @override
  String get imageTranslationLlmInProgress => '正在使用视觉模型识别并翻译…';

  @override
  String get imageTranslationLlmPrivacyNote => '图片会上传至所配置的 LLM 接口进行识别和翻译。';

  @override
  String get imageTranslationLlmNotConfigured =>
      '请先在翻译设置中配置图片翻译 LLM 的 API Key。';

  @override
  String get imageTranslationLlmNoText => '模型未在图片中识别到可读文字。';

  @override
  String get translationInProgress => '翻译中…';

  @override
  String get translationSaved => '翻译设置已保存';

  @override
  String get translationTest => '测试';

  @override
  String get imageTranslationTest => '测试图片翻译';

  @override
  String get translationTestSuccess => '配置可用';

  @override
  String translationTestSuccessWithResult(String result) {
    return '配置可用。示例：$result';
  }

  @override
  String translationTestFailed(String error) {
    return '测试失败：$error';
  }

  @override
  String translationFailed(String error) {
    return '翻译失败：$error';
  }

  @override
  String get translationNoContent => '没有可翻译的内容';

  @override
  String get translationNotConfigured => '请先在设置中配置所选翻译方式';

  @override
  String get checkUpdate => '检查更新';

  @override
  String get currentVersion => '当前版本';

  @override
  String get updateAvailable => '发现新版本';

  @override
  String get updateLater => '稍后';

  @override
  String get updateDownload => '下载';

  @override
  String get updateLatest => '当前已是最新版本';

  @override
  String get updateFailed => '无法检查更新';

  @override
  String get updateOpenFailed => '无法打开发布页';

  @override
  String get updateApkHint => '请在发布页选择适合设备的签名 APK。';
}
