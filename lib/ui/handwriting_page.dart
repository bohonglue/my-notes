import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ink.dart';
import '../data/models.dart';
import '../state/notes_store.dart';
import 'ink_painter.dart';
import 'note_actions.dart';
import 'note_colors.dart';

enum InkTool { pen, highlighter, eraser }

const _penColors = <int>[
  0xFF202020, 0xFF1E5BD8, 0xFFD32F2F, 0xFF2E7D32, 0xFFF57C00, 0xFF7B1FA2, 0xFF6D4C41,
];
const _highlighterColors = <int>[0xFFFFEB3B, 0xFF8BC34A, 0xFF4FC3F7, 0xFFF48FB1, 0xFFFFB74D];
const _penWidths = <double>[3, 6, 10, 18];
const _highlighterWidths = <double>[20, 32, 48];
const _eraserRadius = 14.0;

/// 手寫筆記：用手指、觸控筆或電繪板直接寫字畫圖。
///
/// 觸控規則：
/// - 觸控筆、電繪板、滑鼠：畫畫（觸控筆反過來用＝橡皮擦）
/// - 手指：還沒用過觸控筆時，一根手指畫畫、兩根手指捲動；
///   一旦偵測到觸控筆，手指就只用來捲動（防止手掌誤觸），可在工具列切換。
class HandwritingPage extends StatefulWidget {
  const HandwritingPage({super.key, required this.note});

  final Note note;

  @override
  State<HandwritingPage> createState() => _HandwritingPageState();
}

class _HandwritingPageState extends State<HandwritingPage> {
  late final TextEditingController _title;
  late final InkPage _page;
  final _scroll = ScrollController();
  final _repaint = ValueNotifier<int>(0);
  final _undo = <_Action>[];
  final _redo = <_Action>[];
  Timer? _debounce;

  InkTool _tool = InkTool.pen;
  int _penColor = _penColors.first;
  int _hlColor = _highlighterColors.first;
  double _penWidth = _penWidths[1];
  double _hlWidth = _highlighterWidths[1];
  bool _fingerScrollsOnly = false;

  // 目前的筆畫與手指狀態
  InkStroke? _current;
  int? _drawingPointer;
  bool _drawingErases = false;
  final _erasedThisGesture = <InkStroke>[];
  final _touches = <int, Offset>{};
  double _scale = 1;

