import 'dart:convert';

import 'package:http/http.dart' as http;

class AppVersion implements Comparable<AppVersion> {
  AppVersion._(this.parts);
  final List<int> parts;

  factory AppVersion.parse(String value) {
    final match = RegExp(
      r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(value.trim());
    if (match == null) throw const FormatException('Invalid stable version');
    return AppVersion._([for (var i = 1; i <= 3; i++) int.parse(match[i]!)]);
  }

  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final result = parts[i].compareTo(other.parts[i]);
      if (result != 0) return result;
    }
    return 0;
  }

  @override
  String toString() => parts.join('.');
}

class GitHubRelease {
  GitHubRelease({
    required this.version,
    required this.pageUrl,
    required this.body,
  });
  final AppVersion version;
  final Uri pageUrl;
  final String body;

  factory GitHubRelease.fromJson(dynamic json) {
    if (json is! Map<String, dynamic> ||
        json['draft'] != false ||
        json['prerelease'] != false ||
        json['tag_name'] is! String ||
        json['html_url'] is! String ||
        (json['body'] != null && json['body'] is! String)) {
      throw const FormatException('Invalid stable release');
    }
    final url = Uri.parse(json['html_url'] as String);
    if (url.scheme != 'https' ||
        url.host != 'github.com' ||
        url.userInfo.isNotEmpty ||
        url.hasPort ||
        !url.path.startsWith('/Rehtt/foxlingo/releases/tag/') ||
        url.pathSegments.length != 5 ||
        url.pathSegments.last.isEmpty) {
      throw const FormatException('Invalid release URL');
    }
    return GitHubRelease(
      version: AppVersion.parse(json['tag_name'] as String),
      pageUrl: url,
      body: json['body'] as String? ?? '',
    );
  }
}

class GitHubReleaseClient {
  GitHubReleaseClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  Future<GitHubRelease> fetchLatest() async {
    final response = await _client
        .get(
          Uri.https('api.github.com', '/repos/Rehtt/foxlingo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw const FormatException('Release request failed');
    }
    return GitHubRelease.fromJson(jsonDecode(response.body));
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
