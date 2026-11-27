import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_notes/data/database.dart';
import 'package:my_notes/data/ink.dart';
import 'package:my_notes/data/models.dart';
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

  group('InkPage', () {
    test('存成 JSON 再讀回來內容一樣', () {
      final page = InkPage(strokes: [
        InkStroke(color: 0xFF202020, width: 6, points: [const Offset(1.24, 2), const Offset(30, 40.05)]),
        InkStroke(color: 0xFFFFEB3B, width: 32, highlighter: true, points: [const Offset(5, 5)]),
      ]);
      final back = InkPage.decode(page.encode());
      expect(back.strokes.length, 2);
      expect(back.strokes[0].points, [const Offset(1.2, 2), const Offset(30, 40.1)]);
      expect(back.strokes[1].highlighter, isTrue);
      expect(back.strokes[1].width, 32);
    });

    test('橡皮擦只擦到碰到的筆畫', () {
      final s = InkStroke(color: 0, width: 4, points: [const Offset(0, 0), const Offset(100, 0)]);
      expect(s.hitTest(const Offset(50, 5), 4), isTrue);
      expect(s.hitTest(const Offset(50, 30), 4), isFalse);
      expect(s.hitTest(const Offset(130, 0), 4), isFalse);
    });

    test('往下寫時頁面會自動變長', () {
      final page = InkPage(strokes: [
        InkStroke(color: 0, width: 4, points: [const Offset(0, 1500)]),
      ]);
      page.growToFit();
      expect(page.height, greaterThan(2000));
    });
  });

  testWidgets('用觸控筆寫字、橡皮擦、復原，回首頁後筆記有存', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手寫筆記'));
    await tester.pumpAndSettle();

    Future<void> drawLine(Offset from, Offset to, PointerDeviceKind kind) async {
      final g = await tester.startGesture(from, kind: kind);
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 10)!);
      }
      await g.up();
      await tester.pump();
    }

    // 兩筆觸控筆筆畫
    await drawLine(const Offset(100, 400), const Offset(500, 400), PointerDeviceKind.stylus);
    await drawLine(const Offset(100, 600), const Offset(500, 600), PointerDeviceKind.stylus);
    // 用過觸控筆後，手指只捲動，不會畫
    await drawLine(const Offset(100, 800), const Offset(500, 800), PointerDeviceKind.touch);

    // 橡皮擦擦掉第一筆
    await tester.tap(find.byTooltip('橡皮擦（整筆擦掉）'));
    await tester.pump();
    await drawLine(const Offset(300, 380), const Offset(300, 420), PointerDeviceKind.stylus);

    // 復原橡皮擦 → 兩筆都回來；再擦一次
    await tester.tap(find.byTooltip('復原'));
    await tester.pump();
    await drawLine(const Offset(300, 380), const Offset(300, 420), PointerDeviceKind.stylus);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    final saved = notes.visibleNotes.single;
    expect(saved.type, NoteType.handwriting);
    final page = InkPage.decode(saved.content);
    expect(page.strokes.length, 1);
    // 螢幕 1080 寬時頁面顯示 900 寬、置中（左邊留 90），頁面座標 = (x - 90) / (900 / 1080)。
    final stroke = page.strokes.single;
    expect(stroke.points.first.dx, closeTo((100 - 90) * 1080 / 900, 1));
    expect(stroke.points.last.dx, closeTo((500 - 90) * 1080 / 900, 1));
    // 留下的是比較下面（螢幕 y=600）的那一筆：它和被擦掉那筆差 200 螢幕像素 = 240 頁面單位。
    expect(stroke.points.first.dy, greaterThan(240));

    await tester.runAsync(db.close);
  });
}
