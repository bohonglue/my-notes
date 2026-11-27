import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/notes_store.dart';
import '../state/settings_store.dart';
import 'checklist_page.dart';
import 'note_actions.dart';
import 'note_colors.dart';
import 'settings_page.dart';
import 'text_note_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _viewTitle(NotesStore s) => switch (s.view) {
        AllNotesView() => '所有筆記',
        FolderView(:final folderId) => s.folderById(folderId)?.name ?? '資料夾',
        ArchiveView() => '封存',
        TrashView() => '垃圾桶',
      };

  void _open(Note n) {
    final page = switch (n.type) {
      NoteType.checklist => ChecklistPage(note: n),
      _ => TextNotePage(note: n),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final settings = context.watch<SettingsStore>();
    final notes = store.visibleNotes;
    final wide = MediaQuery.of(context).size.width >= 900;
    final drawer = _NavDrawer(onSelected: () {
      if (!wide) Navigator.of(context).pop();
    });

    final body = notes.isEmpty
        ? Center(
            child: Text(
              store.query.isNotEmpty ? '找不到符合的筆記' : '這裡還沒有筆記',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          )
        : _NotesGrid(notes: notes, layout: settings.layout, onOpen: _open);

    return Scaffold(
      drawer: wide ? null : drawer,
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(hintText: '搜尋筆記', border: InputBorder.none),
                onChanged: (q) => store.query = q,
              )
            : Text(_viewTitle(store)),
        actions: [
          IconButton(
            tooltip: _searching ? '關閉搜尋' : '搜尋',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _search.clear();
                store.query = '';
              }
            }),
          ),
          IconButton(
            tooltip: settings.layout == NotesLayout.grid ? '清單檢視' : '格狀檢視',
            icon: Icon(settings.layout == NotesLayout.grid ? Icons.view_agenda_outlined : Icons.grid_view),
            onPressed: () => settings.setLayout(
                settings.layout == NotesLayout.grid ? NotesLayout.list : NotesLayout.grid),
          ),
          if (store.view is TrashView && notes.isNotEmpty)
            IconButton(
              tooltip: '清空垃圾桶',
              icon: const Icon(Icons.delete_forever_outlined),
              onPressed: () async {
                final ok = await _confirm(context, '清空垃圾桶？', '裡面的 ${notes.length} 則筆記會永久刪除。');
                if (ok) await store.emptyTrash();
              },
            ),
        ],
      ),
      body: wide ? Row(children: [SizedBox(width: 280, child: drawer), const VerticalDivider(width: 1), Expanded(child: body)]) : body,
      floatingActionButton: store.view is TrashView || store.view is ArchiveView
          ? null
          : _NewNoteButton(onCreate: (type) => _open(store.newNote(type))),
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確定')),
      ],
    ),
  );
  return r == true;
}

class _NewNoteButton extends StatelessWidget {
  const _NewNoteButton({required this.onCreate});

