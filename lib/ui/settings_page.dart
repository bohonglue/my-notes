import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings_store.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          const ListTile(title: Text('外觀')),
          RadioGroup<ThemeMode>(
            groupValue: s.themeMode,
            onChanged: (m) => s.setThemeMode(m!),
            child: const Column(children: [
              RadioListTile(value: ThemeMode.system, title: Text('跟隨系統')),
              RadioListTile(value: ThemeMode.light, title: Text('淺色')),
              RadioListTile(value: ThemeMode.dark, title: Text('深色')),
            ]),
          ),
        ],
      ),
    );
  }
}
