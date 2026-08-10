import 'package:flutter/material.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/utils/index.dart';
import 'package:k_chart_jk/renderer/index.dart';

/// VolRenderer
///
/// Vẽ panel volume độc lập (không overlay trong main chart). Layout đi qua
/// `mVolRect` được `BaseChartPainter.initRect` tạo riêng ngay sau `mMainRect`,
/// trước các secondary panel và `mDateRect` (ở đáy cùng). Bật/tắt panel bằng
/// cờ `volHidden` ở `KChartWidget`.
///
/// Render:
///   - Cột vol xanh/đỏ theo `close > open`, alpha = alpha sẵn có của
///     `volumeStyle.upColor`/`dnColor` NHÂN với `chartStyle.volBarOpacity`
///     (không ghi đè) — set opacity thẳng trong `Color` hoặc qua
///     `volBarOpacity` đều dùng được, kết hợp được cả hai.
///   - 2 đường MA5/MA10 (lấy từ `MA5Volume`/`MA10Volume` đã tính trong
///     `DataUtil.calcVolumeMA`).
///   - Label `VOL : … MA5 : … MA10 : …` ở đầu panel.
///   - Nhãn max ở góc phải (min ≈ 0 nên bỏ qua để không đè đường lưới đáy).
class VolRenderer extends BaseChartRenderer<VolumeEntity> {
  final KChartStyle chartStyle;
  final KChartColors chartColors;
  late final double _volWidth;

  VolRenderer(
    Rect volRect,
    Rect priceAxisRect,
    double maxValue,
    double minValue,
    double topPadding,
    int fixedLength,
    this.chartStyle,
    this.chartColors,
  ) : super(
        chartRect: volRect,
        priceAxisRect: priceAxisRect,
        maxValue: maxValue,
        minValue: minValue,
        topPadding: topPadding,
        fixedLength: fixedLength,
        gridColor: chartColors.gridColor,
      ) {
    _volWidth = chartStyle.volWidth;
  }

  @override
  void drawChart(
    VolumeEntity lastPoint,
    VolumeEntity curPoint,
    double lastX,
    double curX,
    Size size,
    Canvas canvas,
  ) {
    if (curPoint.vol != 0) {
      final r = _volWidth / 2;
      final top = getY(curPoint.vol);
      final bottom = chartRect.bottom;
      final base = curPoint.close > curPoint.open
          ? chartColors.volumeStyle.upColor
          : chartColors.volumeStyle.dnColor;
      canvas.drawRect(
        Rect.fromLTRB(curX - r, top, curX + r, bottom),
        chartPaint
          ..color = base.withValues(alpha: base.a * chartStyle.volBarOpacity),
      );
    }
    if (lastPoint.MA5Volume != null &&
        lastPoint.MA5Volume != 0 &&
        curPoint.MA5Volume != null) {
      drawLine(
        lastPoint.MA5Volume,
        curPoint.MA5Volume,
        canvas,
        lastX,
        curX,
        chartColors.volumeStyle.ma5Color,
      );
    }
    if (lastPoint.MA10Volume != null &&
        lastPoint.MA10Volume != 0 &&
        curPoint.MA10Volume != null) {
      drawLine(
        lastPoint.MA10Volume,
        curPoint.MA10Volume,
        canvas,
        lastX,
        curX,
        chartColors.volumeStyle.ma10Color,
      );
    }
  }

  /// `getY` luôn chốt min = 0 (giả định volume không âm) để cột vol neo đáy panel.
  @override
  double getY(double y) =>
      (maxValue - y) * (chartRect.height / maxValue) + chartRect.top;

  @override
  TextStyle getTextStyle(Color color, {bool forceColor = false}) =>
      resolveTextStyle(
        chartColors.volumeStyle.textStyle,
        color,
        forceColor: forceColor,
      );

  @override
  void drawText(Canvas canvas, VolumeEntity data, double x) {
    final span = TextSpan(
      children: [
        TextSpan(
          text: 'VOL:${NumberUtil.formatCompact(data.vol)}  ',
          style: getTextStyle(chartColors.defaultTextColor),
        ),
        if (NumberUtil.checkNotNullOrZero(data.MA5Volume))
          TextSpan(
            text: 'MA5:${NumberUtil.formatCompact(data.MA5Volume!)}  ',
            style: getTextStyle(
              chartColors.volumeStyle.ma5Color,
              forceColor: true,
            ),
          ),
        if (NumberUtil.checkNotNullOrZero(data.MA10Volume))
          TextSpan(
            text: 'MA10:${NumberUtil.formatCompact(data.MA10Volume!)}',
            style: getTextStyle(
              chartColors.volumeStyle.ma10Color,
              forceColor: true,
            ),
          ),
      ],
    );
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(x, chartRect.top - topPadding));
  }

  /// Vẽ vào [priceAxisRect] (strip riêng bên phải, §7) — KHÔNG đè lên cột vol
  /// như trước khi có strip.
  @override
  void drawVerticalText(Canvas canvas, TextStyle textStyle, int gridRows) {
    final maxTp = TextPainter(
      text: TextSpan(
        text: NumberUtil.formatCompact(maxValue),
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    maxTp.paint(
      canvas,
      Offset(
        priceAxisRect.right - maxTp.width - chartStyle.space,
        chartRect.top - topPadding,
      ),
    );
    final minTp = TextPainter(
      text: TextSpan(
        text: NumberUtil.formatCompact(minValue),
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    minTp.paint(
      canvas,
      Offset(
        priceAxisRect.right - minTp.width - chartStyle.space,
        chartRect.bottom - minTp.height,
      ),
    );
  }

  @override
  void drawGrid(Canvas canvas, int gridRows, List<double> verticalXs) {
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
