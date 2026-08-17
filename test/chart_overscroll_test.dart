import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/k_chart_plus.dart';
import 'package:k_chart_jk/renderer/base_dimension.dart';

// Yêu cầu trực tiếp từ user: "chart scroll từ phải sang trái thì bonus thêm
// [khoảng trống] như chart của MEXC hay Binance" — user được phép kéo QUÁ vị
// trí nghỉ mặc định (đã có sẵn `xFrontPadding`) để tự lộ thêm khoảng trống
// bên phải. Kéo quá rồi thả tay: GIỮ NGUYÊN vị trí đã kéo, không tự bật về
// (không có hiệu ứng elastic/rubber-band) — xác nhận qua AskUserQuestion.
//
// Cơ chế: `BaseChartPainter.minScrollX` (cận dưới mới của `scrollX`, mặc
// định 0.0 — không đổi hành vi cũ) âm khi `xOverscrollPadding > 0`.
// `KChartWidget.xOverscrollPadding` mặc định 150 (luôn bật, không gắn với
// tính năng nào khác — khác `bidAskOverscrollPx` đã revert trước đó, lần này
// KHÔNG phụ thuộc bidPrice/askPrice).

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
  required double xOverscrollPadding,
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
    xOverscrollPadding: xOverscrollPadding,
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
  group('BaseChartPainter.minScrollX — overscroll bên phải, luôn bật (không gắn bid/ask)', () {
    testWidgets('xOverscrollPadding > 0 -> minScrollX âm sau khi layout', (tester) async {
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
                // mặc định xOverscrollPadding = 150 — không truyền gì thêm.
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(ChartPainter.minScrollX, lessThan(0.0));
    });

    testWidgets('xOverscrollPadding: 0 -> minScrollX = 0 (tắt hẳn, backward-compat)', (
      tester,
    ) async {
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
                xOverscrollPadding: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(ChartPainter.minScrollX, 0.0);
    });

    test('dựng painter trực tiếp — không cần bidPrice/askPrice vẫn có overscroll', () {
      final candles = _syntheticCandles(50);
      DataUtil.calculateAll(candles, [], []);
      final painter = _buildPainter(candles, xOverscrollPadding: 100);
      // set thẳng mPlotWidth, bỏ qua initRect() cho unit test cô lập — công
      // thức minScrollX chỉ cần mPlotWidth + scaleX, không cần full layout.
      painter.mPlotWidth = 300;
      painter.calculateValue();
      expect(ChartPainter.minScrollX, lessThan(0.0));
    });

    testWidgets(
      'user kéo (drag) thật quá vị trí nghỉ cũ (overscroll) không crash',
      (tester) async {
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
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Kéo LIÊN TỤC sang trái (dx âm) vượt xa mức overscroll cho phép —
        // clamp phải tự chặn ở minScrollX, không throw dù kéo quá tay.
        await tester.drag(find.byType(KChartWidget), const Offset(-500, 0));
        await tester.pump();
        await tester.drag(find.byType(KChartWidget), const Offset(-500, 0));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    // /code-review finding: `xOverscrollPadding` là double public không
    // validate non-negative. Nếu ai lỡ truyền ÂM + chart không có gì để
    // scroll (maxScrollX <= 0, vd data ít, vừa hết màn hình), minScrollX có
    // thể ra DƯƠNG — mọi `.clamp(minScrollX, maxScrollX)` (kể cả trong
    // `_restoreChartScaleFromWidget`, kích hoạt qua đổi `chartScale`) ném
    // `ArgumentError` (min > max), crash cả widget. Reproduce ĐÚNG kịch bản
    // review đã dùng: data ít (fit màn hình) + xOverscrollPadding âm + đổi
    // chartScale (didUpdateWidget -> _restoreChartScaleFromWidget).
    testWidgets(
      'xOverscrollPadding âm + chart không có gì để scroll + đổi chartScale -> không crash',
      (tester) async {
        final candles = _syntheticCandles(3); // ít, fit gọn màn hình 400px

        Widget build(KChartScaleState? chartScale) => MaterialApp(
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
                xOverscrollPadding: -50, // dùng sai — nhưng không được crash
                chartScale: chartScale,
              ),
            ),
          ),
        );

        await tester.pumpWidget(build(null));
        await tester.pumpAndSettle();
        // maxScrollX <= 0 lúc này (data ít, vừa hết màn hình) — đúng điều
        // kiện kích hoạt bug. Đổi chartScale -> didUpdateWidget ->
        // _restoreChartScaleFromWidget -> clamp(minScrollX, maxScrollX).
        await tester.pumpWidget(build(const KChartScaleState(scrollX: 5)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
