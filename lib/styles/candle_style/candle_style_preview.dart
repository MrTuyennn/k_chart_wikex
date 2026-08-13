import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../k_chart_style.dart';

/// Preview lớn cho 1 kiểu vẽ main chart — nến (theo [CandleBodyStyle]) hoặc
/// line chart — vẽ trên 1 chuỗi giá tổng hợp CỐ ĐỊNH (không random, để
/// preview ổn định giữa các lần rebuild) hình sóng lên/xuống mô phỏng biểu
/// đồ thật, dùng cho UI chọn "Kiểu K-line" (settings picker...).
///
/// Cách vẽ nến (đặc/rỗng, râu trên-dưới KHÔNG cắt ngang ruột thân khi rỗng)
/// cố tình đồng bộ với `MainRenderer.drawCandle`
/// (`lib/renderer/main_renderer.dart`) — preview phải giống hệt cách chart
/// thật vẽ, không phải hình minh họa rời rạc.
class CandleStylePreview extends StatelessWidget {
  /// Preview candlestick — [bodyStyle] quyết định thân đặc/rỗng.
  const CandleStylePreview.candle({
    super.key,
    required this.bodyStyle,
    this.upColor = const Color(0xFF0ABE82),
    this.dnColor = const Color(0xFFF54B55),
    this.lineColor = const Color(0xFF217AFF),
    this.lineFillColors = const [Color(0x80217aff), Color(0x00217AFF)],
  }) : isLine = false;

  /// Preview line chart (đường + gradient tô dưới) — ứng với `isLine = true`
  /// của `KChartWidget`, KHÔNG liên quan [CandleBodyStyle].
  const CandleStylePreview.line({
    super.key,
    this.upColor = const Color(0xFF0ABE82),
    this.dnColor = const Color(0xFFF54B55),
    this.lineColor = const Color(0xFF217AFF),
    this.lineFillColors = const [Color(0x80217aff), Color(0x00217AFF)],
  }) : bodyStyle = null,
       isLine = true;

  /// null khi [isLine] = true (line chart không có khái niệm thân nến).
  final CandleBodyStyle? bodyStyle;
  final bool isLine;

  /// màu nến tăng / đường & gradient line chart — cùng ý nghĩa [CandleStyle].
  final Color upColor;
  final Color dnColor;
  final Color lineColor;
  final List<Color> lineFillColors;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite, // constrain() theo box cha (vd Container cao cố định bọc ngoài)
      painter: _CandleStylePreviewPainter(
        bodyStyle: bodyStyle,
        isLine: isLine,
        upColor: upColor,
        dnColor: dnColor,
        lineColor: lineColor,
        lineFillColors: lineFillColors,
      ),
    );
  }
}

class _CandleStylePreviewPainter extends CustomPainter {
  _CandleStylePreviewPainter({
    required this.bodyStyle,
    required this.isLine,
    required this.upColor,
    required this.dnColor,
    required this.lineColor,
    required this.lineFillColors,
  });

  final CandleBodyStyle? bodyStyle;
  final bool isLine;
  final Color upColor;
  final Color dnColor;
  final Color lineColor;
  final List<Color> lineFillColors;

  /// Chuỗi giá tương đối (0..1, không phải giá thật) — hình sóng
  /// đỉnh-đáy-đỉnh xen kẽ tăng/giảm cục bộ, đủ đa dạng để demo rõ từng kiểu
  /// vẽ (không phải 1 xu hướng đơn điệu 1 chiều).
  static const List<double> _closes = [
    0.45,
    0.40,
    0.55,
    0.63,
    0.70,
    0.64,
    0.58,
    0.48,
    0.36,
    0.26,
    0.16,
    0.11,
    0.20,
    0.14,
    0.24,
    0.40,
    0.55,
    0.68,
    0.80,
    0.72,
    0.60,
    0.50,
    0.42,
    0.37,
  ];

  double _yOf(double v, double minV, double range, Size size) {
    final vPad = size.height * 0.12;
    final t = (v - minV) / range;
    return size.height - vPad - t * (size.height - vPad * 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final minV = _closes.reduce(math.min);
    final maxV = _closes.reduce(math.max);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    if (isLine) {
      _paintLine(canvas, size, minV, range);
    } else {
      _paintCandles(canvas, size, minV, range);
    }
  }

  void _paintLine(Canvas canvas, Size size, double minV, double range) {
    final n = _closes.length;
    final stepX = size.width / (n - 1);
    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = stepX * i;
      final y = _yOf(_closes[i], minV, range, size);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fillPath = Path.from(path)
      ..lineTo(stepX * (n - 1), size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: lineFillColors,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  void _paintCandles(Canvas canvas, Size size, double minV, double range) {
    final n = _closes.length;
    final step = size.width / n;
    final candleWidth = step * 0.6;
    final wickHalfWidth = (step * 0.06).clamp(0.6, 2.0);
    final paint = Paint()..isAntiAlias = true;
    final style = bodyStyle!;

    for (var i = 0; i < n; i++) {
      final cx = step * i + step / 2;
      final openV = i == 0 ? _closes[0] : _closes[i - 1];
      final closeV = _closes[i];
      final rising = closeV > openV;

      final bodyTopY = _yOf(math.max(openV, closeV), minV, range, size);
      final bodyBottomY = _yOf(math.min(openV, closeV), minV, range, size);
      // Râu nhô thêm 1 đoạn nhỏ, xen kẽ theo index để trông tự nhiên như
      // dữ liệu thật (không phải mọi nến cùng độ dài râu).
      final wickExtra = size.height * (0.02 + (i % 3) * 0.012);
      final wickTopY = bodyTopY - wickExtra;
      final wickBottomY = bodyBottomY + wickExtra;

      final bodyRect = Rect.fromLTRB(
        cx - candleWidth / 2,
        bodyTopY,
        cx + candleWidth / 2,
        math.max(bodyBottomY, bodyTopY + 1), // tối thiểu 1px, tránh biến mất khi open≈close
      );

      final color = rising ? upColor : dnColor;
      // Nguồn sự thật duy nhất: CandleBodyStyleX.isHollow (k_chart_style.dart)
      // — dùng chung với MainRenderer.drawCandle, không tự chép switch riêng.
      final hollow = style.isHollow(rising: rising);

      paint
        ..color = color
        ..style = PaintingStyle.fill;

      if (hollow) {
        if (bodyRect.top > wickTopY) {
          canvas.drawRect(
            Rect.fromLTRB(cx - wickHalfWidth, wickTopY, cx + wickHalfWidth, bodyRect.top),
            paint,
          );
        }
        if (wickBottomY > bodyRect.bottom) {
          canvas.drawRect(
            Rect.fromLTRB(cx - wickHalfWidth, bodyRect.bottom, cx + wickHalfWidth, wickBottomY),
            paint,
          );
        }
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawRect(bodyRect, paint);
      } else {
        canvas.drawRect(
          Rect.fromLTRB(cx - wickHalfWidth, wickTopY, cx + wickHalfWidth, wickBottomY),
          paint,
        );
        canvas.drawRect(bodyRect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CandleStylePreviewPainter oldDelegate) =>
      oldDelegate.bodyStyle != bodyStyle ||
      oldDelegate.isLine != isLine ||
      oldDelegate.upColor != upColor ||
      oldDelegate.dnColor != dnColor ||
      oldDelegate.lineColor != lineColor;
}
