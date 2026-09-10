import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSettings extends ChangeNotifier {
  AppSettings({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _themeModeStorageKey = 'app.themeMode';
  static const String _localeStorageKey = 'app.locale';

  final FlutterSecureStorage _secureStorage;

  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;

  ThemeMode get themeMode => _themeMode;

  /// `null` means follow the system locale.
  Locale? get locale => _locale;

  String get localePreference {
    if (_locale == null) {
      return 'system';
    }
    return _locale!.languageCode;
  }

  Future<void> load() async {
    final savedTheme = await _secureStorage.read(key: _themeModeStorageKey);
    _themeMode = _deserializeThemeMode(savedTheme);

    final savedLocale = await _secureStorage.read(key: _localeStorageKey);
    _locale = _deserializeLocale(savedLocale);

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }

    _themeMode = mode;
    await _secureStorage.write(
      key: _themeModeStorageKey,
      value: _serializeThemeMode(mode),
    );
    notifyListeners();
  }

  Future<void> setLocalePreference(String preference) async {
    final nextLocale = switch (preference) {
      'en' => const Locale('en'),
      'zh' => const Locale('zh'),
      _ => null,
    };

    if (_locale == nextLocale ||
        (_locale != null &&
            nextLocale != null &&
            _locale!.languageCode == nextLocale.languageCode)) {
      return;
    }

    _locale = nextLocale;
    await _secureStorage.write(
      key: _localeStorageKey,
      value: _serializeLocale(nextLocale),
    );
    notifyListeners();
  }

  static ThemeMode _deserializeThemeMode(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      null || '' => ThemeMode.system,
      _ => ThemeMode.system,
    };
  }

  static String _serializeThemeMode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }

  static Locale? _deserializeLocale(String? value) {
    return switch (value) {
      'en' => const Locale('en'),
      'zh' => const Locale('zh'),
      'system' || null || '' => null,
      _ => null,
    };
  }

  static String _serializeLocale(Locale? locale) {
    if (locale == null) {
      return 'system';
    }
    return locale.languageCode;
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'AppSettingsScope not found in widget tree.');
    return scope!.notifier!;
  }
}
