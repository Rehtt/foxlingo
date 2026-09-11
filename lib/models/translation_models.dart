enum TranslationProvider { llm, google, microsoft }

/// Preset values for OpenAI-compatible `reasoning_effort`.
/// The stored setting is a free string; these are only UI suggestions.
const List<String> llmReasoningEffortPresets = ['low', 'medium', 'high'];

/// How screen/image translation extracts and translates text.
enum ImageTranslationMethod {
  /// On-device ML Kit OCR, then the configured text translation provider.
  ocr,

  /// A vision-capable LLM extracts, translates, and locates text in one call.
  llm,
}
