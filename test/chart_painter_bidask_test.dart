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
  double? livePrice,
  double mBaseHeight = 300,
  VerticalTextAlignment verticalTextAlignment = VerticalTextAlignment.right,
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
      mBaseHeight: mBaseHeight,
      mSecondaryHeight: 60,
      volHidden: false,
      secondaryIndicators: const [],
      mainIndicators: const [],
    ),
    priceAxisWidthCache: PriceAxisWidthCache(),
    timeTickPlanner: TimeTickPlanner(),
    verticalTextAlignment: verticalTextAlignment,
    bidPrice: bidPrice,
    askPrice: askPrice,
    bidLabel: bidLabel,
    askLabel: askLabel,
    livePrice: livePrice,
  );
}

/// Pump [painter] qua `CustomPaint` rồi bắt TOÀN BỘ `RRect` thật đã vẽ, quy
/// đổi về toạ độ tuyệt đối bằng cách tự cộng dồn `canvas.translate` (badge
/// live price vẽ qua `LivePriceBadgePainter` sau 1 lần
/// `canvas.translate(offsetX, top-paddingY)` trong `drawNowPrice`, nên RRect
/// nền badge ghi lại là toạ độ CỤC BỘ — CẢ x LẪN y — cần cộng lại offset đó
/// mới ra đúng toạ độ tuyệt đối để so với box Ask/Bid, vẽ bằng
/// `Rect.fromLTWH` tuyệt đối, không qua translate).
Future<List<RRect>> _capturePaintedRRects(
  WidgetTester tester,
  ChartPainter painter, {
  Size size = const Size(400, 400),
}) async {
  // Key riêng — Scaffold/Material tự chèn thêm 1 CustomPaint nội bộ (kích
  // thước full màn hình test) đứng TRƯỚC widget của mình trong cây, nên
  // `find.byType(CustomPaint).first` bắt nhầm cái đó.
  const paintKey = ValueKey('bidask-under-test');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomPaint(key: paintKey, painter: painter, size: size),
      ),
    ),
  );

  final List<double> dxStack = [0.0];
  final List<double> dyStack = [0.0];
  final List<RRect> globalRRects = [];
  expect(
    find.byKey(paintKey),
    paints..everything((Symbol method, List<dynamic> arguments) {
      if (method == #save) {
        dxStack.add(dxStack.last);
        dyStack.add(dyStack.last);
      } else if (method == #restore) {
        if (dxStack.length > 1) dxStack.removeLast();
        if (dyStack.length > 1) dyStack.removeLast();
      } else if (method == #translate) {
        dxStack[dxStack.length - 1] += arguments[0] as double;
        dyStack[dyStack.length - 1] += arguments[1] as double;
      } else if (method == #drawRRect) {
        final rrect = (arguments[0] as RRect).shift(
          Offset(dxStack.last, dyStack.last),
        );
        globalRRects.add(rrect);
      }
      return true;
    }),
  );
  return globalRRects;
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

  // Khóa cứng bất biến (2026-08-17, đổi hướng lần 2 theo yêu cầu trực tiếp
  // từ user — "lộn nằm bên trái live price nhưng canh center giúp tôi và di
  // chuyển theo live price"): badge live price (drawNowPrice, LUÔN vẽ độc
  // lập, KHÔNG đổi vị trí/hành vi) vẫn center đúng theo đường dashed; box
  // Ask/Bid (drawBidAsk, tách riêng khỏi live price) đặt NGAY BÊN TRÁI badge
  // đó, CÙNG tâm dọc, không đè lên nhau — "di chuyển theo live price" đã tự
  // đúng vì cả 2 dùng chung `centerY` tính lại mỗi frame theo giá hiện tại,
  // không cần cơ chế riêng. Test dựng đúng RRect thật đã vẽ qua `paints`
  // matcher, quy đổi về toạ độ tuyệt đối bằng cách tự cộng dồn
  // `canvas.translate` (badge vẽ qua `LivePriceBadgePainter`, dùng toạ độ
  // cục bộ sau 1 lần translate).
  group(
    'drawNowPrice + drawBidAsk — badge center theo line & giữ nguyên vị trí, box Ask/Bid nằm bên trái (khóa cứng)',
    () {
      testWidgets(
        'badge center đúng Y đường dashed; box Ask/Bid nằm ngay bên trái, cùng tâm dọc, không chồng lấn',
        (tester) async {
          final candles = _syntheticCandles(50);
          DataUtil.calculateAll(candles, [], []);
          // livePrice không set -> value rơi về datas.last.close (100.5, cố
          // định bởi _syntheticCandles) — giá trị biết trước, không cần đoán.
          final painter = _buildPainter(candles, bidPrice: 100.4, askPrice: 100.6);

          final globalRRects = await _capturePaintedRRects(tester, painter);

          // Thứ tự vẽ cố định: drawNowPrice chạy TRƯỚC drawBidAsk trong
          // paint() (base_chart_painter.dart) -> nền badge live price vẽ
          // trước, rồi Ask, rồi Bid. Badge chỉ 1 drawRRect (mũi tên vẽ bằng
          // drawPath, không tính).
          expect(
            globalRRects.length,
            3,
            reason: 'badge live price (1) + Ask (1) + Bid (1) — có cái khác lạ '
                'nghĩa là có code path drawRRect mới cần xem lại test này.',
          );
          final badgeRect = globalRRects[0].outerRect;
          final askRect = globalRRects[1].outerRect;
          final bidRect = globalRRects[2].outerRect;

          // Badge center đúng theo đường dashed — tính lại từ CHÍNH painter
          // đã paint xong (mMainRect đã set). scaleY=1.0, offsetY=0.0 (mặc
          // định, _buildPainter không override offsetY) nên _applyScaleY
          // chỉ còn là clamp(mMainRect.top, mMainRect.bottom) — public,
          // tính lại được từ ngoài mà không cần gọi hàm private.
          final double expectedLineY = painter
              .getMainY(100.5)
              .clamp(painter.mMainRect.top, painter.mMainRect.bottom);
          final double badgeCenterY = (badgeRect.top + badgeRect.bottom) / 2;
          expect(badgeCenterY, closeTo(expectedLineY, 0.5));

          // Box Ask/Bid nằm NGAY BÊN TRÁI badge, không chồng lấn (mép phải
          // box <= mép trái badge), và CÙNG tâm dọc với badge (yêu cầu trực
          // tiếp: "liveprice vẫn giữ nguyên" — box không kéo lệch badge đi
          // đâu, chỉ đứng cạnh).
          expect(askRect.right, lessThanOrEqualTo(badgeRect.left + 0.5));
          expect(bidRect.right, lessThanOrEqualTo(badgeRect.left + 0.5));
          final double boxCenterY = (askRect.top + bidRect.bottom) / 2;
          expect(boxCenterY, closeTo(badgeCenterY, 0.5));
        },
      );

      // Yêu cầu trực tiếp từ user (đợt sau): "luôn luôn căn giữa so với live
      // price trong mọi case" — trước đây box bị kẹp lại vào [minY, maxY]
      // (mMainRect) khi giá sát đỉnh/đáy dải hiển thị, làm lệch tâm so với
      // badge trong đúng case này. Đã bỏ hẳn phần kẹp đó trong drawBidAsk —
      // 2 test dưới đây dựng ĐÚNG giá pinned top/bottom (case trước đây từng
      // bị lệch) để khoá cứng: dù giá sát biên, box vẫn PHẢI center chính
      // xác theo badge, không còn sai số do clamp.
      for (final pinned in [
        (
          name: 'giá pinned SÁT ĐỈNH dải hiển thị (livePrice ≈ mMainHighMaxValue)',
          livePrice: 100.9999,
        ),
        (
          name: 'giá pinned SÁT ĐÁY dải hiển thị (livePrice ≈ mMainLowMinValue)',
          livePrice: 99.0001,
        ),
      ]) {
        testWidgets(
          '${pinned.name}: box Ask/Bid vẫn center chính xác theo badge, mBaseHeight thấp',
          (tester) async {
            final candles = _syntheticCandles(50);
            DataUtil.calculateAll(candles, [], []);
            // mBaseHeight thấp (120, giống test crash-smoke "tight main-chart
            // height") — trước đây đây CHÍNH LÀ tổ hợp dễ kích hoạt nhánh
            // clamp nhất (main chart thấp + giá sát biên).
            final painter = _buildPainter(
              candles,
              bidPrice: 100.4,
              askPrice: 100.6,
              livePrice: pinned.livePrice,
              mBaseHeight: 120,
            );

            final globalRRects = await _capturePaintedRRects(tester, painter);
            expect(globalRRects.length, 3);
            final badgeRect = globalRRects[0].outerRect;
            final askRect = globalRRects[1].outerRect;
            final bidRect = globalRRects[2].outerRect;

            final double badgeCenterY = (badgeRect.top + badgeRect.bottom) / 2;
            final double boxCenterY = (askRect.top + bidRect.bottom) / 2;
            expect(
              boxCenterY,
              closeTo(badgeCenterY, 0.5),
              reason: 'box Ask/Bid phải center CHÍNH XÁC theo badge kể cả khi '
                  'giá sát đỉnh/đáy dải hiển thị — không còn bị kẹp lệch tâm '
                  'nữa (yêu cầu "luôn luôn căn giữa... trong mọi case").',
            );
          },
        );
      }

      // /code-review finding: đặt box CỐ ĐỊNH bên trái badge (bất kể
      // alignment) làm box vẽ hoàn toàn ngoài canvas (x âm, vô hình) khi
      // đóng `left` — badge lúc đó đã sát mép trái, không còn chỗ lùi thêm
      // về bên trái. Test này khoá cứng: đóng `left` thì box phải nằm bên
      // PHẢI badge (không phải trái) và luôn trong canvas (x >= 0).
      testWidgets(
        'verticalTextAlignment.left: box Ask/Bid nằm bên PHẢI badge (không tràn ra ngoài canvas)',
        (tester) async {
          final candles = _syntheticCandles(50);
          DataUtil.calculateAll(candles, [], []);
          final painter = _buildPainter(
            candles,
            bidPrice: 100.4,
            askPrice: 100.6,
            verticalTextAlignment: VerticalTextAlignment.left,
          );

          final globalRRects = await _capturePaintedRRects(tester, painter);
          expect(globalRRects.length, 3);
          final badgeRect = globalRRects[0].outerRect;
          final askRect = globalRRects[1].outerRect;
          final bidRect = globalRRects[2].outerRect;

          // Trong canvas — không âm (trước bug: left ~ -111, vẽ ngoài vùng
          // clip x=[0, size.width], vô hình).
          expect(askRect.left, greaterThanOrEqualTo(0.0));
          expect(bidRect.left, greaterThanOrEqualTo(0.0));

          // Box nằm bên PHẢI badge (mép trái box >= mép phải badge), không
          // chồng lấn — mirror đúng hướng so với case `right` (box bên trái
          // badge).
          expect(askRect.left, greaterThanOrEqualTo(badgeRect.right - 0.5));
          expect(bidRect.left, greaterThanOrEqualTo(badgeRect.right - 0.5));

          final double badgeCenterY = (badgeRect.top + badgeRect.bottom) / 2;
          final double boxCenterY = (askRect.top + bidRect.bottom) / 2;
          expect(boxCenterY, closeTo(badgeCenterY, 0.5));
        },
      );

      // Yêu cầu trực tiếp từ user: "đẩy live-price ra ngoài nằm trên axis Y
      // luôn" — badge now-price (đóng `right`, mặc định) giờ đặt chủ yếu
      // TRÊN price-axis strip (bên phải `mPlotWidth`), chỉ lấn nhẹ vào plot
      // đúng bằng `space` để mũi tên "chạm" đường dashed — khác trước (badge
      // nằm gọn trong `mPlotWidth`, cách mép `space` px).
      testWidgets(
        'verticalTextAlignment.right (mặc định): badge now-price nằm chủ yếu trên price-axis strip',
        (tester) async {
          final candles = _syntheticCandles(50);
          DataUtil.calculateAll(candles, [], []);
          final painter = _buildPainter(candles, bidPrice: null, askPrice: null);

          final globalRRects = await _capturePaintedRRects(tester, painter);
          // Không có bidPrice/askPrice -> chỉ 1 RRect (nền badge; mũi tên vẽ
          // bằng drawPath, không tính).
          expect(globalRRects.length, 1);
          final badgeRect = globalRRects[0].outerRect;

          // Mép trái badge chỉ lấn nhẹ vào plot (tối đa đúng `space`=5px
          // trước mPlotWidth — thực tế luôn NHỎ HƠN do hình mũi tên trong
          // LivePriceBadgePainter tự co theo scaleX, không bao giờ vượt quá
          // `space`), phần LỚN thân badge nằm bên phải mPlotWidth (trên
          // price-axis strip) — trước đây badge nằm gọn trong mPlotWidth
          // (mép phải cách mPlotWidth đúng space, mép trái xa hơn nữa về bên
          // trái theo độ dài text) nên assertion này trước đây sẽ fail.
          // Dùng ngưỡng RỘNG RÃI (12px, > `space` hiện tại) thay vì khớp
          // sát đúng giá trị `space` — tránh test tự vỡ mỗi khi chỉnh nhẹ
          // `space`/padding hay đổi độ dài text hiển thị (vd làm tròn giá).
          expect(badgeRect.left, lessThan(painter.mPlotWidth));
          expect(badgeRect.left, greaterThanOrEqualTo(painter.mPlotWidth - 12.0));
          expect(badgeRect.right, greaterThan(painter.mPlotWidth));
        },
      );
    },
  );
}
