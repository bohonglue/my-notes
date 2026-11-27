import 'package:flutter/material.dart';

/// 筆記可選的背景色（淺色主題用）。深色主題會自動調暗。
const noteColors = <int>[
  0xFFFFF59D, // 黃
  0xFFFFCC80, // 橘
  0xFFF8BBD0, // 粉紅
  0xFFEF9A9A, // 紅
  0xFFC5E1A5, // 綠
  0xFF80CBC4, // 青
  0xFF90CAF9, // 藍
  0xFFCE93D8, // 紫
  0xFFBCAAA4, // 咖啡
  0xFFCFD8DC, // 灰
];

Color? noteBackground(BuildContext context, int? color) {
  if (color == null) return null;
  final c = Color(color);
  if (Theme.of(context).brightness == Brightness.dark) {
    return Color.alphaBlend(c.withValues(alpha: 0.28), const Color(0xFF1E1E1E));
  }
  return c;
}

Future<int?> pickNoteColor(BuildContext context, int? current) {
  return showModalBottomSheet<int?>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _swatch(ctx, null, current == null),
            for (final c in noteColors) _swatch(ctx, c, current == c),
          ],
        ),
      ),
    ),
  );
}

Widget _swatch(BuildContext ctx, int? color, bool selected) {
  return InkWell(
    customBorder: const CircleBorder(),
    // 用 -1 代表「預設顏色」，因為 pop(null) 跟「取消」分不出來。
    onTap: () => Navigator.pop(ctx, color ?? -1),
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color == null ? Theme.of(ctx).colorScheme.surface : noteBackground(ctx, color),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).dividerColor,
          width: selected ? 3 : 1,
        ),
      ),
      child: color == null ? const Icon(Icons.format_color_reset, size: 20) : null,
    ),
  );
}
