import 'package:flutter/material.dart';

import '../k_chart_style.dart';

/// Icon preview cho 1 [CandleBodyStyle] — 2 nến mini (1 giảm bên trái, 1
/// tăng bên phải) vẽ trực tiếp bằng [Canvas]/[Paint] (KHÔNG dùng asset ảnh),
/// dùng cho UI chọn "Candle style" (dropdown/list trong Settings...).
///
/// Cách vẽ (đặc/rỗng, râu trên-dưới KHÔNG cắt ngang ruột thân khi rỗng) cố
/// tình đồng bộ với `MainRenderer.drawCandle` (`lib/renderer/main_renderer.dart`)
/// — icon phải giống hệt cách chart thật vẽ, không phải 1 hình minh họa rời rạc.
class CandleStyleIcon extends StatelessWidget {
  const CandleStyleIcon({
    super.key,
    required this.bodyStyle,
    this.upColor = const Color(0xFF0ABE82),
    this.dnColor = const Color(0xFFF54B55),
    this.size = const Size(28, 22),
  });

  /// Kiểu vẽ thân nến minh họa — xem [CandleBodyStyle].
  final CandleBodyStyle bodyStyle;

  /// màu nến tăng (nến bên phải).
  final Color upColor;

  /// màu nến giảm (nến bên trái).
  final Color dnColor;

  /// kích thước icon (mặc định 28x22 — vừa 1 dòng list/dropdown item).
  final Size size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: size,
      painter: _CandleStyleIconPainter(
        bodyStyle: bodyStyle,
        upColor: upColor,
        dnColor: dnColor,
      ),
    );
  }
}

class _CandleStyleIconPainter extends CustomPainter {
  _CandleStyleIconPainter({
    required this.bodyStyle,
    required this.upColor,
    required this.dnColor,
  });

  final CandleBodyStyle bodyStyle;
  final Color upColor;
  final Color dnColor;

  static const double _wickHalfWidth = 0.6;

  @override
  void paint(Canvas canvas, Size size) {
    final candleWidth = size.width * 0.26;
    final gap = size.width * 0.18;
    final leftX = size.width / 2 - gap / 2 - candleWidth / 2;
    final rightX = size.width / 2 + gap / 2 + candleWidth / 2;
    // Nến trái = giảm, nến phải = tăng — cùng thứ tự "2 nến cạnh nhau" của
    // ảnh mẫu candle-style picker (TradingView/Binance).
    _drawMiniCandle(canvas, size, leftX, candleWidth, dnColor, rising: false);
    _drawMiniCandle(canvas, size, rightX, candleWidth, upColor, rising: true);
  }

  void _drawMiniCandle(
    Canvas canvas,
    Size size,
    double cx,
    double candleWidth,
    Color color, {
    required bool rising,
  }) {
    final r = candleWidth / 2;
    final wickTop = size.height * 0.08;
    final wickBottom = size.height * 0.92;
    final bodyTop = size.height * 0.28;
    final bodyBottom = size.height * 0.72;
    final bodyRect = Rect.fromLTRB(cx - r, bodyTop, cx + r, bodyBottom);

    final hollow = switch (bodyStyle) {
      CandleBodyStyle.solid => false,
      CandleBodyStyle.hollowUp => rising,
      CandleBodyStyle.hollowDown => !rising,
      CandleBodyStyle.hollow => true,
    };

    final paint = Paint()
      ..isAntiAlias = true
      ..color = color
      ..style = PaintingStyle.fill;

    if (hollow) {
      // Râu chỉ vẽ 2 đoạn thò ra ngoài thân — KHÔNG cắt ngang ruột rỗng,
      // đồng bộ MainRenderer.drawCandle.
      canvas.drawRect(
        Rect.fromLTRB(cx - _wickHalfWidth, wickTop, cx + _wickHalfWidth, bodyTop),
        paint,
      );
      canvas.drawRect(
        Rect.fromLTRB(cx - _wickHalfWidth, bodyBottom, cx + _wickHalfWidth, wickBottom),
        paint,
      );
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawRect(bodyRect, paint);
    } else {
      canvas.drawRect(
        Rect.fromLTRB(cx - _wickHalfWidth, wickTop, cx + _wickHalfWidth, wickBottom),
        paint,
      );
      canvas.drawRect(bodyRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CandleStyleIconPainter oldDelegate) =>
      oldDelegate.bodyStyle != bodyStyle ||
      oldDelegate.upColor != upColor ||
      oldDelegate.dnColor != dnColor;
}
