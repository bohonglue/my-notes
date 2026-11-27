import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_notes/data/database.dart';
import 'package:my_notes/main.dart';
import 'package:my_notes/state/notes_store.dart';
import 'package:my_notes/state/settings_store.dart';
import 'package:my_notes/sync/sync_service.dart';
import 'package:my_notes/update/update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('新增待辦清單與文字筆記，回到首頁會看到', (tester) async {
    late NotesDatabase db;
    late NotesStore notes;
    late SettingsStore settings;
    await tester.runAsync(() async {
      db = await NotesDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
      notes = NotesStore(db);
      settings = SettingsStore(db);
      await notes.load();
      await settings.load();
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: notes),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => SyncService(notes)..init()),
        ChangeNotifierProvider(
          create: (_) => UpdateService(client: MockClient((_) async => http.Response('', 404)))
            ..currentBuild = 1
            ..currentVersion = '1.0.1',
        ),
      ],
      child: const NotesApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('這裡還沒有筆記'), findsOneWidget);

    // 待辦清單
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待辦清單'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '週末');
    await tester.enterText(find.byType(TextField).at(1), '買牛奶');
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('週末'), findsOneWidget);
    expect(find.text('買牛奶'), findsOneWidget);

    // 文字筆記
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文字筆記'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '想法');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('想法'), findsOneWidget);

    // 設定頁與深色模式
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);

    await tester.runAsync(db.close);
  });
}
