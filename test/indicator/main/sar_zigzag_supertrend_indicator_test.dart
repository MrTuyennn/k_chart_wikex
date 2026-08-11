import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

/// 3 indicator dưới đây là stateful/path-dependent (SAR trailing-stop,
/// SuperTrend band-flip, ZigZag pivot-connect) — không có công thức đóng kín
/// để tính độc lập bằng 1 dòng như MA/EMA. Chiến lược test:
///  1. Bất biến toán học suy ra được TRỰC TIẾP từ input (không phụ thuộc cách
///     indicator cài đặt) — vd nến đầu tiên của SAR luôn = low[0].
///  2. Oracle transcribe lại thuật toán một cách độc lập (không copy-paste
///     file nguồn) rồi so khớp — bắt được lỗi index/thứ tự phép toán nếu
///     refactor sau này làm lệch hành vi.
///  3. Trace tay 1 bộ dữ liệu nhỏ, tham số đơn giản hoá (ZigZag depth=1,
///     backstep=0) để có kỳ vọng tường minh, kiểm chứng được bằng mắt.
void main() {
  group('SARIndicator', () {
    test('nến đầu tiên luôn chốt sar = low[0] (bất biến từ điều kiện khởi tạo)', () {
      final data = buildKLines(40);
      SARIndicator().calc(data);
      expect(data[0].sar, closeTo(data[0].low, 1e-9));
    });

    test('oracle transcribe độc lập khớp toàn bộ chuỗi', () {
      final data = buildKLines(50);
      SARIndicator().calc(data);
      final oracle = _sarOracle(data, startAf: 0.02, step: 0.02, maxAf: 0.20);
      for (int i = 0; i < data.length; i++) {
        expect(data[i].sar, closeTo(oracle[i], 1e-9), reason: 'i=$i');
      }
    });

    test('dataList rỗng không crash', () {
      expect(() => SARIndicator().calc(<KLineEntity>[]), returnsNormally);
    });

    test('không sinh NaN/Infinity trên toàn bộ chuỗi', () {
      final data = buildKLines(60);
      SARIndicator().calc(data);
      for (final e in data) {
        expect(e.sar!.isFinite, isTrue);
      }
    });
  });

  group('SuperTrendIndicator', () {
    test('oracle transcribe độc lập (ATR Wilder + band flip) khớp toàn bộ chuỗi', () {
      final data = buildKLines(60);
      SuperTrendIndicator().calc(data); // calcParams mặc định [10, 30] -> period=10, factor=3.0
      final oracle = _superTrendOracle(data, period: 10, multiplier: 3.0);
      for (int i = 0; i < data.length; i++) {
        if (i < 10) {
          expect(data[i].superTrend!.value, isNull, reason: 'i=$i warm-up chưa đủ period');
          continue;
        }
        expect(data[i].superTrend!.value, closeTo(oracle[i].$1, 1e-6), reason: 'i=$i value');
        expect(data[i].superTrend!.isUp, oracle[i].$2, reason: 'i=$i isUp');
      }
    });

    test('value luôn khớp đúng band theo isUp: isUp=true dùng lowerBand (<= mid giá high/low)', () {
      final data = buildKLines(60);
      SuperTrendIndicator().calc(data);
      for (int i = 10; i < data.length; i++) {
        final st = data[i].superTrend!;
        if (st.value == null) continue;
        final mid = (data[i].high + data[i].low) / 2;
        if (st.isUp == true) {
          expect(st.value!, lessThanOrEqualTo(mid), reason: 'i=$i lowerBand phải <= mid');
        } else {
          expect(st.value!, greaterThanOrEqualTo(mid), reason: 'i=$i upperBand phải >= mid');
        }
      }
    });

    test('dataList rỗng không crash', () {
      expect(() => SuperTrendIndicator().calc(<KLineEntity>[]), returnsNormally);
    });
  });

  group('ZigZagIndicator', () {
    test('trace tay: depth=1,backstep=0 -> mọi điểm (trừ điểm đầu) là pivot, zigzag = chính giá đó', () {
      // Với depth=1 & backstep=0, không có bước "xác nhận không bị phá" (vòng
      // for k=1..backstep rỗng) nên bất kỳ điểm nào không nhỏ hơn/lớn hơn
      // hàng xóm bên trái đều được coi là pivot — với dãy zig-zag thực sự thì
      // MỌI điểm từ index 1 trở đi đều là pivot, giá trị giữ nguyên.
      final prices = [1.0, 3.0, 2.0, 5.0, 1.0, 4.0, 2.0];
      // Nến "điểm" — open=high=low=close=price[i] (KHÔNG dùng buildKLinesFromCloses
      // vì nó tạo thân nến open=close[i-1]..close[i], khiến high/low lệch khỏi price[i]).
      final data = buildKLinesFromOHLCV([for (final p in prices) (p, p, p, p, 1.0)]);
      final indicator = ZigZagIndicator(calcParams: const [1, 0, 5]);
      indicator.calc(data);

      expect(data[0].zigzag, isNull);
      for (int i = 1; i < prices.length; i++) {
        expect(data[i].zigzag, closeTo(prices[i], 1e-9), reason: 'i=$i');
      }
    });

    test('mọi giá trị zigzag không-null nằm trong [min low, max high] toàn chuỗi', () {
      final data = buildKLines(80); // calcParams mặc định [12, 2, 5]
      ZigZagIndicator().calc(data);
      final minLow = data.map((e) => e.low).reduce(min);
      final maxHigh = data.map((e) => e.high).reduce(max);
      for (final e in data) {
        if (e.zigzag == null) continue;
        expect(e.zigzag!, greaterThanOrEqualTo(minLow - 1e-9));
        expect(e.zigzag!, lessThanOrEqualTo(maxHigh + 1e-9));
      }
    });

    test('dataList rỗng không crash', () {
      expect(() => ZigZagIndicator().calc(<KLineEntity>[]), returnsNormally);
    });

    test('gọi calc 2 lần cho kết quả giống hệt nhau (idempotent, reset đúng field cũ)', () {
      final data = buildKLines(50);
      final indicator = ZigZagIndicator();
      indicator.calc(data);
      final first = data.map((e) => e.zigzag).toList();
      indicator.calc(data);
      final second = data.map((e) => e.zigzag).toList();
      expect(second, first);
    });
  });
}

