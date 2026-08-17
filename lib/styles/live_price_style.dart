import 'package:flutter/material.dart';

/// Style cho now-price (đường + label giá hiện tại, vẽ trong
/// `ChartPainter.drawNowPrice`) — tách khỏi `KChartColors` thành model riêng,
/// cùng convention với `CandleStyle`/`VolumeStyle`/`DepthChartStyle`.
class LivePriceStyle {
  /// màu khi giá hiện tại (`livePrice ?? datas.last.close`) >= open nến cuối.
  final Color upColor;

  /// màu khi giá hiện tại < open nến cuối.
  final Color dnColor;

  /// text style cho label giá trong badge now-price — [upColor]/[dnColor]
  /// CHỈ tô nền badge + đường kẻ, KHÔNG ảnh hưởng màu chữ; màu chữ luôn lấy
  /// từ `textStyle.color` (mặc định trắng, vì nền badge giờ là màu đặc —
  /// dùng chung `upColor`/`dnColor` cho cả chữ sẽ khiến chữ gần như vô hình
  /// trên nền cùng màu).
  final TextStyle textStyle;

  const LivePriceStyle({
    this.upColor = const Color(0xFF0ECB81),
    this.dnColor = const Color(0xFFF6465D),
    this.textStyle = const TextStyle(fontSize: 10, color: Colors.white),
  });
}

/// Badge "flag" (nền bo góc + mũi tên nhỏ trỏ sang trái) cho now-price —
/// convert từ `assets/Number.svg` (viewBox `0 0 54 14`: rect nền
/// `x=2.27344 width=51 rx=2`, path mũi tên trỏ trái ở mép trái badge, cả 2
/// dùng CHUNG hệ toạ độ viewBox). Độc lập, KHÔNG tự gắn vào `KChartWidget` —
/// `ChartPainter.drawNowPrice` gọi trực tiếp `paint()` lên canvas thật của nó
/// (không qua widget `CustomPaint`), đọc màu qua `KChartColors.livePriceStyle`.
///
/// Mũi tên trỏ trái khớp đúng ngữ nghĩa "chỉ vào đường giá" khi badge đứng ở
/// mép PHẢI chart (`VerticalTextAlignment.right`, mặc định) — trỏ vào nội
/// dung chart. Nếu dùng `VerticalTextAlignment.left`, mũi tên sẽ trỏ ra ngoài
/// thay vì vào chart (hạn chế của asset gốc, chưa có bản mirror).
class LivePriceBadgePainter extends CustomPainter {
  final Color color;

  const LivePriceBadgePainter({required this.color});

  /// Kích thước viewBox gốc của `Number.svg` — mọi toạ độ literal bên dưới
  /// (rect lẫn path mũi tên) lấy nguyên từ SVG, tính theo hệ toạ độ này.
  static const double _viewBoxWidth = 54.0;
  static const double _viewBoxHeight = 14.0;

  static final Path _arrowPath = Path()
    ..moveTo(0.486069, 6.1578)
    ..cubicTo(-0.162253, 6.53211, -0.162253, 7.46789, 0.486069, 7.8422)
    ..lineTo(2.06862, 8.75588)
    ..cubicTo(2.71694, 9.13019, 3.52734, 8.6623, 3.52734, 7.91368)
    ..lineTo(3.52734, 6.08632)
    ..cubicTo(3.52734, 5.3377, 2.71694, 4.86981, 2.06862, 5.24412)
    ..lineTo(0.486069, 6.1578)
    ..close();

  static final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _arrowPaint = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / _viewBoxWidth;
    final scaleY = size.height / _viewBoxHeight;

    _bgPaint.color = color;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(2.27344 * scaleX, 0, 51 * scaleX, size.height),
        bottomRight: Radius.circular(2 * scaleX),
        bottomLeft: Radius.circular(2 * scaleX),
        topLeft: Radius.circular(2 * scaleX),
        topRight: Radius.circular(2 * scaleX),
      ),
      _bgPaint,
    );

    _arrowPaint.color = color;

    canvas.save();
    canvas.scale(scaleX, scaleY);
    canvas.drawPath(_arrowPath, _arrowPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LivePriceBadgePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
