import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/database.dart';
import 'state/notes_store.dart';
import 'state/settings_store.dart';
import 'sync/sync_service.dart';
import 'update/update_service.dart';
import 'ui/app_lock.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android 用內建的 sqflite；Windows 用 FFI 版本。
  final DatabaseFactory factory;
  if (Platform.isAndroid || Platform.isIOS) {
    factory = sqflite.databaseFactory;
  } else {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
  }
  final dir = await getApplicationSupportDirectory();
  final db = await NotesDatabase.open(factory, p.join(dir.path, 'notes.db'));

  final notes = NotesStore(db);
  final settings = SettingsStore(db);
  await Future.wait([notes.load(), settings.load()]);
  final sync = SyncService(notes);
  // 不等網路，先把畫面開起來；同步在背景進行。
  unawaited(sync.init());
  final updates = UpdateService();
  unawaited(updates.loadCurrent());

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: notes),
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: sync),
      ChangeNotifierProvider.value(value: updates),
    ],
    child: const NotesApp(),
  ));
}

class NotesApp extends StatefulWidget {
  const NotesApp({super.key});

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => context.read<SyncService>().onResumed(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<SettingsStore, ThemeMode>((s) => s.themeMode);
    const seed = Color(0xFF3B7A57);
    return MaterialApp(
      title: '我的筆記',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      builder: (context, child) => AppLock(child: child!),
      home: const HomePage(),
    );
  }
}
