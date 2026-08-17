import 'package:flutter/material.dart';
export '../styles/k_chart_style.dart';

abstract class BaseChartRenderer<T> {
  double maxValue, minValue;
  late double scaleY;
  double topPadding;
  Rect chartRect;

  /// Strip trục giá dùng chung cho mọi panel (CHART_AXES.md §7) — cùng
  /// `left`/`right` với `BaseChartPainter.mPriceAxisRect` cho mọi renderer,
  /// chỉ khác `top`/`bottom` panel nào cũng tự lấy từ `chartRect` của mình.
  /// Renderer vẽ label giá trị vào ĐÂY thay vì đè lên `chartRect` (nội dung
  /// panel) như trước.
  Rect priceAxisRect;

  int fixedLength;
  Paint chartPaint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.high
    ..strokeWidth = 1.0
    ..color = Colors.red;
  Paint gridPaint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.high
    ..strokeWidth = 0.5
    ..color = Color(0xff4c5c74);

  BaseChartRenderer({
    required this.chartRect,
    required this.priceAxisRect,
    required this.maxValue,
    required this.minValue,
    required this.topPadding,
    required this.fixedLength,
    required Color gridColor,
  }) {
    if (maxValue == minValue) {
      maxValue *= 1.5;
      minValue /= 2;
    }
    scaleY = chartRect.height / (maxValue - minValue);
    gridPaint.color = gridColor;
  }

  double getY(double y) => (maxValue - y) * scaleY + chartRect.top;

  /// [verticalXs]: toạ độ x (screen space) của các đường lưới dọc — tính 1 lần
  /// bởi `BaseChartPainter` (time-tick planner) và dùng chung cho main/vol/
  /// secondary để lưới dọc luôn thẳng hàng giữa các panel (CHART_AXES.md I6).
  void drawGrid(Canvas canvas, int gridRows, List<double> verticalXs);

  void drawText(Canvas canvas, T data, double x);

  void drawVerticalText(Canvas canvas, TextStyle textStyle, int gridRows);

  void drawChart(T lastPoint, T curPoint, double lastX, double curX, Size size,
      Canvas canvas);

  /// Vẽ các đường trang trí phụ (vd đường tham chiếu ngang nét đứt) ở screen
  /// space, phía sau `drawChart`. No-op mặc định — renderer con nào cần thì override.
  void drawReferenceLines(Canvas canvas) {}

  void drawLine(double? lastPrice, double? curPrice, Canvas canvas, double lastX, double curX, Color color) {
    if (lastPrice == null || curPrice == null) {
      return;
    }
    double lastY = getY(lastPrice);
    double curY = getY(curPrice);
    canvas.drawLine(
      Offset(lastX, lastY),
      Offset(curX, curY),
      chartPaint..color = color,
    );
  }

  TextStyle getTextStyle(Color color) {
    return TextStyle(fontSize: 10.0, color: color);
  }
}
