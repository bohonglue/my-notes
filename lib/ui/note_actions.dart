import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/notes_store.dart';
import 'note_colors.dart';

/// 編輯器上方共用的按鈕：置頂、顏色、資料夾、更多（封存、刪除）。
List<Widget> noteEditorActions(BuildContext context, Note note, VoidCallback onChanged) {
  final store = context.read<NotesStore>();
  if (note.isTrashed) {
    return [
      IconButton(
        tooltip: '還原',
        icon: const Icon(Icons.restore_from_trash),
        onPressed: () async {
          await store.restore(note);
          onChanged();
        },
      ),
    ];
  }
  return [
    IconButton(
      tooltip: note.pinned ? '取消置頂' : '置頂',
      icon: Icon(note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
      onPressed: () {
        note.pinned = !note.pinned;
        onChanged();
      },
    ),
    IconButton(
      tooltip: '顏色',
      icon: const Icon(Icons.palette_outlined),
      onPressed: () async {
        final c = await pickNoteColor(context, note.color);
        if (c == null) return;
        note.color = c == -1 ? null : c;
        onChanged();
      },
    ),
    IconButton(
      tooltip: '資料夾',
      icon: const Icon(Icons.folder_outlined),
      onPressed: () async {
        final id = await pickFolder(context, note.folderId);
        if (id == null) return;
        note.folderId = id.isEmpty ? null : id;
        onChanged();
      },
    ),
    PopupMenuButton<String>(
      onSelected: (v) async {
        final nav = Navigator.of(context);
        switch (v) {
          case 'archive':
            note.archived = !note.archived;
            if (note.archived) note.pinned = false;
            onChanged();
            if (note.archived) nav.pop();
          case 'trash':
            note.trashedAt = DateTime.now();
            note.pinned = false;
            onChanged();
            nav.pop();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'archive', child: Text(note.archived ? '取消封存' : '封存')),
        const PopupMenuItem(value: 'trash', child: Text('移到垃圾桶')),
      ],
    ),
  ];
}

/// 選資料夾。回傳資料夾 id；空字串代表「未分類」；null 代表取消。
Future<String?> pickFolder(BuildContext context, String? current) {
  final store = context.read<NotesStore>();
  List<Widget> tiles(String? parent, int depth) => [
        for (final f in store.childFolders(parent)) ...[
          ListTile(
            contentPadding: EdgeInsets.only(left: 16.0 + depth * 20, right: 16),
            leading: const Icon(Icons.folder_outlined),
            title: Text(f.name),
            selected: f.id == current,
            onTap: () => Navigator.pop(context, f.id),
          ),
          ...tiles(f.id, depth + 1),
        ],
      ];
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('未分類'),
              selected: current == null,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            ...tiles(null, 0),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('新增資料夾'),
              onTap: () async {
                final name = await askText(ctx, title: '新增資料夾');
                if (name == null || name.trim().isEmpty) return;
                final f = await store.createFolder(name.trim());
                if (ctx.mounted) Navigator.pop(ctx, f.id);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> askText(BuildContext context, {required String title, String initial = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('確定')),
      ],
    ),
  );
}
