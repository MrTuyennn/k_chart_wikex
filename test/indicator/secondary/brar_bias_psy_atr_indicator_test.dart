import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('BRARIndicator', () {
    test('AR sẵn sàng từ i=n-1, BR trễ hơn 1 nến (từ i=n) — oracle windowed-sum naive khớp toàn bộ chuỗi', () {
      final data = buildKLines(60);
      const n = 26;
      BRARIndicator().calc(data); // calcParams mặc định [26]

      for (int i = 0; i < n - 1; i++) {
        expect(data[i].ar, isNull, reason: 'i=$i ar warm-up');
      }
      for (int i = 0; i < n; i++) {
        expect(data[i].br, isNull, reason: 'i=$i br warm-up (trễ hơn ar 1 nến)');
      }

      for (int i = n - 1; i < data.length; i++) {
        final window = data.sublist(i - n + 1, i + 1);
        final sumHO = window.map((e) => e.high - e.open).reduce((a, b) => a + b);
        final sumOL = window.map((e) => e.open - e.low).reduce((a, b) => a + b);
        final expectedAr = sumOL == 0 ? 0.0 : sumHO / sumOL * 100;
        expect(data[i].ar, closeTo(expectedAr, 1e-6), reason: 'i=$i ar');
      }

      for (int i = n; i < data.length; i++) {
        double sumHC = 0, sumCL = 0;
        for (int j = i - n + 1; j <= i; j++) {
          final prevClose = data[j - 1].close;
          sumHC += max(0.0, data[j].high - prevClose);
          sumCL += max(0.0, prevClose - data[j].low);
        }
        final expectedBr = sumCL == 0 ? 0.0 : sumHC / sumCL * 100;
        expect(data[i].br, closeTo(expectedBr, 1e-6), reason: 'i=$i br');
      }
    });

    test('dataList rỗng không crash', () {
      expect(() => BRARIndicator().calc(<KLineEntity>[]), returnsNormally);
    });
  });

  group('BIASIndicator', () {
    test('BIAS(n) = (close - MA(close,n)) / MA(close,n) * 100 cho từng chu kỳ trong calcParams', () {
      final data = buildKLines(60);
      const periods = [6, 12, 24];
      BIASIndicator().calc(data); // calcParams mặc định [6, 12, 24]

      for (int i = 0; i < data.length; i++) {
        final values = data[i].biasValueList!;
        expect(values.length, periods.length);
        for (int j = 0; j < periods.length; j++) {
          final p = periods[j];
          if (i < p - 1) {
            expect(values[j], isNull, reason: 'i=$i p=$p warm-up');
          } else {
            final window = data.sublist(i - p + 1, i + 1).map((e) => e.close);
            final ma = window.reduce((a, b) => a + b) / p;
            final expected = ma == 0 ? 0.0 : (data[i].close - ma) / ma * 100;
            expect(values[j], closeTo(expected, 1e-6), reason: 'i=$i p=$p');
          }
        }
      }
    });

    test('dataList rỗng không crash', () {
      expect(() => BIASIndicator().calc(<KLineEntity>[]), returnsNormally);
    });
  });

  group('PSYIndicator', () {
    test('hand-trace: 12 phiên tăng đúng 9 lần trong N=12 -> PSY = 9/12*100', () {
      // close: 10 phiên đầu random-ish tăng/giảm kiểm soát, đếm tay số phiên tăng.
      final closes = [10.0, 11.0, 10.0, 11.0, 12.0, 13.0, 12.0, 13.0, 14.0, 13.0, 14.0, 15.0, 16.0];
      // so với phiên trước (i=1..12): +,-,+,+,+,-,+,+,-,+,+,+ -> 9 lần tăng trong 12 phiên (i=1..12).
      final data = buildKLinesFromCloses(closes);
      PSYIndicator().calc(data); // calcParams mặc định [12, 6] -> n=12
      expect(data.last.psy, closeTo(9 / 12 * 100, 1e-9));
    });

    test('PSY = %phiên tăng trong N phiên gần nhất, MAPSY = MA(PSY,M) — oracle naive khớp toàn bộ chuỗi', () {
      final data = buildKLines(60);
      const n = 12, m = 6;
      PSYIndicator().calc(data); // calcParams mặc định [12, 6]

      final psyList = List<double?>.filled(data.length, null);
      for (int i = 1; i < data.length; i++) {
        if (i < n) continue;
        int upCount = 0;
        for (int j = i - n + 1; j <= i; j++) {
          if (data[j].close > data[j - 1].close) upCount++;
        }
        final expected = upCount / n * 100;
        psyList[i] = expected;
        expect(data[i].psy, closeTo(expected, 1e-6), reason: 'i=$i psy');
      }
      for (int i = 0; i < data.length; i++) {
        if (i < n + m - 1) {
          expect(data[i].psyMa, isNull, reason: 'i=$i psyMa warm-up');
        } else {
          final window = psyList.sublist(i - m + 1, i + 1).cast<double>();
          final expected = window.reduce((a, b) => a + b) / m;
          expect(data[i].psyMa, closeTo(expected, 1e-6), reason: 'i=$i psyMa');
        }
      }
    });

    test('PSY luôn nằm trong [0, 100]', () {
      final data = buildKLines(80);
      PSYIndicator().calc(data);
      for (final e in data) {
        if (e.psy != null) expect(e.psy!, inInclusiveRange(0, 100));
      }
    });
  });

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
