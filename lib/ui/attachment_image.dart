import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../state/notes_store.dart';

/// 在 Quill 編輯器裡顯示存在資料庫裡的圖片（來源格式：`attachment:<id>`）。
class AttachmentImageEmbedBuilder extends EmbedBuilder {
  const AttachmentImageEmbedBuilder();

  @override
  String get key => 'image';

  @override
  String toPlainText(Embed node) => '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final src = embedContext.node.value.data as String;
    if (!src.startsWith('attachment:')) {
      return const Icon(Icons.broken_image_outlined);
    }
    return AttachmentImage(id: src.substring('attachment:'.length));
  }
}

class AttachmentImage extends StatefulWidget {
  const AttachmentImage({super.key, required this.id});

  final String id;

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  late final Future<List<int>?> _bytes = context.read<NotesStore>().db.attachmentBytes(widget.id);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>?>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
        }
        final b = snap.data;
        if (b == null) return const Icon(Icons.broken_image_outlined);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
                body: InteractiveViewer(
                  maxScale: 8,
                  child: Center(child: Image.memory(Uint8List.fromList(b))),
                ),
              ),
            )),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: Image.memory(Uint8List.fromList(b), fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
  }
}
