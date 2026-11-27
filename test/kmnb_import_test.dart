import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_quill/flutter_quill.dart' show Document;
import 'package:flutter_test/flutter_test.dart';
import 'package:my_notes/data/database.dart';
import 'package:my_notes/data/html_to_delta.dart';
import 'package:my_notes/data/ink.dart';
import 'package:my_notes/data/kmnb_import.dart';
import 'package:my_notes/data/models.dart';
import 'package:my_notes/data/svg_ink.dart';
import 'package:my_notes/state/notes_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Keep My Notes 備份的資料表結構（只列匯入會用到的欄位）。
const _kmnbSchema = [
  "CREATE TABLE 'note' ('note_id' INTEGER PRIMARY KEY,'title' TEXT,'description' TEXT,'deleted' INTEGER NOT NULL,'created_date' INTEGER NOT NULL,'modified_date' INTEGER NOT NULL,'locked' INTEGER NOT NULL,'background_color' TEXT,'folder_id' INTEGER)",
  "CREATE TABLE 'image' ('image_id' INTEGER PRIMARY KEY,'note_id' INTEGER NOT NULL,'note_type' TEXT NOT NULL,'image_bytes' BLOB NOT NULL,'image_width' REAL NOT NULL,'image_height' REAL NOT NULL,'locked' INTEGER NOT NULL)",
  "CREATE TABLE 'folder' ('folder_id' INTEGER PRIMARY KEY,'parent_folder_id' INTEGER,'folder_name' TEXT NOT NULL,'created_date' INTEGER NOT NULL,'deleted' INTEGER NOT NULL,'background_color' TEXT,'last_update_date' INTEGER NOT NULL)",
  "CREATE TABLE 'checklist' ('checklist_id' INTEGER PRIMARY KEY,'title' TEXT,'deleted' INTEGER NOT NULL,'created_date' INTEGER NOT NULL,'modified_date' INTEGER NOT NULL,'locked' INTEGER NOT NULL,'background_color' TEXT,'folder_id' INTEGER)",
  "CREATE TABLE 'checklist_item' ('checklist_item_id' INTEGER PRIMARY KEY,'checklist_id' INTEGER NOT NULL,'item_text' TEXT NOT NULL,'checked' INTEGER NOT NULL,'order_of_item' INTEGER NOT NULL)",
  "CREATE TABLE 'handwriting' ('handwriting_id' INTEGER PRIMARY KEY,'title' TEXT NOT NULL,'handwriting_bytes' BLOB NOT NULL,'deleted' INTEGER NOT NULL,'created_date' INTEGER NOT NULL,'modified_date' INTEGER NOT NULL,'locked' INTEGER NOT NULL,'background_color' TEXT,'folder_id' INTEGER)",
];

const _svg = '''<?xml version="1.0"?>
<svg xmlns="http://www.w3.org/2000/svg" width="540.000000" height="900.000000">
	<rect width="100%" height="100%" fill="#FEFEFE"></rect>
	<path  stroke-linecap="round" d="M10.000000,20.000000
			Q10.000000,20.000000 15.000000,25.000000
			Q20.000000,30.000000 40.000000,30.000000
			" fill="none" stroke="#303030" stroke-width="5.000000px"/>
</svg>''';

