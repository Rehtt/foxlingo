import 'package:flutter/material.dart';

import 'controllers/screen_translation_controller.dart';
import 'l10n/app_localizations.dart';
import 'pages/home_page.dart';
import 'platform/translation_bridge.dart';
import 'utils/app_settings.dart';
import 'utils/translation_settings.dart';
import 'widgets/translation_overlay_host.dart';
import 'widgets/app_update_host.dart';
import 'services/app_update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  final translationSettings = TranslationSettings();
  await settings.load();
  await translationSettings.load();
  runApp(
    FoxLingoApp(settings: settings, translationSettings: translationSettings),
  );
}

class FoxLingoApp extends StatefulWidget {
  const FoxLingoApp({
    super.key,
    required this.settings,
    required this.translationSettings,
    this.controller,
    this.updateService,
  });

  final AppUpdateService? updateService;
  final AppSettings settings;
  final TranslationSettings translationSettings;
  final ScreenTranslationController? controller;

  @override
  State<FoxLingoApp> createState() => _FoxLingoAppState();
}

class _FoxLingoAppState extends State<FoxLingoApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final _updates = widget.updateService ?? AppUpdateService();
  late final ScreenTranslationController _controller =
      widget.controller ??
      ScreenTranslationController(settings: widget.translationSettings);
  late final bool _ownsController = widget.controller == null;

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    if (widget.updateService == null) _updates.dispose();
    super.dispose();
  }

  static const Color _seedColor = Color(0xff2f6f73);

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      settings: widget.settings,
      child: TranslationSettingsScope(
        settings: widget.translationSettings,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            widget.settings,
            widget.translationSettings,
          ]),
          builder: (context, _) {
            return MaterialApp(
              title: 'FoxLingo',
              navigatorKey: _navigatorKey,
              builder: (context, child) => AppUpdateHost(
                service: _updates,
                navigatorKey: _navigatorKey,
                child: child!,
              ),
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: _seedColor,
                  brightness: Brightness.light,
                ),
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: _seedColor,
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
              ),
              themeMode: widget.settings.themeMode,
              locale: widget.settings.locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              localeResolutionCallback: (locale, supportedLocales) {
                if (locale == null) {
                  return const Locale('en');
                }
                for (final supported in supportedLocales) {
                  if (supported.languageCode == locale.languageCode) {
                    return supported;
                  }
                }
                return const Locale('en');
              },
              home: HomePage(controller: _controller),
            );
          },
        ),
      ),
    );
  }
}

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TranslationOverlayApp(bridge: TranslationBridge.overlay()));
}
