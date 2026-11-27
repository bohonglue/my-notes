import 'dart:convert';
import 'dart:ui';

/// 手寫筆記的一筆筆畫。座標是「頁面座標」：頁面寬度固定為 [InkPage.width]，
/// 顯示時再依螢幕寬度縮放，所以手機和電腦上看起來比例一樣。
class InkStroke {
  InkStroke({required this.color, required this.width, List<Offset>? points, this.highlighter = false})
      : points = points ?? [];

  final int color;
  final double width;
  final bool highlighter;
  final List<Offset> points;

  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var l = points.first.dx, r = l, t = points.first.dy, b = t;
    for (final p in points) {
      if (p.dx < l) l = p.dx;
      if (p.dx > r) r = p.dx;
      if (p.dy < t) t = p.dy;
      if (p.dy > b) b = p.dy;
    }
    return Rect.fromLTRB(l, t, r, b).inflate(width / 2);
  }

  /// 點 [p] 是否在筆畫附近（橡皮擦用）。
  bool hitTest(Offset p, double radius) {
    final r = radius + width / 2;
    if (!bounds.inflate(radius).contains(p)) return false;
    if (points.length == 1) return (points.first - p).distance <= r;
    for (var i = 0; i < points.length - 1; i++) {
      if (_distToSegment(p, points[i], points[i + 1]) <= r) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'c': color,
        'w': width,
        if (highlighter) 'h': true,
        // 座標四捨五入到小數一位，存成扁平陣列以節省空間。
        'p': [for (final o in points) ...[_r(o.dx), _r(o.dy)]],
      };

  factory InkStroke.fromJson(Map<String, dynamic> j) {
    final flat = (j['p'] as List).cast<num>();
    return InkStroke(
      color: j['c'] as int,
      width: (j['w'] as num).toDouble(),
      highlighter: j['h'] == true,
      points: [for (var i = 0; i + 1 < flat.length; i += 2) Offset(flat[i].toDouble(), flat[i + 1].toDouble())],
    );
  }
}

class InkPage {
  InkPage({List<InkStroke>? strokes, this.height = defaultHeight}) : strokes = strokes ?? [];

  static const double width = 1080;
  static const double defaultHeight = 1600;

  final List<InkStroke> strokes;
  double height;

  bool get isEmpty => strokes.isEmpty;

  /// 讓頁面高度永遠比最下面的筆畫多出一段空白，往下寫就會自動變長。
  void growToFit() {
    var bottom = 0.0;
    for (final s in strokes) {
      final b = s.bounds.bottom;
      if (b > bottom) bottom = b;
    }
    final needed = bottom + 600;
    if (needed > height) height = needed;
  }

  String encode() => jsonEncode({
        'v': 1,
        'h': _r(height),
        's': [for (final s in strokes) s.toJson()],
      });

  static InkPage decode(String s) {
    if (s.isEmpty) return InkPage();
    final j = jsonDecode(s) as Map<String, dynamic>;
    return InkPage(
      height: (j['h'] as num?)?.toDouble() ?? defaultHeight,
      strokes: [for (final e in j['s'] as List) InkStroke.fromJson(e as Map<String, dynamic>)],
    );
  }
}

double _r(double v) => (v * 10).roundToDouble() / 10;

double _distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
  t = t.clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}