void main() {
  setUpAll(sqfliteFfiInit);
  final factory = databaseFactoryFfiNoIsolate;

  group('htmlToDelta', () {
    test('段落、換行、格式、螢光與數字實體', () {
      final ops = htmlToDelta(
        '<p dir="ltr">&#25214;<b>粗</b><u>底</u><strike>刪</strike><br>\n'
        '<span style ="background-color: #f3ff00">亮</span></p>\n<p dir="ltr">二</p>',
      );
      expect(ops, [
        {'insert': '找'},
        {'insert': '粗', 'attributes': {'bold': true}},
        {'insert': '底', 'attributes': {'underline': true}},
        {'insert': '刪', 'attributes': {'strike': true}},
        {'insert': '\n'},
        {'insert': '亮', 'attributes': {'background': '#f3ff00'}},
        {'insert': '\n二\n'},
      ]);
      expect(deltaPlainText(ops), '找粗底刪\n亮\n二');
    });

    test('圖片轉成 attachment 來源，找不到的圖片略過', () {
      final ops = htmlToDelta('<p>a<img id="1"><img id="2"></p>',
          imageSource: (id) => id == '1' ? 'attachment:x' : null);
      expect(ops, [
        {'insert': 'a'},
        {'insert': {'image': 'attachment:x'}},
        {'insert': '\n'},
      ]);
    });
  });

  test('SVG 手寫轉成筆畫，並依寬度縮放到頁面座標', () {
    final page = svgToInk(_svg);
    expect(page.strokes.length, 1);
    final s = page.strokes.single;
    expect(s.color, 0xFF303030);
    expect(s.width, 10); // 540 寬 → 1080，放大 2 倍
    expect(s.points.first, const Offset(20, 40));
    expect(s.points.last, const Offset(80, 60));
  });

  test('kmnbColor 對應原 app 的顏色名稱', () {
    expect(kmnbColor('Mint Green'), 0xFFC5E1A5);
    expect(kmnbColor('Bean Red'), 0xFFEF9A9A);
    expect(kmnbColor('Milk White'), isNull);
    expect(kmnbColor(null), isNull);
  });

  group('importKmnb', () {
    late Directory dir;
    late String kmnbPath;
    late NotesDatabase db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kmnb');
      kmnbPath = '${dir.path}/test.kmnb';
      final src = await factory.openDatabase(kmnbPath);
      for (final s in _kmnbSchema) {
        await src.execute(s);
      }
      const t = 1700000000000;
      await src.insert('folder', {'folder_id': 1, 'folder_name': '工作', 'created_date': t, 'deleted': 0, 'last_update_date': t});
      await src.insert('folder', {'folder_id': 2, 'parent_folder_id': 1, 'folder_name': '專案', 'created_date': t, 'deleted': 0, 'last_update_date': t});
      await src.insert('folder', {'folder_id': 3, 'folder_name': '舊的', 'created_date': t, 'deleted': 1, 'last_update_date': t});
      await src.insert('note', {'note_id': -5, 'title': '有圖', 'description': '<p>看<img id="9"></p>', 'deleted': 0, 'created_date': t, 'modified_date': t + 1, 'locked': 0, 'background_color': 'Yellow', 'folder_id': 2});
      await src.insert('note', {'note_id': 6, 'title': '丟掉的', 'description': '<p>x</p>', 'deleted': 1, 'created_date': t, 'modified_date': t, 'locked': 0, 'folder_id': 3});
      await src.insert('note', {'note_id': 7, 'title': '鎖', 'description': 'MDEwO6lX2Gg', 'deleted': 0, 'created_date': t, 'modified_date': t, 'locked': 1});
      await src.insert('image', {'image_id': 9, 'note_id': -5, 'note_type': 'Note', 'image_bytes': Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]), 'image_width': 10.0, 'image_height': 10.0, 'locked': 0});
      await src.insert('checklist', {'checklist_id': 1, 'title': '買', 'deleted': 0, 'created_date': t, 'modified_date': t, 'locked': 0});
      await src.insert('checklist_item', {'checklist_id': 1, 'item_text': '二', 'checked': 1, 'order_of_item': 1});
      await src.insert('checklist_item', {'checklist_id': 1, 'item_text': '一', 'checked': 0, 'order_of_item': 0});
      await src.insert('handwriting', {'handwriting_id': 1, 'title': '', 'handwriting_bytes': Uint8List.fromList(utf8.encode(_svg)), 'deleted': 0, 'created_date': t, 'modified_date': t, 'locked': 0});
      await src.close();
      db = await NotesDatabase.open(factory, inMemoryDatabasePath);
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('匯入所有種類，資料夾、垃圾桶、圖片、上鎖都處理正確', () async {
      final r = await importKmnb(factory, kmnbPath, db);
      expect((r.notes, r.checklists, r.handwriting, r.folders, r.images, r.trashed, r.skippedLocked),
          (2, 1, 1, 2, 1, 1, 1));

      final store = NotesStore(db);
      await store.load();
      final img = store.noteById('kmnb-note--5')!;
      expect(img.color, 0xFFFFF59D);
      expect(store.folderById(img.folderId)!.name, '專案');
      expect(store.folderById(store.folderById(img.folderId)!.parentId)!.name, '工作');
      expect(img.content, contains('attachment:kmnb-img-9'));
      expect(img.plainText, '看');
      expect(await db.attachmentBytes('kmnb-img-9'), [0x89, 0x50, 0x4E, 0x47]);

      final trashed = store.noteById('kmnb-note-6')!;
      expect(trashed.isTrashed, isTrue);
      expect(trashed.folderId, isNull); // 原資料夾已刪除

      final cl = store.noteById('kmnb-checklist-1')!;
      expect(cl.checklistItems.map((e) => (e.text, e.checked)), [('一', false), ('二', true)]);

      final hw = store.noteById('kmnb-handwriting-1')!;
      expect(hw.type, NoteType.handwriting);
      expect(InkPage.decode(hw.content).strokes, hasLength(1));
    });

    test('重複匯入不會重複，也不會蓋掉匯入後修改過的筆記', () async {
      await importKmnb(factory, kmnbPath, db);
      final store = NotesStore(db);
      await store.load();
      final n = store.noteById('kmnb-checklist-1')!..title = '我改過';
      await store.save(n);

      final r = await importKmnb(factory, kmnbPath, db);
      expect(r.total, 0);
      expect(r.skippedUnchanged, 4);
      await store.load();
      expect(store.noteById('kmnb-checklist-1')!.title, '我改過');
      expect(store.countIn(const AllNotesView()), 3);
    });

    test('不是 Keep My Notes 備份就報錯', () async {
      final other = '${dir.path}/other.db';
      final o = await factory.openDatabase(other);
      await o.execute('CREATE TABLE x (a)');
      await o.close();
      expect(() => importKmnb(factory, other, db), throwsFormatException);
    });
  });

  group('備份與還原', () {
    test('匯出再還原到另一個資料庫：內容一樣，較新的版本保留，刪除也會同步', () async {
      final dir = await Directory.systemTemp.createTemp('backup');
      final a = await NotesDatabase.open(factory, inMemoryDatabasePath);
      final b = await NotesDatabase.open(factory, '${dir.path}/b.db');
      final storeA = NotesStore(a);
      final storeB = NotesStore(b);
      await storeA.load();
      await storeB.load();

      Note make(NotesStore s, String title) => s.newNote(NoteType.text)
        ..title = title
        ..plainText = title;

      final shared = make(storeA, '共同');
      await storeA.save(shared);
      final onlyA = make(storeA, 'A 才有');
      await storeA.save(onlyA);
      await a.putAttachment(id: 'img', noteId: onlyA.id, mime: 'image/png', bytes: [1, 2, 3]);

      // B 先有一份「共同」的較新版本
      final newer = Note.fromRow(shared.toRow())
        ..title = '共同（B 較新）'
        ..updatedAt = shared.updatedAt.add(const Duration(minutes: 1));
      await b.upsertNote(newer);

      final backupPath = '${dir.path}/backup.mynotes';
      await a.exportTo(backupPath);
      expect(await b.mergeFrom(factory, backupPath), 1);
      await storeB.load();
      expect(storeB.noteById(onlyA.id)!.title, 'A 才有');
      expect(storeB.noteById(shared.id)!.title, '共同（B 較新）');
      expect(await b.attachmentBytes('img'), [1, 2, 3]);

      // A 永久刪除後再備份，B 還原時也會刪掉
      await storeA.moveToTrash(onlyA);
      await storeA.emptyTrash();
      await File(backupPath).delete();
      await a.exportTo(backupPath);
      await b.mergeFrom(factory, backupPath);
      await storeB.load();
      expect(storeB.noteById(onlyA.id), isNull);

      await a.close();
      await b.close();
      await dir.delete(recursive: true);
    });
  });

  // 用真實的備份檔檢查（不會放進 repo）：KMNB_PATH=/path/to/file.kmnb flutter test
  final realPath = Platform.environment['KMNB_PATH'];
  test('真實備份檔', () async {
    final db = await NotesDatabase.open(factory, inMemoryDatabasePath);
    final r = await importKmnb(factory, realPath!, db);
    // ignore: avoid_print
    print('真實備份匯入結果：$r；上鎖略過 ${r.skippedLocked}');
    final store = NotesStore(db);
    await store.load();
    store.view = const AllNotesView();
    final all = [...store.visibleNotes, ...(() { store.view = const TrashView(); return store.visibleNotes; })()];
    for (final n in all.where((n) => n.type == NoteType.text)) {
      if (n.content.isEmpty) fail('空內容: ${n.id}');
      // 每則都要能被 Quill 讀取：最後一個 op 必須以換行結尾
      final ops = jsonDecode(n.content) as List;
      expect((ops.last as Map)['insert'], endsWith('\n'));
      // Quill 讀得進去
      Document.fromJson(ops);
    }
    await db.close();
  }, skip: realPath == null ? '沒有設定 KMNB_PATH' : false);
}
