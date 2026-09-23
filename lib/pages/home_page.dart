import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/screen_translation_controller.dart';
import '../l10n/app_localizations.dart';
import '../platform/overlay_controller.dart';
import '../platform/screen_capture_channel.dart';
import '../utils/translation_settings.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.controller,
    this.overlayController,
    this.screenCapture,
  });

  final ScreenTranslationController? controller;
  final OverlayController? overlayController;
  final ScreenCaptureGateway? screenCapture;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  ScreenTranslationController? _ownedController;
  bool _listening = false;
  bool? _overlayGranted;

  ScreenTranslationController get _controller =>
      widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller == null && _ownedController == null) {
      _ownedController = ScreenTranslationController(
        settings: TranslationSettingsScope.of(context),
        screenCapture: widget.screenCapture,
        overlay: widget.overlayController,
        appLocale: () => Localizations.localeOf(context),
      );
    }
    if (!_listening) {
      _controller.addListener(_onControllerChanged);
      _listening = true;
    }
    unawaited(_refreshPermissionsAndSession());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_listening) {
      _controller.removeListener(_onControllerChanged);
    }
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermissionsAndSession());
    }
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshPermissionsAndSession() async {
    try {
      final granted = await _controller.isOverlayPermissionGranted();
      if (mounted) {
        setState(() => _overlayGranted = granted);
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => _overlayGranted = false);
      }
    } on PlatformException {
      if (mounted) {
        setState(() => _overlayGranted = false);
      }
    }
    await _controller.refresh();
  }

  Future<void> _requestOverlayPermission() async {
    try {
      final granted = await _controller.requestOverlayPermission();
      if (mounted) {
        setState(() => _overlayGranted = granted);
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => _overlayGranted = false);
      }
    } on PlatformException {
      if (mounted) {
        setState(() => _overlayGranted = false);
      }
    }
  }

  Future<void> _startTranslation() async {
    final l10n = AppLocalizations.of(context);
    try {
      await _controller.start(
        appLocale: Localizations.localeOf(context),
        deviceLocale: WidgetsBinding.instance.platformDispatcher.locale,
      );
      if (mounted) {
        setState(() => _overlayGranted = true);
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      final message = switch (error) {
        TranslationControllerException(:final code)
            when code == 'translation_not_configured' =>
          l10n.translationNotConfigured,
        TranslationControllerException(:final code)
            when code == 'overlay_permission_denied' =>
          l10n.overlayPermissionDenied,
        TranslationControllerException(:final code)
            when code == 'screen_capture_cancelled' =>
          l10n.screenCapturePermissionCancelled,
        TranslationControllerException(:final code)
            when code == 'screen_capture_denied' =>
          l10n.screenCapturePermissionDenied,
        TranslationControllerException(:final message) => message,
        _ => error.toString(),
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _stopTranslation() async {
    await _controller.stop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    final overlayGranted = _overlayGranted ?? false;
    final state = controller.state;
    final active = controller.isSessionActive;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            tooltip: l10n.settings,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const SettingsPage(),
                ),
              );
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.overlaySettingsHint,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(
                overlayGranted ? Icons.check_circle : Icons.error_outline,
              ),
              title: Text(l10n.overlayPermission),
              subtitle: Text(
                overlayGranted
                    ? l10n.overlayPermissionGranted
                    : l10n.overlayPermissionDenied,
              ),
              trailing: overlayGranted
                  ? null
                  : TextButton(
                      onPressed: _requestOverlayPermission,
                      child: Text(l10n.requestOverlayPermission),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(
                active ? Icons.check_circle : Icons.screenshot_monitor,
              ),
              title: Text(l10n.screenCapturePermission),
              subtitle: Text(_statusText(l10n, state)),
            ),
          ),
          if (controller.errorMessage case final error?) ...[
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                title: Text(error),
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (active)
            FilledButton.icon(
              onPressed: state == ScreenTranslationState.starting
                  ? null
                  : _stopTranslation,
              icon: const Icon(Icons.stop),
              label: Text(l10n.stopTranslation),
            )
          else
            FilledButton.icon(
              onPressed: _startTranslation,
              icon: const Icon(Icons.translate),
              label: Text(l10n.startTranslation),
            ),
        ],
      ),
    );
  }

  String _statusText(AppLocalizations l10n, ScreenTranslationState state) {
    return switch (state) {
      ScreenTranslationState.stopped => l10n.screenCapturePermissionPending,
      ScreenTranslationState.starting => l10n.translationStarting,
      ScreenTranslationState.ready => l10n.translationReady,
      ScreenTranslationState.capturing => l10n.translationCapturing,
      ScreenTranslationState.selecting => l10n.translationSelectingRegion,
      ScreenTranslationState.translating => l10n.translationInProgress,
      ScreenTranslationState.result => l10n.translationResultReady,
      ScreenTranslationState.error => l10n.translationSessionError,
    };
  }
}
