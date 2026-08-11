import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('ATRIndicator', () {
    test('oracle transcribe độc lập (TR -> seed SMA -> Wilder smoothing) khớp toàn bộ chuỗi', () {
      final data = buildKLines(60);
      const n = 14, m = 6;
      ATRIndicator().calc(data); // calcParams mặc định [14, 6]

      double trSum = 0;
      double? atrPrev;
      final atrList = List<double?>.filled(data.length, null);
      for (int i = 0; i < data.length; i++) {
        final double tr;
        if (i == 0) {
          tr = data[i].high - data[i].low;
        } else {
          final prevClose = data[i - 1].close;
          tr = max(data[i].high - data[i].low, max((data[i].high - prevClose).abs(), (data[i].low - prevClose).abs()));
        }
        double? atr;
        if (i < n - 1) {
          trSum += tr;
        } else if (i == n - 1) {
          trSum += tr;
          atr = trSum / n;
        } else {
          atr = (tr + (n - 1) * atrPrev!) / n;
        }
        if (atr != null) atrPrev = atr;
        atrList[i] = atr;
        expect(data[i].atr, atr == null ? isNull : closeTo(atr, 1e-6), reason: 'i=$i atr');
      }

      for (int i = 0; i < data.length; i++) {
        if (i < n + m - 2) {
          expect(data[i].atrMa, isNull, reason: 'i=$i atrMa warm-up');
        } else {
          final window = atrList.sublist(i - m + 1, i + 1).cast<double>();
          final expected = window.reduce((a, b) => a + b) / m;
          expect(data[i].atrMa, closeTo(expected, 1e-6), reason: 'i=$i atrMa');
        }
      }
    });

    test('ATR luôn >= 0 (độ biến động không âm)', () {
      final data = buildKLines(60);
      ATRIndicator().calc(data);
      for (final e in data) {
        if (e.atr != null) expect(e.atr!, greaterThanOrEqualTo(0));
      }
    });

    test('dataList rỗng không crash', () {
      expect(() => ATRIndicator().calc(<KLineEntity>[]), returnsNormally);
    });
  });
}
