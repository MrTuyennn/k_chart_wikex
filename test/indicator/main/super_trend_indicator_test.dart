import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
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
