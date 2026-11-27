import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// 把 Keep My Notes 的 HTML 內容（Android Html.toHtml 的格式）轉成 Quill Delta。
///
/// 支援：p、br、b/strong、i/em、u、strike/del/s、span style="background-color"、
/// span style="color"、img id="…"（轉成 attachment:… 的圖片）。
/// [imageSource] 把 img 的 id 轉成 Delta 裡的圖片來源；回傳 null 代表略過該圖片。
List<Map<String, dynamic>> htmlToDelta(String source, {String? Function(String imgId)? imageSource}) {
  final ops = <Map<String, dynamic>>[];

  void insert(Object value, Map<String, dynamic> attrs) {
    if (value is String) {
      if (value.isEmpty) return;
      // 跟上一個同樣格式的文字合併
      if (ops.isNotEmpty && ops.last['insert'] is String && _sameAttrs(ops.last['attributes'], attrs)) {
        ops.last['insert'] = (ops.last['insert'] as String) + value;
        return;
      }
    }
    ops.add({'insert': value, if (attrs.isNotEmpty) 'attributes': Map.of(attrs)});
  }

  void newline() => insert('\n', const {});

  void walk(dom.Node node, Map<String, dynamic> attrs) {
    if (node is dom.Text) {
      // Html.toHtml 會在 <br> 後面加真正的換行字元，那只是排版用的，忽略。
      insert(node.text.replaceAll('\n', ''), attrs);
      return;
    }
    if (node is! dom.Element) {
      for (final c in node.nodes) {
        walk(c, attrs);
      }
      return;
    }
    final tag = node.localName;
    final a = Map<String, dynamic>.of(attrs);
    switch (tag) {
      case 'br':
        newline();
        return;
      case 'img':
        final id = node.attributes['id'] ?? node.attributes['src'];
        final src = id == null ? null : (imageSource == null ? id : imageSource(id));
        if (src != null) {
          insert({'image': src}, const {});
        }
        return;
      case 'b' || 'strong':
        a['bold'] = true;
      case 'i' || 'em' || 'cite' || 'dfn':
        a['italic'] = true;
      case 'u':
        a['underline'] = true;
      case 'strike' || 'del' || 's':
        a['strike'] = true;
      case 'span' || 'font':
        final style = node.attributes['style'] ?? '';
        final bg = RegExp(r'background-color\s*:\s*(#[0-9a-fA-F]{6})').firstMatch(style);
        if (bg != null) a['background'] = bg.group(1)!.toLowerCase();
        final fg = RegExp(r'(?<![-\w])color\s*:\s*(#[0-9a-fA-F]{6})').firstMatch(style);
        if (fg != null) a['color'] = fg.group(1)!.toLowerCase();
        final fontColor = node.attributes['color'];
        if (fontColor != null && fontColor.startsWith('#')) a['color'] = fontColor.toLowerCase();
    }
    for (final c in node.nodes) {
      walk(c, a);
    }
    if (tag == 'p' || tag == 'div' || tag == 'li') {
      // 段落結尾：若最後一個字元已經是 <br> 產生的換行，就不再多加一行，
      // 跟原 app 顯示的行數一致。
      final last = ops.isEmpty ? null : ops.last['insert'];
      if (!(last is String && last.endsWith('\n'))) newline();
    }
  }

  final doc = html.parseFragment(source);
  walk(doc, const {});

  // Quill 文件一定要以換行結尾。
  final last = ops.isEmpty ? null : ops.last['insert'];
  if (!(last is String && last.endsWith('\n'))) newline();
  // 拿掉結尾多餘的空行（保留最後一個換行）。
  while (ops.length > 1 && ops.last['insert'] == '\n' && ops[ops.length - 2]['insert'] is String &&
      (ops[ops.length - 2]['insert'] as String).endsWith('\n')) {
    ops.removeLast();
  }
  return ops;
}

/// Delta 的純文字（給搜尋和卡片預覽用）。
String deltaPlainText(List<Map<String, dynamic>> ops) =>
    ops.map((o) => o['insert'] is String ? o['insert'] as String : '').join().trim();

bool _sameAttrs(Object? a, Map<String, dynamic> b) {
  final m = (a as Map<String, dynamic>?) ?? const {};
  if (m.length != b.length) return false;
  for (final e in b.entries) {
    if (m[e.key] != e.value) return false;
  }
  return true;
}
