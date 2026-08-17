import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/k_chart_plus.dart';
import 'package:k_chart_jk/renderer/base_dimension.dart';

// Yêu cầu trực tiếp từ user: "cho axisY rộng ra tí" — tăng công thức
// `updatePriceAxisWidth` (BaseChartPainter, §7.6 CHART_AXES.md): offset cộng
// thêm 14→20, cận dưới 48→56, cận trên 96→104 (vẫn làm tròn lên bội số 8).

List<KLineEntity> _syntheticCandles(int count) {
  final base = DateTime(2024, 1, 1).millisecondsSinceEpoch;
  return List.generate(
    count,
    (i) => KLineEntity.fromCustom(
      time: base + i * 3600000,
      open: 100,
      high: 101,
      low: 99,
      close: 100.5,
      vol: 1,
      amount: 100,
    ),
  );
}

ChartPainter _buildPainter(List<KLineEntity> candles) {
  return ChartPainter(
    const KChartStyle(),
    const KChartColors(),
    lines: const [],
    isTrendLine: false,
    selectY: 0,
    sink: StreamController<InfoWindowEntity?>.broadcast().sink,
    datas: candles,
    scaleX: 1.0,
    scaleY: 1.0,
    scrollX: 0.0,
    isLongPress: false,
    selectX: 0,
    xFrontPadding: 100,
    baseDimension: BaseDimension(
      mBaseHeight: 300,
      mSecondaryHeight: 60,
      volHidden: false,
      secondaryIndicators: const [],
      mainIndicators: const [],
    ),
    priceAxisWidthCache: PriceAxisWidthCache(),
    timeTickPlanner: TimeTickPlanner(),
    verticalTextAlignment: VerticalTextAlignment.right,
  );
}

void main() {
  group('BaseChartPainter.updatePriceAxisWidth — cận mới (56–104, offset +20)', () {
    test('maxLabelWidth nhỏ -> kẹp ở cận dưới MỚI (56), không còn 48', () {
      final painter = _buildPainter(_syntheticCandles(10));
      painter.updatePriceAxisWidth(0.0);
      expect(painter.priceAxisWidth, 56.0);
    });

    test('maxLabelWidth lớn -> kẹp ở cận trên MỚI (104), không còn 96', () {
      final painter = _buildPainter(_syntheticCandles(10));
      painter.updatePriceAxisWidth(500.0);
      expect(painter.priceAxisWidth, 104.0);
    });

    test('maxLabelWidth vừa -> maxLabelWidth + 20, làm tròn lên bội số 8', () {
      final painter = _buildPainter(_syntheticCandles(10));
      // 50 + 20 = 70 -> làm tròn lên bội số 8 gần nhất = 72.
      painter.updatePriceAxisWidth(50.0);
      expect(painter.priceAxisWidth, 72.0);
    });
  });
}
