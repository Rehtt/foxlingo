class LlmResponseUtils {
  const LlmResponseUtils._();

  static String stripCodeFence(String text) {
    if (!text.startsWith('```')) {
      return text;
    }

    final lines = text.split('\n');
    if (lines.length < 2) {
      return text;
    }

    final withoutOpening = lines.sublist(1);
    if (withoutOpening.isEmpty) {
      return text;
    }

    if (withoutOpening.last.trim() == '```') {
      return withoutOpening
          .sublist(0, withoutOpening.length - 1)
          .join('\n')
          .trim();
    }

    return withoutOpening.join('\n').trim();
  }

  static String extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      throw StateError('Response did not include JSON.');
    }
    return text.substring(start, end + 1);
  }

  static String extractJsonArray(String text) {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start == -1 || end == -1 || end <= start) {
      throw StateError('Response did not include JSON.');
    }
    return text.substring(start, end + 1);
  }
}
