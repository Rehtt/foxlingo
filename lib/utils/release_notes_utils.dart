import 'package:flutter/widgets.dart';

String pickLocalizedReleaseNotes(String body, Locale locale) {
  final normalized = body.trim();
  if (normalized.isEmpty) {
    return '';
  }

  final englishSection = _extractSection(normalized, 'English');
  final chineseSection = _extractSection(normalized, '中文');

  final prefersChinese = locale.languageCode.toLowerCase().startsWith('zh');
  final selected = prefersChinese
      ? (chineseSection ?? englishSection ?? normalized)
      : (englishSection ?? chineseSection ?? normalized);
  return _stripVersionHeading(selected).trim();
}

String? _extractSection(String body, String heading) {
  final marker = '## $heading';
  final start = body.indexOf(marker);
  if (start == -1) {
    return null;
  }

  final sectionStart = start + marker.length;
  final remainder = body.substring(sectionStart);
  final nextHeading = remainder.indexOf('\n## ');
  final raw = nextHeading == -1
      ? remainder
      : remainder.substring(0, nextHeading);
  final normalized = raw.trim();
  return normalized.isEmpty ? null : normalized;
}

String _stripVersionHeading(String notes) {
  final lines = notes.split('\n');
  if (lines.isEmpty) {
    return notes;
  }
  final firstLine = lines.first.trim();
  final headingPattern = RegExp(
    r'^###\s+v\d+\.\d+\.\d+(-preview\.[1-9][0-9]*)?(\s+—\s+.+)?$',
  );
  if (!headingPattern.hasMatch(firstLine)) {
    return notes;
  }

  return lines.skip(1).join('\n').trimLeft();
}
