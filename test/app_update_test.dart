import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foxlingo/client/github_release_client.dart';
import 'package:foxlingo/l10n/app_localizations.dart';
import 'package:foxlingo/services/app_update_service.dart';
import 'package:foxlingo/widgets/app_update_host.dart';
import 'package:foxlingo/utils/release_notes_utils.dart';

Map<String, dynamic> releaseJson() => {
  'tag_name': 'v1.2.0',
  'draft': false,
  'prerelease': false,
  'html_url': 'https://github.com/Rehtt/foxlingo/releases/tag/v1.2.0',
  'body': '## English\nEnglish notes\n## 中文\n中文说明',
};
http.Response response() => http.Response(
  jsonEncode(releaseJson()),
  200,
  headers: {'content-type': 'application/json'},
);
AppUpdateService service(
  http.Client client, {
  Future<bool> Function(Uri)? browser,
}) => AppUpdateService(
  client: GitHubReleaseClient(client: client),
  versionProvider: () async => '1.0.0+99',
  openBrowser: browser,
);

Widget harness(
  AppUpdateService service, {
  Locale locale = const Locale('en'),
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final key = navigatorKey ?? GlobalKey<NavigatorState>();
  return MaterialApp(
    navigatorKey: key,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) =>
        AppUpdateHost(service: service, navigatorKey: key, child: child!),
    home: const Scaffold(body: CheckUpdateTile()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('numeric stable comparison ignores build numbers', () {
    expect(
      AppVersion.parse('v1.10.0').compareTo(AppVersion.parse('1.9.99')),
      greaterThan(0),
    );
    expect(
      AppVersion.parse('1.0.0+99').compareTo(AppVersion.parse('1.0.0+1')),
      0,
    );
    expect(
      AppVersion.parse('1.99.99').compareTo(AppVersion.parse('2.0.0')),
      lessThan(0),
    );
    for (final version in ['1.0', '1.2.3-preview.1', '01.2.3', '', '1.2.3.4']) {
      expect(() => AppVersion.parse(version), throwsFormatException);
    }
  });

  test('rejects malformed releases and unsafe URLs', () {
    for (final override in [
      {'draft': true},
      {'prerelease': true},
      {'tag_name': 'bad'},
      {'html_url': 'https://evil.com/Rehtt/foxlingo/releases/tag/v1.2.0'},
      {'html_url': 'http://github.com/Rehtt/foxlingo/releases/tag/v1.2.0'},
      {'body': 3},
    ]) {
      expect(
        () => GitHubRelease.fromJson({...releaseJson(), ...override}),
        throwsFormatException,
      );
    }
    expect(() => GitHubRelease.fromJson([]), throwsFormatException);
  });

  test('HTTP errors, JSON errors, network errors and timeout fail', () async {
    for (final client in [
      MockClient((_) async => http.Response('', 403)),
      MockClient((_) async => http.Response('{', 200)),
      MockClient((_) async => throw http.ClientException('offline')),
    ]) {
      expect(
        (await service(client).check(manual: true)).status,
        UpdateStatus.failed,
      );
    }
    final client = GitHubReleaseClient(
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 1),
    );
    await expectLater(client.fetchLatest(), throwsA(isA<TimeoutException>()));
  });

  test('ignore persists, manual bypasses ignore and refreshes cache', () async {
    var requests = 0;
    final updates = service(
      MockClient((_) async {
        requests++;
        return response();
      }),
    );
    final first = await updates.check(manual: false);
    await updates.ignore(first.release!);
    expect((await updates.check(manual: false)).status, UpdateStatus.ignored);
    expect(requests, 1);
    expect((await updates.check(manual: true)).status, UpdateStatus.available);
    expect(requests, 2);
  });

  test('installed newer version and invalid installed version', () async {
    for (final version in ['2.0.0', 'invalid']) {
      final updates = AppUpdateService(
        client: GitHubReleaseClient(
          client: MockClient((_) async => response()),
        ),
        versionProvider: () async => version,
      );
      expect(
        (await updates.check(manual: true)).status,
        version == 'invalid' ? UpdateStatus.failed : UpdateStatus.latest,
      );
    }
  });

  test('notes select language and fall back to available or full body', () {
    expect(
      pickLocalizedReleaseNotes(releaseJson()['body'], const Locale('zh')),
      '中文说明',
    );
    expect(pickLocalizedReleaseNotes('## 中文\n内容', const Locale('en')), '内容');
    expect(
      pickLocalizedReleaseNotes('plain notes', const Locale('zh')),
      'plain notes',
    );
    expect(
      pickLocalizedReleaseNotes(
        '## English\n### v1.2.0\nChanges',
        const Locale('en'),
      ),
      'Changes',
    );
  });

  testWidgets('startup checks once across rebuilds and lifecycle resumes', (
    tester,
  ) async {
    var requests = 0;
    final updates = service(
      MockClient((_) async {
        requests++;
        return response();
      }),
    );
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(harness(updates, navigatorKey: key));
    await tester.pumpAndSettle();
    expect(find.text('English notes'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      harness(updates, locale: const Locale('zh'), navigatorKey: key),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'manual supersedes automatic check, disables tile and shows one dialog',
    (tester) async {
      final pending = <Completer<http.Response>>[];
      final updates = service(
        MockClient((_) {
          final c = Completer<http.Response>();
          pending.add(c);
          return c.future;
        }),
      );
      await tester.pumpWidget(harness(updates));
      await tester.pump();
      await tester.tap(find.text('Check for updates'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
      pending[1].complete(response());
      await tester.pump();
      pending[0].complete(response());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('late response after host disposal is harmless', (tester) async {
    final pending = Completer<http.Response>();
    await tester.pumpWidget(
      harness(service(MockClient((_) => pending.future))),
    );
    await tester.pumpWidget(const SizedBox());
    pending.complete(response());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('background response waits for foreground', (tester) async {
    final pending = Completer<http.Response>();
    await tester.pumpWidget(
      harness(service(MockClient((_) => pending.future))),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    pending.complete(response());
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Chinese long notes scroll and browser failure does not ignore', (
    tester,
  ) async {
    final updates = service(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            ...releaseJson(),
            'body': '## 中文\n${List.filled(100, '长更新说明').join('\n')}\n最后一行',
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      browser: (_) async => false,
    );
    await tester.pumpWidget(harness(updates, locale: const Locale('zh')));
    await tester.pumpAndSettle();
    expect(find.textContaining('长更新说明'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    expect(find.text('无法打开发布页'), findsOneWidget);
    expect((await updates.check(manual: false)).status, UpdateStatus.available);
  });

  testWidgets('dismissal does not ignore and manual failure has feedback', (
    tester,
  ) async {
    var fail = false;
    final updates = service(
      MockClient((_) async => fail ? http.Response('', 500) : response()),
    );
    await tester.pumpWidget(harness(updates));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect((await updates.check(manual: false)).status, UpdateStatus.available);
    fail = true;
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to check for updates'), findsOneWidget);
  });
  testWidgets('manual result after settings route is removed is discarded', (
    tester,
  ) async {
    var requests = 0;
    final pending = Completer<http.Response>();
    final updates = service(
      MockClient((_) async {
        requests++;
        return requests == 1 ? http.Response('', 500) : pending.future;
      }),
    );
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(harness(updates, navigatorKey: key));
    await tester.pumpAndSettle();
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: CheckUpdateTile()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for updates').last);
    await tester.pump();
    key.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    pending.complete(response());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual latest feedback and installed version subtitle', (
    tester,
  ) async {
    final updates = AppUpdateService(
      client: GitHubReleaseClient(client: MockClient((_) async => response())),
      versionProvider: () async => '1.2.0',
    );
    await tester.pumpWidget(harness(updates));
    await tester.pumpAndSettle();
    expect(find.text('Current version: 1.2.0'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('You are using the latest version'), findsOneWidget);
  });
}
