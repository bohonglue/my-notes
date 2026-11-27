import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models.dart';

/// 本機 SQLite 資料庫。
///
/// 每一筆資料都有 updated_at，刪除會留下 tombstone（tombstones 表），
/// 之後 Google Drive 同步會靠這兩樣東西合併兩台裝置的變更。
class NotesDatabase {
  NotesDatabase._(this._db, this.factory);

  final Database _db;

  /// 開啟這個資料庫用的 factory；開備份檔時也用同一個。
  final DatabaseFactory factory;

  static const _version = 1;

  static Future<NotesDatabase> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE notes (
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              title TEXT NOT NULL DEFAULT '',
              content TEXT NOT NULL DEFAULT '',
              plain_text TEXT NOT NULL DEFAULT '',
              color INTEGER,
              folder_id TEXT,
              pinned INTEGER NOT NULL DEFAULT 0,
              archived INTEGER NOT NULL DEFAULT 0,
              trashed_at INTEGER,
              reminder_at INTEGER,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )''');
          await db.execute('''
            CREATE TABLE folders (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              parent_id TEXT,
              color INTEGER,
              updated_at INTEGER NOT NULL
            )''');
          await db.execute('''
            CREATE TABLE attachments (
              id TEXT PRIMARY KEY,
              note_id TEXT NOT NULL,
              mime TEXT NOT NULL,
              bytes BLOB NOT NULL,
              width REAL,
              height REAL,
              updated_at INTEGER NOT NULL
            )''');
          await db.execute('''
            CREATE TABLE tombstones (
              table_name TEXT NOT NULL,
              row_id TEXT NOT NULL,
              deleted_at INTEGER NOT NULL,
              PRIMARY KEY (table_name, row_id)
            )''');
          await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
          await db.execute('CREATE INDEX notes_folder ON notes(folder_id)');
        },
      ),
    );
    return NotesDatabase._(db, factory);
  }

  Future<void> close() => _db.close();

  // ---- notes ----

  Future<List<Note>> allNotes() async {
    final rows = await _db.query('notes', orderBy: 'updated_at DESC');
    return rows.map(Note.fromRow).toList();
  }

  Future<void> upsertNote(Note n) =>
      _db.insert('notes', n.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  /// 只有比現有版本新（或還不存在）才寫入。回傳是否有寫入。
  Future<bool> upsertNoteIfNewer(Note n) async {
    final rows = await _db.query('notes', columns: ['updated_at'], where: 'id = ?', whereArgs: [n.id]);
    if (rows.isNotEmpty && (rows.first['updated_at'] as int) >= n.updatedAt.millisecondsSinceEpoch) {
      return false;
    }
    if (await _isTombstoned('notes', n.id, n.updatedAt)) return false;
    await upsertNote(n);
    return true;
  }

  /// 永久刪除（從垃圾桶清掉）。
  Future<void> deleteNote(String id) async {
    await _db.transaction((txn) async {
      await txn.delete('notes', where: 'id = ?', whereArgs: [id]);
      await txn.delete('attachments', where: 'note_id = ?', whereArgs: [id]);
      await _tombstone(txn, 'notes', id);
    });
  }

  // ---- folders ----

  Future<List<Folder>> allFolders() async {
    final rows = await _db.query('folders', orderBy: 'name COLLATE NOCASE');
    return rows.map(Folder.fromRow).toList();
  }

  Future<void> upsertFolder(Folder f) =>
      _db.insert('folders', f.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<bool> upsertFolderIfNewer(Folder f) async {
    final rows = await _db.query('folders', columns: ['updated_at'], where: 'id = ?', whereArgs: [f.id]);
    if (rows.isNotEmpty && (rows.first['updated_at'] as int) >= f.updatedAt.millisecondsSinceEpoch) {
      return false;
    }
    if (await _isTombstoned('folders', f.id, f.updatedAt)) return false;
    await upsertFolder(f);
    return true;
  }

  /// 刪除資料夾：裡面的筆記移到「未分類」，子資料夾移到上一層。
  Future<void> deleteFolder(Folder f) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      await txn.update('notes', {'folder_id': null, 'updated_at': now},
          where: 'folder_id = ?', whereArgs: [f.id]);
      await txn.update('folders', {'parent_id': f.parentId, 'updated_at': now},
          where: 'parent_id = ?', whereArgs: [f.id]);
      await txn.delete('folders', where: 'id = ?', whereArgs: [f.id]);
      await _tombstone(txn, 'folders', f.id);
    });
  }

  // ---- attachments（圖片） ----

  Future<void> putAttachment({
    required String id,
    required String noteId,
    required String mime,
    required List<int> bytes,
    double? width,
    double? height,
  }) =>
      _db.insert(
        'attachments',
        {
          'id': id,
          'note_id': noteId,
          'mime': mime,
          'bytes': bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
          'width': width,
          'height': height,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<int>?> attachmentBytes(String id) async {
    final rows = await _db.query('attachments',
        columns: ['bytes'], where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first['bytes'] as List<int>;
  }

  // ---- 備份 / 還原 ----

  /// 把整個資料庫複製成一個獨立的備份檔。
  Future<void> exportTo(String path) => _db.execute('VACUUM INTO ?', [path]);

  /// 從另一個本 app 的資料庫（備份檔）合併進來：
  /// 每一筆資料比較 updated_at，新的贏；對方的 tombstone 也會套用。
  /// 回傳寫入（新增或更新）的筆記數。
  Future<int> mergeFrom(DatabaseFactory factory, String path) async {
    final other = await factory.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
    var changed = 0;
    try {
      final tables = (await other.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'] as String)
          .toSet();
      if (!tables.containsAll(['notes', 'folders', 'attachments', 'tombstones'])) {
        throw const FormatException('這不是「我的筆記」的備份檔');
      }
      for (final r in await other.query('folders')) {
        await upsertFolderIfNewer(Folder.fromRow(r));
      }
      for (final r in await other.query('notes')) {
        if (await upsertNoteIfNewer(Note.fromRow(r))) changed++;
      }
      for (final r in await other.query('attachments')) {
        final mine = await _db.query('attachments',
            columns: ['updated_at'], where: 'id = ?', whereArgs: [r['id']]);
        if (mine.isEmpty || (mine.first['updated_at'] as int) < (r['updated_at'] as int)) {
          await _db.insert('attachments', r, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      for (final t in await other.query('tombstones')) {
        final table = t['table_name'] as String;
        final id = t['row_id'] as String;
        final deletedAt = t['deleted_at'] as int;
        if (table != 'notes' && table != 'folders') continue;
        final mine = await _db.query(table, columns: ['updated_at'], where: 'id = ?', whereArgs: [id]);
        // 只有在對方刪除之後我這邊沒再改過，才跟著刪。
        if (mine.isNotEmpty && (mine.first['updated_at'] as int) <= deletedAt) {
          await _db.delete(table, where: 'id = ?', whereArgs: [id]);
          if (table == 'notes') await _db.delete('attachments', where: 'note_id = ?', whereArgs: [id]);
          changed++;
        }
        await _db.insert('tombstones', t, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } finally {
      await other.close();
    }
    return changed;
  }

  Future<bool> _isTombstoned(String table, String id, DateTime updatedAt) async {
    final rows = await _db.query('tombstones',
        columns: ['deleted_at'], where: 'table_name = ? AND row_id = ?', whereArgs: [table, id]);
    return rows.isNotEmpty && (rows.first['deleted_at'] as int) >= updatedAt.millisecondsSinceEpoch;
  }

  // ---- settings ----

  Future<String?> getSetting(String key) async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) => _db.insert(
      'settings', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> _tombstone(DatabaseExecutor ex, String table, String id) => ex.insert(
        'tombstones',
        {'table_name': table, 'row_id': id, 'deleted_at': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<int> tombstoneCount() async =>
      (await _db.rawQuery('SELECT COUNT(*) AS c FROM tombstones')).first['c'] as int;
}
