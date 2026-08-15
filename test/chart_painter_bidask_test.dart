import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/k_chart_plus.dart';
import 'package:k_chart_jk/renderer/base_dimension.dart';

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

ChartPainter _buildPainter(
  List<KLineEntity> candles, {
  double? bidPrice = 100.4,
  double? askPrice = 100.6,
  String bidLabel = 'Bid',
  String askLabel = 'Ask',
}) {
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
    bidPrice: bidPrice,
    askPrice: askPrice,
    bidLabel: bidLabel,
    askLabel: askLabel,
  );
}

void main() {
  // /code-review finding — bidLabel/askLabel bị bỏ sót khỏi shouldRepaint,
  // khiến đổi locale (Bid/Ask -> Mua/Bán) không tự vẽ lại badge tới khi có
  // field khác đổi (vd tick livePrice tiếp theo) mới "ăn theo" — đúng lớp
  // lỗi mà comment về `chartColors.candleStyle.bodyStyle` ngay trong
  // shouldRepaint đã cảnh báo trước cho field tương tự.
  group('ChartPainter.shouldRepaint — bid/ask fields', () {
    test('bidPrice/askPrice change alone triggers repaint', () {
      final candles = _syntheticCandles(50);
      DataUtil.calculateAll(candles, [], []);
      final before = _buildPainter(candles, bidPrice: 100.4, askPrice: 100.6);
      final after = _buildPainter(candles, bidPrice: 100.3, askPrice: 100.7);
      expect(after.shouldRepaint(before), isTrue);
    });

    test('bidLabel/askLabel change alone triggers repaint (i18n locale switch)', () {
      final candles = _syntheticCandles(50);
      DataUtil.calculateAll(candles, [], []);
      final before = _buildPainter(candles, bidLabel: 'Bid', askLabel: 'Ask');
      final after = _buildPainter(candles, bidLabel: 'Mua', askLabel: 'Bán');
      expect(after.shouldRepaint(before), isTrue);
    });

    test('no change at all -> no repaint (avoid jank)', () {
      final candles = _syntheticCandles(50);
      DataUtil.calculateAll(candles, [], []);
      final a = _buildPainter(candles);
      final b = _buildPainter(candles);
      expect(b.shouldRepaint(a), isFalse);
    });
  });

  // /code-review finding — clamp vào [minY, maxY] chỉ sửa 1 hướng tràn
  // (if/else-if cũ) nên có thể vẫn tràn hướng còn lại khi mMainRect quá thấp
  // so với minGap giữa 2 badge. Verify bằng widget test thực (không chỉ đọc
  // code) — chart bị ép rất thấp, badge có spread lớn cần minGap rộng.
  group('KChartWidget — bid/ask badge does not crash on tight main-chart height', () {
    testWidgets('short-but-realistic mBaseHeight with wide spread does not throw', (tester) async {
      final candles = _syntheticCandles(200);
      DataUtil.calculateAll(candles, [], []);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                candles,
                const KChartStyle(),
                const KChartColors(),
                isTrendLine: false,
                detailBuilder: (e) => const SizedBox(),
                mBaseHeight: 120, // thấp nhưng còn hợp lý (không phải cực đoan)
                bidPrice: 99.0,
                askPrice: 101.0, // spread rộng, ép minGap phải dịch nhiều
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('bidPrice/askPrice pinned at top of visible price range', (tester) async {
      final candles = _syntheticCandles(200);
      DataUtil.calculateAll(candles, [], []);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                candles,
                const KChartStyle(),
                const KChartColors(),
                isTrendLine: false,
                detailBuilder: (e) => const SizedBox(),
                bidPrice: 100.9999,
                askPrice: 101.0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('bidPrice/askPrice pinned at bottom of visible price range', (tester) async {
      final candles = _syntheticCandles(200);
      DataUtil.calculateAll(candles, [], []);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                candles,
                const KChartStyle(),
                const KChartColors(),
                isTrendLine: false,
                detailBuilder: (e) => const SizedBox(),
                bidPrice: 99.0,
                askPrice: 99.0001,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
