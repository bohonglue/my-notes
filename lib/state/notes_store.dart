import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../data/models.dart';

/// 左側選單選到的檢視。
sealed class NoteView {
  const NoteView();
}

class AllNotesView extends NoteView {
  const AllNotesView();
}

class FolderView extends NoteView {
  const FolderView(this.folderId);
  final String folderId;
}

class ArchiveView extends NoteView {
  const ArchiveView();
}

class TrashView extends NoteView {
  const TrashView();
}

/// 筆記在垃圾桶保留的天數，超過就自動永久刪除。
const trashRetentionDays = 30;

class NotesStore extends ChangeNotifier {
  NotesStore(this.db);

  final NotesDatabase db;
  static const _uuid = Uuid();

  List<Note> _notes = [];
  List<Folder> _folders = [];
  NoteView _view = const AllNotesView();
  String _query = '';

  List<Folder> get folders => _folders;
  NoteView get view => _view;

  /// 本機資料每改一次就加一（給同步判斷「有沒有要上傳的變更」）。
  int get localChanges => _localChanges;
  int _localChanges = 0;

  void _changed() {
    _localChanges++;
    notifyListeners();
  }
  String get query => _query;

  Future<void> load() async {
    _notes = await db.allNotes();
    _folders = await db.allFolders();
    await _purgeOldTrash();
    notifyListeners();
  }

  set view(NoteView v) {
    _view = v;
    notifyListeners();
  }

  set query(String q) {
    _query = q;
    notifyListeners();
  }

  Note? noteById(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Folder? folderById(String? id) {
    if (id == null) return null;
    for (final f in _folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<Folder> childFolders(String? parentId) =>
      _folders.where((f) => f.parentId == parentId).toList();

  /// 某資料夾及其所有子資料夾的 id。
  Set<String> _folderAndDescendants(String id) {
    final result = {id};
    var added = true;
    while (added) {
      added = false;
      for (final f in _folders) {
        if (f.parentId != null && result.contains(f.parentId) && result.add(f.id)) {
          added = true;
        }
      }
    }
    return result;
  }

  /// 目前檢視要顯示的筆記：置頂的在前，其餘依修改時間排序。
  /// 有搜尋字串時，搜尋所有不在垃圾桶的筆記（包含封存）。
  List<Note> get visibleNotes => _notesFor(_view, _query);

  int countIn(NoteView v) => _notesFor(v, '').length;

  List<Note> _notesFor(NoteView view, String query) {
    Iterable<Note> list = _notes;
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((n) =>
          !n.isTrashed &&
          (n.title.toLowerCase().contains(q) || n.plainText.toLowerCase().contains(q)));
    } else {
      switch (view) {
        case AllNotesView():
          list = list.where((n) => !n.isTrashed && !n.archived);
        case FolderView(:final folderId):
          final ids = _folderAndDescendants(folderId);
          list = list.where((n) => !n.isTrashed && !n.archived && ids.contains(n.folderId));
        case ArchiveView():
          list = list.where((n) => !n.isTrashed && n.archived);
        case TrashView():
          list = list.where((n) => n.isTrashed);
      }
    }
    return list.toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
  }

  // ---- 筆記操作 ----

  Note newNote(NoteType type) {
    final now = DateTime.now();
    final folder = switch (_view) {
      FolderView(:final folderId) => folderId,
      _ => null,
    };
    return Note(
      id: _uuid.v4(),
      type: type,
      folderId: folder,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 儲存筆記（新增或更新）。空白的新筆記不會存，除非 [allowEmpty]
  /// （例如手寫筆記沒有文字，但有筆畫）。
  Future<void> save(Note n, {bool touch = true, bool allowEmpty = false}) async {
    final isNew = noteById(n.id) == null;
    if (isNew && !allowEmpty && n.title.trim().isEmpty && n.plainText.trim().isEmpty) return;
    if (touch) n.updatedAt = DateTime.now();
    await db.upsertNote(n);
    if (isNew) _notes.add(n);
    _changed();
  }

  Future<void> togglePin(Note n) async {
    n.pinned = !n.pinned;
    await save(n);
  }

  Future<void> setArchived(Note n, bool archived) async {
    n.archived = archived;
    if (archived) n.pinned = false;
    await save(n);
  }

  Future<void> moveToTrash(Note n) async {
    n.trashedAt = DateTime.now();
    n.pinned = false;
    await save(n);
  }

  Future<void> restore(Note n) async {
    n.trashedAt = null;
    await save(n);
  }

  Future<void> deleteForever(Note n) async {
    await db.deleteNote(n.id);
    _notes.removeWhere((e) => e.id == n.id);
    _changed();
  }

  Future<void> emptyTrash() async {
    for (final n in _notes.where((n) => n.isTrashed).toList()) {
      await db.deleteNote(n.id);
    }
    _notes.removeWhere((n) => n.isTrashed);
    _changed();
  }

  Future<void> _purgeOldTrash() async {
    final cutoff = DateTime.now().subtract(const Duration(days: trashRetentionDays));
    final old = _notes.where((n) => n.trashedAt != null && n.trashedAt!.isBefore(cutoff)).toList();
    for (final n in old) {
      await db.deleteNote(n.id);
    }
    _notes.removeWhere(old.contains);
    if (old.isNotEmpty) _localChanges++;
  }

  // ---- 資料夾操作 ----

  Future<Folder> createFolder(String name, {String? parentId}) async {
    final f = Folder(id: _uuid.v4(), name: name, parentId: parentId, updatedAt: DateTime.now());
    await db.upsertFolder(f);
    _folders = await db.allFolders();
    _changed();
    return f;
  }

  Future<void> renameFolder(Folder f, String name) async {
    f.name = name;
    f.updatedAt = DateTime.now();
    await db.upsertFolder(f);
    _folders = await db.allFolders();
    _changed();
  }

  Future<void> deleteFolder(Folder f) async {
    await db.deleteFolder(f);
    _localChanges++;
    if (_view case FolderView(:final folderId) when folderId == f.id) {
      _view = const AllNotesView();
    }
    await load();
  }
}
