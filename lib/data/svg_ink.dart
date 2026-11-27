import 'dart:ui';

import 'ink.dart';

/// 把 Keep My Notes 手寫筆記的 SVG 轉成筆畫。
///
/// 它的 SVG 是一串 `<path d="M x,y Q cx,cy x,y Q …" stroke="#rrggbb" stroke-width="5px"/>`，
/// 其中 Q 的控制點就是原始的觸控點，終點是相鄰兩點的中點。所以取 M 的起點、
/// 每個 Q 的控制點，加上最後的終點，就能還原出原始的筆跡。
InkPage svgToInk(String svg) {
  final widthMatch = RegExp(r'<svg[^>]*\swidth="([\d.]+)').firstMatch(svg);
  final heightMatch = RegExp(r'<svg[^>]*\sheight="([\d.]+)').firstMatch(svg);
  final svgWidth = double.tryParse(widthMatch?.group(1) ?? '') ?? InkPage.width;
  final svgHeight = double.tryParse(heightMatch?.group(1) ?? '');
  final k = InkPage.width / svgWidth;

  final strokes = <InkStroke>[];
  for (final m in RegExp(r'<path\b([^>]*)/?>', dotAll: true).allMatches(svg)) {
    final attrs = m.group(1)!;
    final d = RegExp(r'\sd="([^"]*)"').firstMatch(attrs)?.group(1);
    if (d == null) continue;
    final color = _parseColor(RegExp(r'stroke="([^"]*)"').firstMatch(attrs)?.group(1));
    final width = double.tryParse(
            RegExp(r'stroke-width="([\d.]+)').firstMatch(attrs)?.group(1) ?? '') ??
        5;
    final opacity = double.tryParse(RegExp(r'stroke-opacity="([\d.]+)').firstMatch(attrs)?.group(1) ?? '');

    // 每個 M 開始一筆新的筆畫
    for (final segment in d.split(RegExp(r'(?=M)')).where((s) => s.trim().isNotEmpty)) {
      final nums = RegExp(r'-?[\d.]+').allMatches(segment).map((x) => double.parse(x.group(0)!)).toList();
      final cmds = RegExp(r'[MQLC]').allMatches(segment).map((x) => x.group(0)!).toList();
      final points = <Offset>[];
      var i = 0;
      Offset? lastEnd;
      for (final c in cmds) {
        switch (c) {
          case 'M' || 'L':
            if (i + 1 >= nums.length) break;
            points.add(Offset(nums[i], nums[i + 1]));
            i += 2;
          case 'Q':
            if (i + 3 >= nums.length) break;
            final ctrl = Offset(nums[i], nums[i + 1]);
            if (points.isEmpty || points.last != ctrl) points.add(ctrl);
            lastEnd = Offset(nums[i + 2], nums[i + 3]);
            i += 4;
          case 'C':
            if (i + 5 >= nums.length) break;
            points.add(Offset(nums[i], nums[i + 1]));
            points.add(Offset(nums[i + 2], nums[i + 3]));
            lastEnd = Offset(nums[i + 4], nums[i + 5]);
            i += 6;
        }
      }
      if (lastEnd != null && points.last != lastEnd) points.add(lastEnd);
      if (points.isEmpty) continue;
      strokes.add(InkStroke(
        color: color,
        width: width * k,
        highlighter: opacity != null && opacity < 0.9,
        points: [for (final p in points) p * k],
      ));
    }
  }
  final page = InkPage(strokes: strokes, height: (svgHeight ?? InkPage.defaultHeight) * k);
  page.growToFit();
  return page;
}

int _parseColor(String? s) {
  if (s == null || !s.startsWith('#')) return 0xFF202020;
  final hex = s.substring(1);
  final v = int.tryParse(hex.length == 3 ? hex.split('').map((c) => '$c$c').join() : hex, radix: 16);
  if (v == null) return 0xFF202020;
  return hex.length == 8 ? v : 0xFF000000 | v;
}
