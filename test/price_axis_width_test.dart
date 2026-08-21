import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/k_chart_plus.dart';
import 'package:k_chart_jk/renderer/base_dimension.dart';

// Yêu cầu trực tiếp từ user: "chỉnh thêm tí nữa cho ngắn hơn" — giảm thêm
// công thức `updatePriceAxisWidth` (BaseChartPainter, §7.6 CHART_AXES.md):
// offset cộng thêm 12→4, cận trên 88→80 (cận dưới giữ 40, vẫn làm tròn lên
// bội số 8). Lịch sử: 14/48/96 (gốc) → 20/56/104 (rộng ra) → 16/48/96 (hẹp
// lại) → 12/40/88 (hẹp thêm) → 4/40/80 (hẹp thêm lần nữa).

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
  group('BaseChartPainter.updatePriceAxisWidth — cận mới (40–80, offset +4)', () {
    test('maxLabelWidth nhỏ -> kẹp ở cận dưới (40)', () {
      final painter = _buildPainter(_syntheticCandles(10));
      painter.updatePriceAxisWidth(0.0);
      expect(painter.priceAxisWidth, 40.0);
    });

    test('maxLabelWidth lớn -> kẹp ở cận trên MỚI (80), không còn 88', () {
      final painter = _buildPainter(_syntheticCandles(10));
      painter.updatePriceAxisWidth(500.0);
      expect(painter.priceAxisWidth, 80.0);
    });

    test('maxLabelWidth vừa -> maxLabelWidth + 4, làm tròn lên bội số 8', () {
      final painter = _buildPainter(_syntheticCandles(10));
      // 50 + 4 = 54 -> làm tròn lên bội số 8 gần nhất = 56.
      painter.updatePriceAxisWidth(50.0);
      expect(painter.priceAxisWidth, 56.0);
    });
  });
}