/// Transcribe độc lập thuật toán SAR (không copy file nguồn) từ mô tả công
/// thức trong `indicator.md` §1 SAR — dùng làm oracle cross-check.
List<double> _sarOracle(
  List<KLineEntity> data, {
  required double startAf,
  required double step,
  required double maxAf,
}) {
  double af = startAf;
  double ep = -100;
  bool isIncreasing = false;
  double sar = 0;
  final out = <double>[];
  for (int i = 0; i < data.length; i++) {
    final preSar = sar;
    final high = data[i].high;
    final low = data[i].low;
    if (isIncreasing) {
      if (ep == -100 || ep < high) {
        ep = high;
        af = min(af + step, maxAf);
      }
      sar = preSar + af * (ep - preSar);
      final lowMin = min(data[max(1, i) - 1].low, low);
      if (sar > data[i].low) {
        sar = ep;
        af = startAf;
        ep = -100;
        isIncreasing = !isIncreasing;
      } else if (sar > lowMin) {
        sar = lowMin;
      }
    } else {
      if (ep == -100 || ep > low) {
        ep = low;
        af = min(af + step, maxAf);
      }
      sar = preSar + af * (ep - preSar);
      final highMax = max(data[max(1, i) - 1].high, high);
      if (sar < data[i].high) {
        sar = ep;
        af = 0;
        ep = -100;
        isIncreasing = !isIncreasing;
      } else if (sar < highMax) {
        sar = highMax;
      }
    }
    out.add(sar);
  }
  return out;
}

/// Transcribe độc lập thuật toán SuperTrend (ATR Wilder-smoothed + band flip)
/// từ mô tả công thức trong `indicator.md` §1 SuperTrend — dùng làm oracle.
List<(double, bool)> _superTrendOracle(
  List<KLineEntity> data, {
  required int period,
  required double multiplier,
}) {
  double atr = 0;
  double sumTr = 0;
  double? prevFinalUpperBand;
  double? prevFinalLowerBand;
  double? prevSuperTrend;
  final out = <(double, bool)>[];

  for (int i = 0; i < data.length; i++) {
    final high = data[i].high;
    final low = data[i].low;
    final close = data[i].close;

    final tr = i == 0
        ? high - low
        : max(high - low, max((high - data[i - 1].close).abs(), (low - data[i - 1].close).abs()));

    if (i < period) {
      sumTr += tr;
      if (i == period - 1) atr = sumTr / period;
      out.add((double.nan, false));
      continue;
    }

    atr = (atr * (period - 1) + tr) / period;

    final mid = (high + low) / 2;
    final basicUpperBand = mid + multiplier * atr;
    final basicLowerBand = mid - multiplier * atr;
    final prevClose = data[i - 1].close;

    final finalUpperBand =
        (prevFinalUpperBand == null || basicUpperBand < prevFinalUpperBand || prevClose > prevFinalUpperBand)
        ? basicUpperBand
        : prevFinalUpperBand;

    final finalLowerBand =
        (prevFinalLowerBand == null || basicLowerBand > prevFinalLowerBand || prevClose < prevFinalLowerBand)
        ? basicLowerBand
        : prevFinalLowerBand;

    final isUp = prevSuperTrend == null
        ? close > finalUpperBand
        : prevSuperTrend == prevFinalUpperBand
        ? close > finalUpperBand
        : close >= finalLowerBand;

    final value = isUp ? finalLowerBand : finalUpperBand;
    out.add((value, isUp));

    prevFinalUpperBand = finalUpperBand;
    prevFinalLowerBand = finalLowerBand;
    prevSuperTrend = value;
  }
  return out;
}
