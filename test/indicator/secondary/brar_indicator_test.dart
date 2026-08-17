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
}
