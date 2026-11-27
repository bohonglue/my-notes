import 'package:flutter/material.dart';

import '../data/database.dart';

enum NotesLayout { grid, list }

class SettingsStore extends ChangeNotifier {
  SettingsStore(this.db);

  final NotesDatabase db;

  ThemeMode themeMode = ThemeMode.system;
  NotesLayout layout = NotesLayout.grid;

  Future<void> load() async {
    themeMode = ThemeMode.values.asNameMap()[await db.getSetting('theme')] ?? ThemeMode.system;
    layout = NotesLayout.values.asNameMap()[await db.getSetting('layout')] ?? NotesLayout.grid;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await db.setSetting('theme', m.name);
  }

  Future<void> setLayout(NotesLayout l) async {
    layout = l;
    notifyListeners();
    await db.setSetting('layout', l.name);
  }
}
