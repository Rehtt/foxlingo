enum TranslationProvider { llm, google, microsoft }

/// How screen/image translation extracts and translates text.
enum ImageTranslationMethod {
  /// On-device ML Kit OCR, then the configured text translation provider.
  ocr,

  /// A vision-capable LLM extracts, translates, and locates text in one call.
  llm,
}
