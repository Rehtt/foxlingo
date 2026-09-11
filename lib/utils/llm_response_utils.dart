class LlmResponseUtils {
  const LlmResponseUtils._();

  static final RegExp _completeThinkBlock = RegExp(
    r'<think\b[^>]*>[\s\S]*?</think>',
    caseSensitive: false,
  );
  static final RegExp _closingThink = RegExp(
    r'</think>',
    caseSensitive: false,
  );
  static final RegExp _openingThink = RegExp(
    r'<think\b[^>]*>',
    caseSensitive: false,
  );

  /// Removes reasoning that some gateways embed in `content`.
  ///
  /// Handles complete `<think>…</think>` blocks, a leftover closing tag
  /// (the opening tag was swallowed), and an unclosed opening tag.
  static String stripThinkTags(String text) {
    var result = text.replaceAll(_completeThinkBlock, '');

    final closingMatches = _closingThink.allMatches(result);
    if (closingMatches.isNotEmpty) {
      result = result.substring(closingMatches.last.end);
    }

    final openingMatch = _openingThink.firstMatch(result);
    if (openingMatch != null) {
      result = result.substring(0, openingMatch.start);
    }

    return result.trim();
  }

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
