import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../client/github_release_client.dart';

enum UpdateStatus { available, latest, ignored, failed }

class UpdateResult {
  const UpdateResult(this.status, [this.release]);
  final UpdateStatus status;
  final GitHubRelease? release;
}

class AppUpdateService {
  AppUpdateService({
    GitHubReleaseClient? client,
    Future<String> Function()? versionProvider,
    FlutterSecureStorage? storage,
    Future<bool> Function(Uri)? openBrowser,
  }) : _client = client ?? GitHubReleaseClient(),
       _versionProvider =
           versionProvider ??
           (() async => (await PackageInfo.fromPlatform()).version),
       _storage = storage ?? const FlutterSecureStorage(),
       _openBrowser =
           openBrowser ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  final GitHubReleaseClient _client;
  final Future<String> Function() _versionProvider;
  final FlutterSecureStorage _storage;
  final Future<bool> Function(Uri) _openBrowser;
  static const ignoredKey = 'app.ignoredReleaseVersion';
  Future<GitHubRelease?>? _cached;
  Future<String?>? _version;

  Future<String?> get currentVersion => _version ??= _readVersion();
  Future<String?> _readVersion() async {
    try {
      final value = await _versionProvider();
      AppVersion.parse(value);
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<GitHubRelease?> _fetch() async {
    try {
      return await _client.fetchLatest();
    } catch (_) {
      return null;
    }
  }

  void prefetch() {
    _cached ??= _fetch();
  }

  Future<UpdateResult> check({required bool manual}) async {
    try {
      if (manual) _cached = null;
      final release = await (_cached ??= _fetch());
      final version = await currentVersion;
      if (release == null || version == null) {
        return const UpdateResult(UpdateStatus.failed);
      }
      if (release.version.compareTo(AppVersion.parse(version)) <= 0) {
        return const UpdateResult(UpdateStatus.latest);
      }
      if (!manual &&
          await _storage.read(key: ignoredKey) == release.version.toString()) {
        return const UpdateResult(UpdateStatus.ignored);
      }
      return UpdateResult(UpdateStatus.available, release);
    } catch (_) {
      return const UpdateResult(UpdateStatus.failed);
    }
  }

  Future<void> ignore(GitHubRelease release) =>
      _storage.write(key: ignoredKey, value: release.version.toString());
  Future<bool> download(GitHubRelease release) async {
    try {
      return await _openBrowser(release.pageUrl);
    } catch (_) {
      return false;
    }
  }

  void dispose() => _client.dispose();
}
