import 'package:flutter/material.dart';

import '../data/database.dart';

enum NotesLayout { grid, list }

class SettingsStore extends ChangeNotifier {
  SettingsStore(this.db);

  final NotesDatabase db;

  ThemeMode themeMode = ThemeMode.system;
  NotesLayout layout = NotesLayout.grid;

  /// 開啟 app 時要不要解鎖。
  bool lockEnabled = false;

  /// App 在背景超過這個時間，回來時要重新解鎖。
  Duration lockAfter = const Duration(minutes: 1);

  static const lockAfterChoices = [
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 30),
  ];

  Future<void> load() async {
    themeMode = ThemeMode.values.asNameMap()[await db.getSetting('theme')] ?? ThemeMode.system;
    layout = NotesLayout.values.asNameMap()[await db.getSetting('layout')] ?? NotesLayout.grid;
    lockEnabled = await db.getSetting('lock') == '1';
    final secs = int.tryParse(await db.getSetting('lock_after') ?? '');
    if (secs != null) lockAfter = Duration(seconds: secs);
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

  Future<void> setLockEnabled(bool v) async {
    lockEnabled = v;
    notifyListeners();
    await db.setSetting('lock', v ? '1' : '0');
  }

  Future<void> setLockAfter(Duration d) async {
    lockAfter = d;
    notifyListeners();
    await db.setSetting('lock_after', '${d.inSeconds}');
  }
}
