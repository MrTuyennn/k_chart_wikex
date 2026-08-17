import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('CCIIndicator', () {
    test('oracle transcribe độc lập (naive O(n*period), TP=(H+L+C)/3) khớp toàn bộ chuỗi', () {
      final data = buildKLines(60);
      const periods = 20;
      CCIIndicator().calc(data); // calcParams mặc định [20]

      for (int i = 0; i < data.length; i++) {
        if (i < periods - 1) {
          expect(data[i].cci, isNull, reason: 'i=$i warm-up');
          continue;
        }
        final window = data.sublist(i - periods + 1, i + 1);
        final tps = window.map((e) => (e.high + e.low + e.close) / 3).toList();
        final tp = tps.last;
        final maTp = tps.reduce((a, b) => a + b) / periods;
        final md = tps.map((v) => (v - maTp).abs()).reduce((a, b) => a + b) / periods;
        final expected = md != 0 ? (tp - maTp) / md / 0.015 : 0.0;
        expect(data[i].cci, closeTo(expected, 1e-6), reason: 'i=$i');
      }
    });

    test('dataList rỗng không crash', () {
      expect(() => CCIIndicator().calc(<KLineEntity>[]), returnsNormally);
    });
  });
}
