import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_settings.dart';
import '../utils/translation_settings.dart';
import 'translation_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appSettings = AppSettingsScope.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(appSettings.localePreference),
            initialValue: appSettings.localePreference,
            decoration: InputDecoration(
              labelText: l10n.language,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: 'system',
                child: Text(l10n.languageSystem),
              ),
              DropdownMenuItem(
                value: 'en',
                child: Text(l10n.languageEnglish),
              ),
              DropdownMenuItem(
                value: 'zh',
                child: Text(l10n.languageChinese),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                appSettings.setLocalePreference(value);
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ThemeMode>(
            key: ValueKey(appSettings.themeMode),
            initialValue: appSettings.themeMode,
            decoration: InputDecoration(
              labelText: l10n.displayMode,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: ThemeMode.system,
                child: Text(l10n.system),
              ),
              DropdownMenuItem(
                value: ThemeMode.light,
                child: Text(l10n.light),
              ),
              DropdownMenuItem(
                value: ThemeMode.dark,
                child: Text(l10n.dark),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                appSettings.setThemeMode(value);
              }
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.translate),
            title: Text(l10n.translationSettings),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => TranslationSettingsPage(
                    settings: TranslationSettingsScope.of(context),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
