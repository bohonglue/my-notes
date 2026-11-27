import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database.dart';
import 'html_to_delta.dart';
import 'models.dart';
import 'svg_ink.dart';

/// 匯入結果統計。
class ImportResult {
  int notes = 0;
  int checklists = 0;
  int handwriting = 0;
  int folders = 0;
  int images = 0;
  int trashed = 0;
  int skippedLocked = 0;
  int skippedUnchanged = 0;

  int get total => notes + checklists + handwriting;

  @override
  String toString() => '筆記 $notes、待辦清單 $checklists、手寫 $handwriting、'
      '資料夾 $folders、圖片 $images（其中 $trashed 則在垃圾桶）';
}

/// 匯入 Keep My Notes 的 .kmnb 備份（其實是 SQLite 資料庫）。
///
/// - 用固定的 id（kmnb-…），重複匯入同一份備份不會產生重複的筆記；
///   如果匯入後你在這個 app 改過，備份裡較舊的版本不會蓋掉你的修改。
/// - 原 app 的垃圾桶會匯入到垃圾桶，從匯入當下開始算 30 天。
/// - 上了鎖（加密）的筆記無法解開，會略過並計數。
Future<ImportResult> importKmnb(DatabaseFactory factory, String path, NotesDatabase target) async {
  final src = await factory.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
  final result = ImportResult();
  final now = DateTime.now();
  try {
    final tables = (await src.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'] as String)
        .toSet();
    if (!tables.contains('note')) {
      throw const FormatException('這不是 Keep My Notes 的備份檔');
    }
    Future<List<Map<String, Object?>>> rows(String table) async =>
        tables.contains(table) ? await src.query(table) : const [];

    // ---- 資料夾 ----
    final folderRows = await rows('folder');
    final liveFolders = <Object?>{};
    for (final f in folderRows) {
      if (f['deleted'] == 1) continue;
      liveFolders.add(f['folder_id']);
    }
    for (final f in folderRows) {
      if (f['deleted'] == 1) continue;
      final parent = f['parent_folder_id'];
      final folder = Folder(
        id: _id('folder', f['folder_id']),
        name: f['folder_name'] as String,
        parentId: parent != null && liveFolders.contains(parent) ? _id('folder', parent) : null,
        color: kmnbColor(f['background_color'] as String?),
        updatedAt: _date(f['last_update_date']) ?? now,
      );
      if (await target.upsertFolderIfNewer(folder)) result.folders++;
    }
    String? folderId(Object? id) => id != null && liveFolders.contains(id) ? _id('folder', id) : null;

    Note base(Map<String, Object?> r, NoteType type, String id) {
      final trashed = r['deleted'] == 1;
      return Note(
        id: id,
        type: type,
        title: (r['title'] as String?) ?? '',
        color: kmnbColor(r['background_color'] as String?),
        folderId: folderId(r['folder_id']),
        trashedAt: trashed ? now : null,
        createdAt: _date(r['created_date']) ?? now,
        updatedAt: _date(r['modified_date']) ?? now,
      );
    }

    Future<void> save(Note n, ImportResult r, void Function() count) async {
      if (await target.upsertNoteIfNewer(n)) {
        count();
        if (n.isTrashed) r.trashed++;
      } else {
        r.skippedUnchanged++;
      }
    }

    // ---- 文字筆記與圖片 ----
    final imageRows = await rows('image');
    final imageIds = {for (final i in imageRows) '${i['image_id']}'};
    for (final r in await rows('note')) {
      if (r['locked'] == 1) {
        result.skippedLocked++;
        continue;
      }
      final id = _id('note', r['note_id']);
      final delta = htmlToDelta(
        (r['description'] as String?) ?? '',
        imageSource: (imgId) => imageIds.contains(imgId) ? 'attachment:${_id('img', imgId)}' : null,
      );
      final n = base(r, NoteType.text, id)
        ..content = jsonEncode(delta)
        ..plainText = deltaPlainText(delta);
      await save(n, result, () => result.notes++);
    }
    for (final i in imageRows) {
      if (i['locked'] == 1) continue;
      final bytes = i['image_bytes'] as List<int>;
      await target.putAttachment(
        id: _id('img', i['image_id']),
        noteId: _id('note', i['note_id']),
        mime: _sniffMime(bytes),
        bytes: bytes,
        width: (i['image_width'] as num?)?.toDouble(),
        height: (i['image_height'] as num?)?.toDouble(),
      );
      result.images++;
    }

    // ---- 待辦清單 ----
    final items = await rows('checklist_item');
    for (final r in await rows('checklist')) {
      if (r['locked'] == 1) {
        result.skippedLocked++;
        continue;
      }
      final mine = items.where((i) => i['checklist_id'] == r['checklist_id']).toList()
        ..sort((a, b) => (a['order_of_item'] as int).compareTo(b['order_of_item'] as int));
      final n = base(r, NoteType.checklist, _id('checklist', r['checklist_id']))
        ..checklistItems = [
          for (final i in mine) ChecklistItem(text: i['item_text'] as String, checked: i['checked'] == 1),
        ];
      await save(n, result, () => result.checklists++);
    }

    // ---- 手寫 ----
    for (final r in await rows('handwriting')) {
      if (r['locked'] == 1) {
        result.skippedLocked++;
        continue;
      }
      final svg = utf8.decode(r['handwriting_bytes'] as List<int>, allowMalformed: true);
      final n = base(r, NoteType.handwriting, _id('handwriting', r['handwriting_id']))
        ..content = svgToInk(svg).encode();
      await save(n, result, () => result.handwriting++);
    }
  } finally {
    await src.close();
  }
  return result;
}

String _id(String kind, Object? id) => 'kmnb-$kind-$id';

DateTime? _date(Object? ms) => ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;

String _sniffMime(List<int> b) {
  if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
  if (b.length > 2 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
  if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'image/gif';
  if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
  return 'application/octet-stream';
}

/// 原 app 的顏色是名稱（例如 "Mint Green"），對應到這個 app 的色票。
int? kmnbColor(String? name) {
  if (name == null || name.isEmpty) return null;
  final n = name.toLowerCase();
  const yellow = 0xFFFFF59D,
      orange = 0xFFFFCC80,
      pink = 0xFFF8BBD0,
      red = 0xFFEF9A9A,
      green = 0xFFC5E1A5,
      teal = 0xFF80CBC4,
      blue = 0xFF90CAF9,
      purple = 0xFFCE93D8,
      brown = 0xFFBCAAA4,
      grey = 0xFFCFD8DC;
  const exact = {
    'honey': orange,
    'peach': orange,
    'carnation pink': pink,
    'rose': pink,
    'bean red': red,
    'chili pepper': red,
    'crimson': red,
    'night': grey,
    'milk white': null,
    'white': null,
  };
  if (exact.containsKey(n)) return exact[n];
  if (n.contains('yellow') || n.contains('lemon') || n.contains('gold')) return yellow;
  if (n.contains('orange') || n.contains('apricot')) return orange;
  if (n.contains('pink') || n.contains('rose')) return pink;
  if (n.contains('red') || n.contains('cherry') || n.contains('scarlet')) return red;
  if (n.contains('teal') || n.contains('cyan') || n.contains('aqua') || n.contains('turquoise')) return teal;
  if (n.contains('green') || n.contains('lime') || n.contains('olive')) return green;
  if (n.contains('blue') || n.contains('sky') || n.contains('navy')) return blue;
  if (n.contains('purple') || n.contains('violet') || n.contains('lavender') || n.contains('lilac')) return purple;
  if (n.contains('brown') || n.contains('coffee') || n.contains('chocolate') || n.contains('mocha')) return brown;
  if (n.contains('gray') || n.contains('grey') || n.contains('silver')) return grey;
  return null;
}
