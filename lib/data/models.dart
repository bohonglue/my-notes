import 'dart:convert';

/// 筆記種類
enum NoteType { text, checklist, handwriting }

class ChecklistItem {
  ChecklistItem({required this.text, this.checked = false});

  String text;
  bool checked;

  Map<String, dynamic> toJson() => {'text': text, 'checked': checked};

  factory ChecklistItem.fromJson(Map<String, dynamic> j) =>
      ChecklistItem(text: j['text'] as String? ?? '', checked: j['checked'] == true);
}

/// 一則筆記。
///
/// [content] 的格式依 [type] 而定：
/// - text：Quill Delta JSON
/// - checklist：ChecklistItem 陣列 JSON
/// - handwriting：筆畫 JSON（里程碑 3）
class Note {
  Note({
    required this.id,
    required this.type,
    this.title = '',
    this.content = '',
    this.plainText = '',
    this.color,
    this.folderId,
    this.pinned = false,
    this.archived = false,
    this.trashedAt,
    this.reminderAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final NoteType type;
  String title;
  String content;

  /// 純文字內容，給搜尋和清單預覽用。
  String plainText;

  /// ARGB 色碼；null 代表預設顏色。
  int? color;
  String? folderId;
  bool pinned;
  bool archived;

  /// 丟進垃圾桶的時間；null 代表不在垃圾桶。
  DateTime? trashedAt;
  DateTime? reminderAt;
  final DateTime createdAt;
  DateTime updatedAt;

  bool get isTrashed => trashedAt != null;

  List<ChecklistItem> get checklistItems {
    if (type != NoteType.checklist || content.isEmpty) return [];
    final list = jsonDecode(content) as List;
    return list.map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  set checklistItems(List<ChecklistItem> items) {
    content = jsonEncode(items.map((e) => e.toJson()).toList());
    plainText = items.map((e) => e.text).join('\n');
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'type': type.name,
        'title': title,
        'content': content,
        'plain_text': plainText,
        'color': color,
        'folder_id': folderId,
        'pinned': pinned ? 1 : 0,
        'archived': archived ? 1 : 0,
        'trashed_at': trashedAt?.millisecondsSinceEpoch,
        'reminder_at': reminderAt?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Note.fromRow(Map<String, Object?> r) => Note(
        id: r['id'] as String,
        type: NoteType.values.byName(r['type'] as String),
        title: r['title'] as String? ?? '',
        content: r['content'] as String? ?? '',
        plainText: r['plain_text'] as String? ?? '',
        color: r['color'] as int?,
        folderId: r['folder_id'] as String?,
        pinned: r['pinned'] == 1,
        archived: r['archived'] == 1,
        trashedAt: _date(r['trashed_at']),
        reminderAt: _date(r['reminder_at']),
        createdAt: _date(r['created_at'])!,
        updatedAt: _date(r['updated_at'])!,
      );
}

class Folder {
  Folder({
    required this.id,
    required this.name,
    this.parentId,
    this.color,
    required this.updatedAt,
  });

  final String id;
  String name;
  String? parentId;
  int? color;
  DateTime updatedAt;

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'parent_id': parentId,
        'color': color,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Folder.fromRow(Map<String, Object?> r) => Folder(
        id: r['id'] as String,
        name: r['name'] as String,
        parentId: r['parent_id'] as String?,
        color: r['color'] as int?,
        updatedAt: _date(r['updated_at'])!,
      );
}

DateTime? _date(Object? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms as int);
