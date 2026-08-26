import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/k_chart_plus.dart';

/// Regression: `KChartWidget` painted với `datas` null/rỗng (vd app đang
/// fetch REST lần đầu, hoặc API trả về không có nến) từng crash
/// "Unsupported operation: Infinity or NaN toInt". Nguyên nhân —
/// `BaseChartPainter.calculateValue()` return sớm khi datas rỗng mà KHÔNG
/// reset `mMainMaxValue`/`mMainMinValue` (và vol/secondary tương ứng) khỏi
/// sentinel dò min/max (`minPositive`/`maxFinite`, đảo ngược nhau khi chưa
/// scan qua nến nào) — `initChartRenderer()` vẫn chạy UNCONDITIONALLY mỗi
/// paint (kể cả rỗng) và feed thẳng cặp giá trị đảo ngược đó vào renderer,
/// gây priceRange ≈ -maxFinite → NaN/Infinity khi tính tỉ lệ pixel/giá.
void main() {
  group('KChartWidget — datas null/empty does not crash on paint', () {
    testWidgets('datas = [] paints without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                const <KLineEntity>[],
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
      expect(tester.takeException(), isNull);
    });

    testWidgets('datas = null paints without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                null,
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
      expect(tester.takeException(), isNull);
    });

    testWidgets('datas = [] with emptyPlaceholder shows the placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                const <KLineEntity>[],
                const KChartStyle(),
                const KChartColors(),
                isTrendLine: false,
                detailBuilder: (e) => const SizedBox(),
                emptyPlaceholder: const Text('Không có dữ liệu'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Không có dữ liệu'), findsOneWidget);
    });

    testWidgets('datas = [] with volHidden=false and secondary indicators '
        'still paints without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                const <KLineEntity>[],
                const KChartStyle(),
                const KChartColors(),
                isTrendLine: false,
                detailBuilder: (e) => const SizedBox(),
                volHidden: false,
                secondaryIndicators: [MACDIndicator()],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('KChartWidget — loading default spinner / loadingWidget / precedence', () {
    testWidgets('loading = true with no loadingWidget/emptyPlaceholder shows '
        'a default adaptive spinner', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                const <KLineEntity>[],
                const KChartStyle(),
                const KChartColors(),
                isTrendLine: false,
                detailBuilder: (e) => const SizedBox(),
                loading: true,
              ),
            ),
          ),
        ),
      );
      // KHÔNG `pumpAndSettle()` — CircularProgressIndicator mặc định animate
      // vô hạn (indeterminate), `pumpAndSettle` sẽ timeout chờ nó "settle".
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('loadingWidget custom ghi đè spinner adaptive mặc định khi '
        'loading = true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                const <KLineEntity>[],
                const KChartStyle(),
                const KChartColors(),
                isTrendLine: false,
                detailBuilder: (e) => const SizedBox(),
                loading: true,
                loadingWidget: const Text('Custom loading'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Custom loading'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('loading = true LUÔN thắng emptyPlaceholder (vẽ spinner, bỏ '
        'qua emptyPlaceholder) — cho phép set emptyPlaceholder KHÔNG ĐIỀU '
        'KIỆN ở tầng gọi', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                const <KLineEntity>[],
                const KChartStyle(),
                const KChartColors(),
                isTrendLine: false,
                detailBuilder: (e) => const SizedBox(),
                loading: true,
                emptyPlaceholder: const Text('Không có dữ liệu'),
              ),
            ),
          ),
        ),
      );
      // KHÔNG `pumpAndSettle()` — vẫn vẽ spinner (loading thắng), không phải
      // Text tĩnh.
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Không có dữ liệu'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('loading = false (mặc định) không vẽ spinner, để '
        'emptyPlaceholder tự lộ ra', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                const <KLineEntity>[],
                const KChartStyle(),
                const KChartColors(),
                isTrendLine: false,
                detailBuilder: (e) => const SizedBox(),
                emptyPlaceholder: const Text('Không có dữ liệu'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Không có dữ liệu'), findsOneWidget);
    });
  });

  group('KChartWidget — datas null/empty kèm livePrice/bidPrice/askPrice', () {
    // `drawNowPrice`/`drawBidAsk` (chart_painter.dart) dùng `datas!.last` —
    // cả 2 chỉ được gọi từ trong nhánh `datas != null && datas!.isNotEmpty`
    // của `BaseChartPainter.paint()`, nên `livePrice`/`bidPrice`/`askPrice`
    // (dù null hay có giá trị) không bao giờ chạm code đọc `datas!.last` khi
    // `datas` null/rỗng. Test dưới xác nhận điều đó bằng cách pump thật thay
    // vì chỉ đọc code.
    testWidgets('datas = null + livePrice/bidPrice/askPrice đều set không '
        'crash', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                null,
                const KChartStyle(),
                const KChartColors(),
                isTrendLine: false,
                detailBuilder: (e) => const SizedBox(),
                livePrice: 100.5,
                bidPrice: 100.4,
                askPrice: 100.6,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('datas = [] + chỉ bidPrice set (askPrice null) không crash', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                const <KLineEntity>[],
                const KChartStyle(),
                const KChartColors(),
                isTrendLine: false,
                detailBuilder: (e) => const SizedBox(),
                bidPrice: 100.4,
                askPrice: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('datas = null + loading: true + livePrice/bidPrice/askPrice '
        'set đồng thời không crash', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: KChartWidget(
                null,
                const KChartStyle(),
                const KChartColors(),
                isTrendLine: false,
                detailBuilder: (e) => const SizedBox(),
                loading: true,
                livePrice: 100.5,
                bidPrice: 100.4,
                askPrice: 100.6,
              ),
            ),
          ),
        ),
      );
      // loading:true → spinner adaptive animate vô hạn, không pumpAndSettle().
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('datas có nến thật nhưng livePrice/bidPrice/askPrice đều '
        'null không crash (fallback datas.last.close)', (tester) async {
      final candles = List.generate(
        20,
        (i) => KLineEntity.fromCustom(
          time: DateTime(2024, 1, 1).millisecondsSinceEpoch + i * 3600000,
          open: 100,
          high: 101,
          low: 99,
          close: 100.5,
          vol: 1,
          amount: 100,
        ),
      );
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
                livePrice: null,
                bidPrice: null,
                askPrice: null,
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
