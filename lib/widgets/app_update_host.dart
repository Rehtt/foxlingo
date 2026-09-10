import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_update_service.dart';
import '../utils/release_notes_utils.dart';

class AppUpdateHost extends StatefulWidget {
  const AppUpdateHost({
    super.key,
    required this.service,
    required this.navigatorKey,
    required this.child,
  });
  final AppUpdateService service;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  static AppUpdateHostState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_UpdateScope>()?.notifier;

  @override
  State<AppUpdateHost> createState() => AppUpdateHostState();
}

class AppUpdateHostState extends State<AppUpdateHost>
    with WidgetsBindingObserver {
  final ValueNotifier<bool> busy = ValueNotifier(false);
  String? version;
  int _generation = 0;
  bool _dialogOpen = false;
  Completer<void>? _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.service.prefetch();
    unawaited(_loadVersion());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_check());
    });
  }

  Future<void> _loadVersion() async {
    final value = await widget.service.currentVersion;
    if (mounted) setState(() => version = value);
  }

  bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground?.complete();
      _foreground = null;
    }
  }

  Future<void> checkManually(BuildContext context) => _check(origin: context);

  Future<void> _check({BuildContext? origin}) async {
    final manual = origin != null;
    if (manual && (busy.value || _dialogOpen)) return;
    final generation = ++_generation;
    if (manual) busy.value = true;
    var ownsDialog = false;
    try {
      final result = await widget.service.check(manual: manual);
      if (!mounted ||
          generation != _generation ||
          (origin != null && !origin.mounted)) {
        return;
      }
      if (!_isForeground) {
        await (_foreground ??= Completer<void>()).future;
      }
      if (!mounted ||
          generation != _generation ||
          (origin != null && !origin.mounted)) {
        return;
      }
      final context = widget.navigatorKey.currentState?.overlay?.context;
      if (context == null || !context.mounted) return;
      final l10n = AppLocalizations.of(context);
      if (result.status != UpdateStatus.available) {
        if (manual) {
          _message(
            context,
            result.status == UpdateStatus.latest
                ? l10n.updateLatest
                : l10n.updateFailed,
          );
        }
        return;
      }
      if (_dialogOpen) return;
      _dialogOpen = true;
      ownsDialog = true;
      final release = result.release!;
      final action = await showDialog<String>(
        context: context,
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          final notes = pickLocalizedReleaseNotes(
            release.body,
            Localizations.localeOf(context),
          );
          return AlertDialog(
            title: Text('${l10n.updateAvailable} ${release.version}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.updateApkHint),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(notes),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'later'),
                child: Text(l10n.updateLater),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'download'),
                child: Text(l10n.updateDownload),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      if (action == 'later') {
        try {
          await widget.service.ignore(release);
        } catch (_) {
          if (context.mounted) _message(context, l10n.updateFailed);
        }
      } else if (action == 'download') {
        final opened = await widget.service.download(release);
        if (mounted && context.mounted && !opened) {
          _message(context, l10n.updateOpenFailed);
        }
      }
    } finally {
      if (ownsDialog) _dialogOpen = false;
      if (mounted && manual) busy.value = false;
    }
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foreground?.complete();
    busy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _UpdateScope(notifier: this, version: version, child: widget.child);
}

class _UpdateScope extends InheritedWidget {
  const _UpdateScope({
    required this.notifier,
    required this.version,
    required super.child,
  });
  final AppUpdateHostState notifier;
  final String? version;
  @override
  bool updateShouldNotify(_UpdateScope oldWidget) =>
      version != oldWidget.version;
}

class CheckUpdateTile extends StatelessWidget {
  const CheckUpdateTile({super.key});
  @override
  Widget build(BuildContext context) {
    final host = AppUpdateHost.of(context);
    if (host == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: host.busy,
      builder: (context, busy, _) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.system_update),
        title: Text(l10n.checkUpdate),
        subtitle: Text('${l10n.currentVersion}: ${host.version ?? "—"}'),
        trailing: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(),
              )
            : const Icon(Icons.chevron_right),
        onTap: busy ? null : () => host.checkManually(context),
      ),
    );
  }
}
