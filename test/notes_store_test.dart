import 'package:flutter_test/flutter_test.dart';
import 'package:my_notes/data/database.dart';
import 'package:my_notes/data/models.dart';
import 'package:my_notes/state/notes_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late NotesDatabase db;
  late NotesStore store;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await NotesDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    store = NotesStore(db);
    await store.load();
  });

  tearDown(() => db.close());

  Future<Note> addText(String title, String body) async {
    final n = store.newNote(NoteType.text)
      ..title = title
      ..plainText = body
      ..content = '[{"insert":"$body\\n"}]';
    await store.save(n);
    return n;
  }

  test('空白的新筆記不會存', () async {
    await store.save(store.newNote(NoteType.text));
    expect(store.visibleNotes, isEmpty);
  });

  test('儲存後重新載入還在，置頂排在最前面', () async {
    final a = await addText('A', 'aaa');
    await addText('B', 'bbb');
    await store.togglePin(a);
    final reloaded = NotesStore(db);
    await reloaded.load();
    expect(reloaded.visibleNotes.map((n) => n.title), ['A', 'B']);
    expect(reloaded.visibleNotes.first.pinned, isTrue);
  });

  test('封存、垃圾桶與還原', () async {
    final a = await addText('A', 'x');
    final b = await addText('B', 'y');
    await store.setArchived(a, true);
    await store.moveToTrash(b);
    expect(store.visibleNotes, isEmpty);
    store.view = const ArchiveView();
    expect(store.visibleNotes.single.id, a.id);
    store.view = const TrashView();
    expect(store.visibleNotes.single.id, b.id);
    await store.restore(b);
    store.view = const AllNotesView();
    expect(store.visibleNotes.single.id, b.id);
  });

  test('永久刪除會留下同步用的 tombstone', () async {
    final a = await addText('A', 'x');
    await store.moveToTrash(a);
    await store.emptyTrash();
    store.view = const TrashView();
    expect(store.visibleNotes, isEmpty);
    expect(await db.tombstoneCount(), 1);
  });

  test('搜尋標題與內容，包含封存但不含垃圾桶', () async {
    await addText('購物', '牛奶 雞蛋');
    final b = await addText('工作', '開會紀錄 牛奶');
    final c = await addText('其他', '牛奶');
    await store.setArchived(b, true);
    await store.moveToTrash(c);
    store.query = '牛奶';
    expect(store.visibleNotes.map((n) => n.title).toSet(), {'購物', '工作'});
  });

  test('資料夾檢視包含子資料夾，刪除資料夾後筆記移到未分類', () async {
    final parent = await store.createFolder('工作');
    final child = await store.createFolder('專案', parentId: parent.id);
    final n = await addText('A', 'x');
    n.folderId = child.id;
    await store.save(n);
    store.view = FolderView(parent.id);
    expect(store.visibleNotes.single.id, n.id);
    await store.deleteFolder(child);
    expect(store.noteById(n.id)!.folderId, isNull);
    expect(store.view, isA<FolderView>());
  });

  test('待辦清單項目存取', () async {
    final n = store.newNote(NoteType.checklist)
      ..checklistItems = [ChecklistItem(text: '買菜'), ChecklistItem(text: '繳費', checked: true)];
    await store.save(n);
    final reloaded = NotesStore(db);
    await reloaded.load();
    final items = reloaded.noteById(n.id)!.checklistItems;
    expect(items.map((e) => (e.text, e.checked)), [('買菜', false), ('繳費', true)]);
  });
}
