import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/notes_store.dart';
import 'note_actions.dart';
import 'note_colors.dart';

/// 待辦清單編輯器。打勾的項目會移到下方。
class ChecklistPage extends StatefulWidget {
  const ChecklistPage({super.key, required this.note});

  final Note note;

  @override
  State<ChecklistPage> createState() => _ChecklistPageState();
}

class _Row {
  _Row(ChecklistItem item)
      : checked = item.checked,
        ctrl = TextEditingController(text: item.text),
        focus = FocusNode();
  bool checked;
  final TextEditingController ctrl;
  final FocusNode focus;
}

class _ChecklistPageState extends State<ChecklistPage> {
  late final TextEditingController _title;
  late final List<_Row> _rows;

  Note get note => widget.note;
  bool get _readOnly => note.isTrashed;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: note.title);
    _rows = note.checklistItems.map(_Row.new).toList();
    if (_rows.isEmpty) _rows.add(_Row(ChecklistItem(text: '')));
  }

  Future<void> _save() async {
    note.title = _title.text;
    note.checklistItems = [
      for (final r in _rows)
        if (r.ctrl.text.trim().isNotEmpty) ChecklistItem(text: r.ctrl.text, checked: r.checked),
    ];
    await context.read<NotesStore>().save(note);
  }

  void _addAfter(int index) {
    final row = _Row(ChecklistItem(text: ''));
    setState(() => _rows.insert(index + 1, row));
    WidgetsBinding.instance.addPostFrameCallback((_) => row.focus.requestFocus());
  }

  @override
  void dispose() {
    _title.dispose();
    for (final r in _rows) {
      r.ctrl.dispose();
      r.focus.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = noteBackground(context, note.color);
    final unchecked = [for (var i = 0; i < _rows.length; i++) if (!_rows[i].checked) i];
    final checked = [for (var i = 0; i < _rows.length; i++) if (_rows[i].checked) i];

    Widget rowTile(int i) {
      final r = _rows[i];
      return Row(
        key: ObjectKey(r),
        children: [
          Checkbox(
            value: r.checked,
            onChanged: _readOnly
                ? null
                : (v) {
                    setState(() => r.checked = v ?? false);
                    _save();
                  },
          ),
          Expanded(
            child: TextField(
              controller: r.ctrl,
              focusNode: r.focus,
              readOnly: _readOnly,
              style: r.checked
                  ? TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: Theme.of(context).disabledColor,
                    )
                  : null,
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _addAfter(i),
              onChanged: (_) => _save(),
            ),
          ),
          if (!_readOnly)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                setState(() => _rows.removeAt(i));
                _save();
              },
            ),
        ],
      );
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          actions: noteEditorActions(context, note, () {
            setState(() {});
            _save();
          }),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                controller: _title,
                readOnly: _readOnly,
                style: Theme.of(context).textTheme.titleLarge,
                decoration: const InputDecoration(hintText: '標題', border: InputBorder.none),
                onChanged: (_) => _save(),
              ),
            ),
            for (final i in unchecked) rowTile(i),
            if (!_readOnly)
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('新增項目'),
                onTap: () => _addAfter(_rows.length - 1),
              ),
            if (checked.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text('已完成 ${checked.length} 項',
                    style: Theme.of(context).textTheme.labelMedium),
              ),
              for (final i in checked) rowTile(i),
            ],
          ],
        ),
      ),
    );
  }
}