  final void Function(NoteType) onCreate;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.notes),
          onPressed: () => onCreate(NoteType.text),
          child: const Text('文字筆記'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.checklist),
          onPressed: () => onCreate(NoteType.checklist),
          child: const Text('待辦清單'),
        ),
      ],
      builder: (context, ctrl, _) => FloatingActionButton(
        tooltip: '新增',
        onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _NotesGrid extends StatelessWidget {
  const _NotesGrid({required this.notes, required this.layout, required this.onOpen});

  final List<Note> notes;
  final NotesLayout layout;
  final void Function(Note) onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = layout == NotesLayout.list ? 1 : (c.maxWidth / 220).floor().clamp(2, 6);
      // 簡單的瀑布流：依序把卡片放進目前最短的欄（以字數估計高度）。
      final columns = List.generate(cols, (_) => <Note>[]);
      final heights = List.filled(cols, 0.0);
      for (final n in notes) {
        var best = 0;
        for (var i = 1; i < cols; i++) {
          if (heights[i] < heights[best]) best = i;
        }
        columns[best].add(n);
        heights[best] += 80 + n.plainText.length.clamp(0, 240) * 0.5;
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final col in columns)
              Expanded(
                child: Column(
                  children: [for (final n in col) _NoteCard(note: n, onOpen: onOpen)],
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onOpen});

  final Note note;
  final void Function(Note) onOpen;

  @override
  Widget build(BuildContext context) {
    final store = context.read<NotesStore>();
    final theme = Theme.of(context);
    final folder = store.folderById(note.folderId);
    final items = note.type == NoteType.checklist ? note.checklistItems : const <ChecklistItem>[];

    return Card(
      color: noteBackground(context, note.color),
      margin: const EdgeInsets.all(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(note),
        onLongPress: () => _menu(context, store),
        onSecondaryTap: () => _menu(context, store),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (note.title.isNotEmpty)
                  Expanded(
                    child: Text(note.title,
                        style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                  )
                else
                  const Spacer(),
                if (note.pinned) const Icon(Icons.push_pin, size: 16),
              ]),
              if (note.title.isNotEmpty) const SizedBox(height: 4),
              if (note.type == NoteType.checklist)
                for (final it in items.take(6))
                  Row(children: [
                    Icon(it.checked ? Icons.check_box : Icons.check_box_outline_blank, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(it.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: it.checked ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                    ),
                  ])
              else if (note.plainText.isNotEmpty)
                Text(note.plainText, maxLines: 8, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Row(children: [
                if (folder != null) ...[
                  const Icon(Icons.folder_outlined, size: 14),
                  const SizedBox(width: 2),
                  Flexible(child: Text(folder.name, style: theme.textTheme.labelSmall, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                ],
                Text(DateFormat('yyyy/M/d').format(note.updatedAt), style: theme.textTheme.labelSmall),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, NotesStore store) async {
    final trashed = note.isTrashed;
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          if (trashed) ...[
            ListTile(leading: const Icon(Icons.restore), title: const Text('還原'), onTap: () => Navigator.pop(ctx, 'restore')),
            ListTile(leading: const Icon(Icons.delete_forever), title: const Text('永久刪除'), onTap: () => Navigator.pop(ctx, 'delete')),
          ] else ...[
            ListTile(
              leading: Icon(note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(note.pinned ? '取消置頂' : '置頂'),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            ListTile(leading: const Icon(Icons.palette_outlined), title: const Text('顏色'), onTap: () => Navigator.pop(ctx, 'color')),
            ListTile(leading: const Icon(Icons.folder_outlined), title: const Text('移到資料夾'), onTap: () => Navigator.pop(ctx, 'folder')),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(note.archived ? '取消封存' : '封存'),
              onTap: () => Navigator.pop(ctx, 'archive'),
            ),
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('移到垃圾桶'), onTap: () => Navigator.pop(ctx, 'trash')),
          ],
        ]),
      ),
    );
    if (!context.mounted) return;
    switch (v) {
      case 'restore':
        await store.restore(note);
      case 'delete':
        if (await _confirm(context, '永久刪除？', '刪除後無法復原。')) await store.deleteForever(note);
      case 'pin':
        await store.togglePin(note);
      case 'color':
        final c = await pickNoteColor(context, note.color);
        if (c != null) {
          note.color = c == -1 ? null : c;
          await store.save(note);
        }
      case 'folder':
        final id = await pickFolder(context, note.folderId);
        if (id != null) {
          note.folderId = id.isEmpty ? null : id;
          await store.save(note);
        }
      case 'archive':
        await store.setArchived(note, !note.archived);
      case 'trash':
        await store.moveToTrash(note);
    }
  }
}

class _NavDrawer extends StatelessWidget {
  const _NavDrawer({required this.onSelected});

  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final view = store.view;

    Widget item(IconData icon, String label, NoteView v, {bool selected = false, int depth = 0, Folder? folder}) {
      return ListTile(
        contentPadding: EdgeInsets.only(left: 16.0 + depth * 16, right: 8),
        leading: Icon(icon),
        title: Text(label, overflow: TextOverflow.ellipsis),
        trailing: Text('${store.countIn(v)}'),
        selected: selected,
        onTap: () {
          store.view = v;
          onSelected();
        },
        onLongPress: folder == null ? null : () => _folderMenu(context, store, folder),
      );
    }

    List<Widget> folderTiles(String? parent, int depth) => [
          for (final f in store.childFolders(parent)) ...[
            item(Icons.folder_outlined, f.name, FolderView(f.id),
                selected: view is FolderView && view.folderId == f.id, depth: depth, folder: f),
            ...folderTiles(f.id, depth + 1),
          ],
        ];

    return Drawer(
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('我的筆記', style: Theme.of(context).textTheme.titleLarge),
            ),
            item(Icons.notes, '所有筆記', const AllNotesView(), selected: view is AllNotesView),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(children: [
                Expanded(child: Text('資料夾', style: Theme.of(context).textTheme.labelLarge)),
                IconButton(
                  tooltip: '新增資料夾',
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: () async {
                    final name = await askText(context, title: '新增資料夾');
                    if (name != null && name.trim().isNotEmpty) await store.createFolder(name.trim());
                  },
                ),
              ]),
            ),
            ...folderTiles(null, 0),
            const Divider(),
            item(Icons.archive_outlined, '封存', const ArchiveView(), selected: view is ArchiveView),
            item(Icons.delete_outline, '垃圾桶', const TrashView(), selected: view is TrashView),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('設定'),
              onTap: () {
                onSelected();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _folderMenu(BuildContext context, NotesStore store, Folder f) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.edit), title: const Text('重新命名'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('新增子資料夾'),
              onTap: () => Navigator.pop(ctx, 'sub')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('刪除資料夾'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!context.mounted) return;
    switch (v) {
      case 'rename':
        final name = await askText(context, title: '重新命名', initial: f.name);
        if (name != null && name.trim().isNotEmpty) await store.renameFolder(f, name.trim());
      case 'sub':
        final name = await askText(context, title: '新增子資料夾');
        if (name != null && name.trim().isNotEmpty) await store.createFolder(name.trim(), parentId: f.id);
      case 'delete':
        if (await _confirm(context, '刪除「${f.name}」？', '裡面的筆記不會被刪除，會移到「未分類」。')) {
          await store.deleteFolder(f);
        }
    }
  }
}
