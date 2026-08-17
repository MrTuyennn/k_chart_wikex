import 'package:flutter/material.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';
import 'package:k_chart_jk/utils/index.dart';
import '../entity/macd_entity.dart';
import 'base_chart_renderer.dart';

class SecondaryRenderer extends BaseChartRenderer<MACDEntity> {
  SecondaryIndicator indicator;
  final KChartStyle chartStyle;
  final KChartColors chartColors;
  late final Paint _referencePaint;

  SecondaryRenderer(
    Rect mainRect,
    Rect priceAxisRect,
    double maxValue,
    double minValue,
    double topPadding,
    this.indicator,
    int fixedLength,
    this.chartStyle,
    this.chartColors,
  ) : super(
        chartRect: mainRect,
        priceAxisRect: priceAxisRect,
        maxValue: maxValue,
        minValue: minValue,
        topPadding: topPadding,
        fixedLength: fixedLength,
        gridColor: chartColors.gridColor,
      ) {
    _referencePaint = Paint()
      ..color = chartColors.defaultTextColor
          .withValues(alpha: chartColors.defaultTextColor.a * (90 / 255))
      ..strokeWidth = 0.5;
  }

  @override
  void drawChart(
    MACDEntity lastPoint,
    MACDEntity curPoint,
    double lastX,
    double curX,
    Size size,
    Canvas canvas,
  ) {
    indicator.drawChart(
      lastPoint,
      curPoint,
      lastX,
      curX,
      getY,
      canvas,
      chartColors,
    );
  }

  /// Vẽ các đường tham chiếu ngang nét đứt (indicator.referenceValues).
  /// Gọi 1 lần mỗi frame ở screen space, TRƯỚC vòng drawChart để vạch
  /// nằm phía sau đường indicator.
  @override
  void drawReferenceLines(Canvas canvas) {
    if (indicator.referenceValues.isEmpty) return;
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    for (final value in indicator.referenceValues) {
      final y = getY(value);
      // Gom toàn bộ các đoạn nét đứt vào 1 Path, vẽ bằng 1 lệnh drawPath
      // thay vì hàng chục/hàng trăm lệnh drawLine riêng lẻ mỗi frame.
      final path = Path();
      double x = 0;
      while (x < chartRect.width) {
        path.moveTo(x, y);
        path.lineTo(x + dashWidth, y);
        x += dashWidth + dashSpace;
      }
      canvas.drawPath(path, _referencePaint);
    }
  }

  /// Panel secondary dùng textStyle riêng của chính indicator đó
  /// (`indicator.indicatorStyle.textStyle`) — KHÔNG dùng chung `candleStyle.textStyle`
  /// của main chart, để mỗi panel (StochRSI/KDJ/MACD/...) tự chỉnh font/màu độc lập.
  @override
  TextStyle getTextStyle(Color color) =>
      resolveTextStyle(indicator.indicatorStyle.textStyle, color);

  @override
  void drawText(Canvas canvas, MACDEntity data, double x) {
    TextSpan? span = indicator.drawFigure(data, fixedLength, chartColors);
    if (span == null) return;
    TextPainter tp = TextPainter(text: span, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(x, chartRect.top - topPadding));
  }

  /// Vẽ vào [priceAxisRect] (strip riêng bên phải, §7) — KHÔNG đè lên panel
  /// indicator như trước khi có strip.
  ///
  /// `indicator.drawVerticalText` (13 lớp con — MACD/KDJ/RSI/...) tự vẽ theo
  /// `chartRect.width` coi như đang ở local x=0 (đúng khi mọi rect trong
  /// codebase này đều bắt đầu tại x=0 — thật vậy tới trước khi có strip giá).
  /// `priceAxisRect` giờ có `left != 0`, nên thay vì sửa cả 13 file indicator,
  /// dịch canvas sang gốc strip rồi đưa 1 rect "local" (left=0) — mọi công
  /// thức `chartRect.width - x` trong indicator vẫn đúng nguyên vẹn.
  @override
  void drawVerticalText(canvas, textStyle, int gridRows) {
    canvas.save();
    canvas.translate(priceAxisRect.left, 0);
    indicator.drawVerticalText(
      canvas: canvas,
      style: textStyle,
      maxValue: maxValue,
      minValue: minValue,
      fixedLength: fixedLength,
      chartRect: Rect.fromLTRB(
        0,
        chartRect.top - topPadding,
        priceAxisRect.width - chartStyle.space,
        chartRect.bottom,
      ),
    );
    canvas.restore();
  }

  @override
  void drawGrid(Canvas canvas, int gridRows, List<double> verticalXs) {
    // canvas.drawLine(Offset(0, chartRect.top), Offset(chartRect.width, chartRect.top), gridPaint); //hidden line
    canvas.drawLine(
      Offset(0, chartRect.bottom),
      Offset(chartRect.width, chartRect.bottom),
      gridPaint,
    );
    for (final x in verticalXs) {
      canvas.drawLine(
        Offset(x, chartRect.top - topPadding),
        Offset(x, chartRect.bottom),
        gridPaint,
      );
    }
  }
}
