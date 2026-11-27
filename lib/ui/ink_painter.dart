import 'package:flutter/material.dart';

import '../data/ink.dart';

/// 畫出手寫頁面。[scale] = 螢幕像素 / 頁面座標。
class InkPainter extends CustomPainter {
  InkPainter({required this.strokes, required this.scale, this.current, this.darkMode = false, super.repaint});

  final List<InkStroke> strokes;

  /// 回傳「正在畫的那一筆」，每次重畫時讀取。
  final InkStroke? Function()? current;
  final double scale;

  /// 深色主題時，把接近黑色的筆畫畫成接近白色，才看得到。
  final bool darkMode;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    for (final s in strokes) {
      _draw(canvas, s);
    }
    final cur = current?.call();
    if (cur != null) _draw(canvas, cur);
    canvas.restore();
  }

  void _draw(Canvas canvas, InkStroke s) {
    if (s.points.isEmpty) return;
    var color = Color(s.color);
    if (darkMode && color.computeLuminance() < 0.08) color = const Color(0xFFE8E8E8);
    if (s.highlighter) color = color.withValues(alpha: 0.35);
    final paint = Paint()
      ..color = color
      ..strokeWidth = s.width
      ..strokeCap = s.highlighter ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final pts = s.points;
    if (pts.length == 1) {
      canvas.drawCircle(pts.first, s.width / 2, paint..style = PaintingStyle.fill);
      return;
    }
    // 用每兩點的中點當端點、原始點當控制點畫二次曲線，讓線條平滑。
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(InkPainter old) => true;
}

/// 首頁卡片上的手寫縮圖：只顯示有筆畫的區域。
class InkThumbnail extends StatelessWidget {
  const InkThumbnail({super.key, required this.page, this.maxHeight = 160});

  final InkPage page;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (page.isEmpty) return const SizedBox.shrink();
    var bounds = page.strokes.first.bounds;
    for (final s in page.strokes.skip(1)) {
      bounds = bounds.expandToInclude(s.bounds);
    }
    bounds = bounds.inflate(10);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      var scale = c.maxWidth / bounds.width;
      if (bounds.height * scale > maxHeight) scale = maxHeight / bounds.height;
      return ClipRect(
        child: SizedBox(
          width: c.maxWidth,
          height: bounds.height * scale,
          child: CustomPaint(
            painter: _OffsetInkPainter(page.strokes, scale, bounds.topLeft, dark),
          ),
        ),
      );
    });
  }
}

class _OffsetInkPainter extends CustomPainter {
  _OffsetInkPainter(this.strokes, this.scale, this.origin, this.dark);

  final List<InkStroke> strokes;
  final double scale;
  final Offset origin;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    canvas.translate(-origin.dx, -origin.dy);
    InkPainter(strokes: strokes, scale: 1, darkMode: dark).paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OffsetInkPainter old) => old.strokes != strokes || old.scale != scale;
}
