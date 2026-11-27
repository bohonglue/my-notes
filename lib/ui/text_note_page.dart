import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/notes_store.dart';
import 'attachment_image.dart';
import 'note_actions.dart';
import 'note_colors.dart';

/// 文字筆記編輯器（Quill 富文字：粗體、底線、刪除線、螢光、清單…）。
class TextNotePage extends StatefulWidget {
  const TextNotePage({super.key, required this.note});

  final Note note;

  @override
  State<TextNotePage> createState() => _TextNotePageState();
}

class _TextNotePageState extends State<TextNotePage> {
  late final QuillController _quill;
  late final TextEditingController _title;
  final _focus = FocusNode();
  Timer? _debounce;

  Note get note => widget.note;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: note.title);
    final doc = note.content.isEmpty
        ? Document()
        : Document.fromJson(jsonDecode(note.content) as List);
    _quill = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: note.isTrashed,
    );
    _quill.document.changes.listen((_) => _scheduleSave());
    _title.addListener(_scheduleSave);
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    _debounce?.cancel();
    note.title = _title.text;
    note.content = jsonEncode(_quill.document.toDelta().toJson());
    note.plainText = _quill.document.toPlainText().replaceAll('\uFFFC', '').trim();
    await context.read<NotesStore>().save(note);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _quill.dispose();
    _title.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = noteBackground(context, note.color);
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
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: TextField(
                controller: _title,
                readOnly: note.isTrashed,
                style: Theme.of(context).textTheme.titleLarge,
                decoration: const InputDecoration(hintText: '標題', border: InputBorder.none),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: QuillEditor.basic(
                  controller: _quill,
                  focusNode: _focus,
                  config: const QuillEditorConfig(
                    embedBuilders: [AttachmentImageEmbedBuilder()],
                    placeholder: '內容',
                    expands: true,
                    padding: EdgeInsets.only(bottom: 16),
                  ),
                ),
              ),
            ),
            if (!note.isTrashed)
              SafeArea(
                top: false,
                child: QuillSimpleToolbar(
                  controller: _quill,
                  config: const QuillSimpleToolbarConfig(
                    multiRowsDisplay: false,
                    showFontFamily: false,
                    showFontSize: false,
                    showSubscript: false,
                    showSuperscript: false,
                    showInlineCode: false,
                    showCodeBlock: false,
                    showSearchButton: false,
                    showDirection: false,
                    showLink: false,
                    showQuote: false,
                    showIndent: false,
                    showHeaderStyle: false,
                    showAlignmentButtons: false,
                    showColorButton: false,
                    // 「清除格式」只對選取的文字有效，沒選字時按了沒反應，容易誤會，先拿掉。
                    showClearFormat: false,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
