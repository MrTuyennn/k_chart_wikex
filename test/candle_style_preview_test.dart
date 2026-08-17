import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/k_chart_plus.dart';

/// Test cho `lib/styles/candle_style/` — 2 widget vẽ preview bằng
/// `CustomPainter`, không có `test/indicator/`-style oracle (không phải công
/// thức số học) nên verify qua `paints` matcher của `flutter_test` (bắt được
/// canvas method call thật, không cần golden image) + smoke test không
/// throw ở input suy biến.
void main() {
  Widget wrap(Widget child, {double width = 200, double height = 120}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  /// true nếu có ít nhất 1 `Canvas.drawRect` vẽ với `Paint.style == style`.
  PaintPatternPredicate rectWithStyle(PaintingStyle style) {
    return (Symbol methodName, List<dynamic> arguments) {
      if (methodName != #drawRect) return false;
      final paint = arguments[1] as Paint;
      return paint.style == style;
    };
  }

  group('CandleStylePreview.candle', () {
    testWidgets('solid — không có rect nào vẽ style stroke (mọi thân đều tô đặc)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const CandleStylePreview.candle(bodyStyle: CandleBodyStyle.solid)),
      );
      expect(
        find.byType(CustomPaint).first,
        isNot(paints..something(rectWithStyle(PaintingStyle.stroke))),
      );
    });

    testWidgets('hollow — có ít nhất 1 rect vẽ style stroke (thân rỗng)', (tester) async {
      await tester.pumpWidget(
        wrap(const CandleStylePreview.candle(bodyStyle: CandleBodyStyle.hollow)),
      );
      expect(find.byType(CustomPaint).first, paints..something(rectWithStyle(PaintingStyle.stroke)));
    });

    testWidgets('hollowUp/hollowDown — vẫn có rect stroke (nến tăng lẫn giảm đan xen trong dữ liệu demo)', (
      tester,
    ) async {
      for (final style in [CandleBodyStyle.hollowUp, CandleBodyStyle.hollowDown]) {
        await tester.pumpWidget(wrap(CandleStylePreview.candle(bodyStyle: style)));
        expect(
          find.byType(CustomPaint).first,
          paints..something(rectWithStyle(PaintingStyle.stroke)),
          reason: '$style phải có nến rỗng vì chuỗi giá demo có cả nến tăng lẫn giảm',
        );
      }
    });

    testWidgets('kích thước suy biến (height = 0) không throw (early-return guard trong painter)', (
      tester,
    ) async {
      for (final style in CandleBodyStyle.values) {
        await tester.pumpWidget(
          wrap(CandleStylePreview.candle(bodyStyle: style), height: 0),
        );
        expect(tester.takeException(), isNull, reason: '$style height=0');
      }
    });
  });

  group('CandleStylePreview.line', () {
    testWidgets('vẽ path stroke màu lineColor, KHÔNG vẽ rect nào (không phải nến)', (
      tester,
    ) async {
      const lineColor = Color(0xFF217AFF);
      await tester.pumpWidget(wrap(const CandleStylePreview.line(lineColor: lineColor)));
      expect(
        find.byType(CustomPaint).first,
        // path() đầu = gradient fill dưới đường (không ràng buộc gì — shader,
        // không phải color) — path() thứ 2 mới là đường line thật cần kiểm.
        paints
          ..path()
          ..path(style: PaintingStyle.stroke, color: lineColor),
      );
      expect(
        find.byType(CustomPaint).first,
        isNot(paints..something((methodName, _) => methodName == #drawRect)),
      );
    });

    testWidgets('height = 0 không throw', (tester) async {
      await tester.pumpWidget(wrap(const CandleStylePreview.line(), height: 0));
      expect(tester.takeException(), isNull);
    });
  });

  group('CandleStyleIcon', () {
    testWidgets('build không throw cho mọi CandleBodyStyle', (tester) async {
      for (final style in CandleBodyStyle.values) {
        await tester.pumpWidget(wrap(CandleStyleIcon(bodyStyle: style), width: 28, height: 22));
        expect(tester.takeException(), isNull, reason: '$style');
      }
    });

    testWidgets('hollow — có rect vẽ style stroke, solid thì không', (tester) async {
      await tester.pumpWidget(
        wrap(const CandleStyleIcon(bodyStyle: CandleBodyStyle.hollow), width: 28, height: 22),
      );
      expect(find.byType(CustomPaint).first, paints..something(rectWithStyle(PaintingStyle.stroke)));

      await tester.pumpWidget(
        wrap(const CandleStyleIcon(bodyStyle: CandleBodyStyle.solid), width: 28, height: 22),
      );
      expect(
        find.byType(CustomPaint).first,
        isNot(paints..something(rectWithStyle(PaintingStyle.stroke))),
      );
    });
  });
}