  Note get note => widget.note;
  bool get _readOnly => note.isTrashed;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: note.title)..addListener(_scheduleSave);
    _page = InkPage.decode(note.content);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _scroll.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    _debounce?.cancel();
    note.title = _title.text;
    note.content = _page.isEmpty ? '' : _page.encode();
    note.plainText = '';
    final store = context.read<NotesStore>();
    if (store.noteById(note.id) == null && _page.isEmpty && note.title.trim().isEmpty) return;
    await store.save(note, allowEmpty: true);
  }

  // ---- 輸入處理 ----

  Offset _toPage(Offset local) => local / _scale;

  bool _isPen(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus ||
      e.kind == PointerDeviceKind.mouse;

  void _onDown(PointerDownEvent e) {
    if (_readOnly) return;
    if (e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus) {
      if (!_fingerScrollsOnly) setState(() => _fingerScrollsOnly = true);
    }
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) return;

    if (e.kind == PointerDeviceKind.touch) {
      _touches[e.pointer] = e.position;
      if (_fingerScrollsOnly) return;
      if (_touches.length > 1) {
        // 第二根手指放下：取消正在畫的線，改成捲動。
        _cancelStroke();
        return;
      }
    } else if (!_isPen(e)) {
      return;
    }
    if (_drawingPointer != null) return;
    _drawingPointer = e.pointer;
    _drawingErases = _tool == InkTool.eraser || e.kind == PointerDeviceKind.invertedStylus;
    final p = _toPage(e.localPosition);
    if (_drawingErases) {
      _erasedThisGesture.clear();
      _eraseAt(p);
    } else {
      final hl = _tool == InkTool.highlighter;
      _current = InkStroke(
        color: hl ? _hlColor : _penColor,
        width: hl ? _hlWidth : _penWidth,
        highlighter: hl,
        points: [p],
      );
      _repaint.value++;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (_touches.containsKey(e.pointer)) {
      final prev = _touches[e.pointer]!;
      _touches[e.pointer] = e.position;
      if (_fingerScrollsOnly || _touches.length > 1) {
        // 多根手指時用平均位移，這裡每根手指各貢獻 1/n。
        _scrollBy(-(e.position.dy - prev.dy) / _touches.length);
        return;
      }
    }
    if (e.pointer != _drawingPointer) return;
    final p = _toPage(e.localPosition);
    if (_drawingErases) {
      _eraseAt(p);
    } else if (_current != null) {
      final last = _current!.points.last;
      if ((p - last).distance >= 0.8) {
        _current!.points.add(p);
        _repaint.value++;
      }
    }
  }

  void _onUp(PointerEvent e) {
    _touches.remove(e.pointer);
    if (e.pointer != _drawingPointer) return;
    _drawingPointer = null;
    if (_drawingErases) {
      if (_erasedThisGesture.isNotEmpty) {
        _push(_Action(removed: List.of(_erasedThisGesture)));
      }
      _erasedThisGesture.clear();
    } else if (_current != null) {
      final s = _current!;
      _current = null;
      _page.strokes.add(s);
      _push(_Action(added: [s]));
    }
    final oldHeight = _page.height;
    _page.growToFit();
    if (_page.height != oldHeight) setState(() {});
    _repaint.value++;
    _scheduleSave();
  }

  void _cancelStroke() {
    _drawingPointer = null;
    _current = null;
    if (_erasedThisGesture.isNotEmpty) {
      _push(_Action(removed: List.of(_erasedThisGesture)));
      _erasedThisGesture.clear();
    }
    _repaint.value++;
  }

  void _eraseAt(Offset p) {
    final hits = _page.strokes.where((s) => s.hitTest(p, _eraserRadius)).toList();
    if (hits.isEmpty) return;
    _page.strokes.removeWhere(hits.contains);
    _erasedThisGesture.addAll(hits);
    _repaint.value++;
  }

  void _scrollBy(double dy) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    _scroll.jumpTo((pos.pixels + dy).clamp(pos.minScrollExtent, pos.maxScrollExtent));
  }

  // ---- 復原 / 重做 ----

  void _push(_Action a) {
    _undo.add(a);
    _redo.clear();
    setState(() {});
  }

  void _doUndo() {
    if (_undo.isEmpty) return;
    final a = _undo.removeLast();
    _page.strokes.removeWhere(a.added.contains);
    _page.strokes.addAll(a.removed);
    _redo.add(a);
    setState(() {});
    _repaint.value++;
    _scheduleSave();
  }

  void _doRedo() {
    if (_redo.isEmpty) return;
    final a = _redo.removeLast();
    _page.strokes.removeWhere(a.removed.contains);
    _page.strokes.addAll(a.added);
    _undo.add(a);
    setState(() {});
    _repaint.value++;
    _scheduleSave();
  }

  Future<void> _clearAll() async {
    if (_page.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除整頁？'),
        content: const Text('可以用「復原」找回來。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清除')),
        ],
      ),
    );
    if (ok != true) return;
    final all = List.of(_page.strokes);
    _page.strokes.clear();
    _push(_Action(removed: all));
    _repaint.value++;
    _scheduleSave();
  }

  // ---- 畫面 ----

  @override
  Widget build(BuildContext context) {
    final bg = noteBackground(context, note.color);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paper = bg ?? (dark ? const Color(0xFF1E1E1E) : Colors.white);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        backgroundColor: paper,
        appBar: AppBar(
          backgroundColor: paper,
          title: TextField(
            controller: _title,
            readOnly: _readOnly,
            decoration: const InputDecoration(hintText: '標題', border: InputBorder.none),
          ),
          actions: [
            if (!_readOnly) ...[
              IconButton(tooltip: '復原', icon: const Icon(Icons.undo), onPressed: _undo.isEmpty ? null : _doUndo),
              IconButton(tooltip: '重做', icon: const Icon(Icons.redo), onPressed: _redo.isEmpty ? null : _doRedo),
            ],
            ...noteEditorActions(context, note, () {
              setState(() {});
              _save();
            }),
          ],
        ),
        body: Column(
          children: [
            if (!_readOnly) _toolbar(context),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                // 寬螢幕上頁面最寬 900，置中。
                final w = math.min(c.maxWidth, 900.0);
                _scale = w / InkPage.width;
                return Listener(
                  onPointerSignal: (e) {
                    if (e is PointerScrollEvent) _scrollBy(e.scrollDelta.dy);
                  },
                  child: SingleChildScrollView(
                    controller: _scroll,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Center(
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: _onDown,
                        onPointerMove: _onMove,
                        onPointerUp: _onUp,
                        onPointerCancel: _onUp,
                        child: SizedBox(
                          width: w,
                          height: _page.height * _scale,
                          child: CustomPaint(
                            painter: InkPainter(
                              strokes: _page.strokes,
                              scale: _scale,
                              darkMode: dark,
                              current: () => _current,
                              repaint: _repaint,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = _tool == InkTool.highlighter ? _highlighterColors : _penColors;
    final widths = _tool == InkTool.highlighter ? _highlighterWidths : _penWidths;
    final selColor = _tool == InkTool.highlighter ? _hlColor : _penColor;
    final selWidth = _tool == InkTool.highlighter ? _hlWidth : _penWidth;

    Widget toolBtn(InkTool t, IconData icon, String tip) => IconButton(
          tooltip: tip,
          isSelected: _tool == t,
          style: IconButton.styleFrom(
            backgroundColor: _tool == t ? scheme.primaryContainer : null,
          ),
          icon: Icon(icon),
          onPressed: () => setState(() => _tool = t),
        );

    return Material(
      color: scheme.surfaceContainer,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            toolBtn(InkTool.pen, Icons.edit, '筆'),
            toolBtn(InkTool.highlighter, Icons.border_color, '螢光筆'),
            toolBtn(InkTool.eraser, Icons.auto_fix_normal, '橡皮擦（整筆擦掉）'),
            const SizedBox(width: 8),
            if (_tool != InkTool.eraser) ...[
              for (final c in colors)
                GestureDetector(
                  onTap: () => setState(() {
                    if (_tool == InkTool.highlighter) {
                      _hlColor = c;
                    } else {
                      _penColor = c;
                    }
                  }),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == selColor ? scheme.primary : scheme.outlineVariant,
                        width: c == selColor ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              for (final w in widths)
                IconButton(
                  tooltip: '粗細 ${w.toInt()}',
                  style: IconButton.styleFrom(
                    backgroundColor: w == selWidth ? scheme.primaryContainer : null,
                  ),
                  onPressed: () => setState(() {
                    if (_tool == InkTool.highlighter) {
                      _hlWidth = w;
                    } else {
                      _penWidth = w;
                    }
                  }),
                  icon: Container(
                    width: math.min(4 + w * 0.6, 22),
                    height: math.min(4 + w * 0.6, 22),
                    decoration: BoxDecoration(color: scheme.onSurface, shape: BoxShape.circle),
                  ),
                ),
            ],
            const SizedBox(width: 8),
            IconButton(
              tooltip: _fingerScrollsOnly ? '手指：只捲動（觸控筆模式）' : '手指：可以畫',
              isSelected: _fingerScrollsOnly,
              icon: Icon(_fingerScrollsOnly ? Icons.do_not_touch_outlined : Icons.touch_app_outlined),
              onPressed: () => setState(() => _fingerScrollsOnly = !_fingerScrollsOnly),
            ),
            IconButton(tooltip: '清除整頁', icon: const Icon(Icons.layers_clear_outlined), onPressed: _clearAll),
          ],
        ),
      ),
    );
  }
}

class _Action {
  _Action({this.added = const [], this.removed = const []});
  final List<InkStroke> added;
  final List<InkStroke> removed;
}

