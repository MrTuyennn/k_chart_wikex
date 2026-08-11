import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('MTMIndicator', () {
    test('hand-trace: dãy cấp số cộng bước 1, calcParams mặc định [12,6] -> MTM luôn = 12', () {
      // MTMIndicator không cho constructor tự truyền calcParams (hard-code [12, 6]).
      final closes = List.generate(30, (i) => (i + 1).toDouble()); // 1..30
      final data = buildKLinesFromCloses(closes);
      MTMIndicator().calc(data);
      for (int i = 0; i < 12; i++) {
        expect(data[i].mtm, isNull, reason: 'i=$i warm-up');
      }
      for (int i = 12; i < data.length; i++) {
        expect(data[i].mtm, closeTo(12.0, 1e-9), reason: 'i=$i');
      }
      // mtmMa cần đủ m=6 giá trị mtm liên tiếp -> có từ i = n + m - 1 = 17
      expect(data[16].mtmMa, isNull);
      expect(data[17].mtmMa, closeTo(12.0, 1e-9));
    });

    test('oracle công thức trực tiếp MTM = close - close[i-n], MTMMA = MA(MTM,m)', () {
      final data = buildKLines(60);
      const n = 12, m = 6;
      MTMIndicator().calc(data); // calcParams mặc định [12, 6]

      final mtmList = List<double?>.filled(data.length, null);
      for (int i = 0; i < data.length; i++) {
        if (i < n) {
          expect(data[i].mtm, isNull, reason: 'i=$i');
          continue;
        }
        final expected = data[i].close - data[i - n].close;
        mtmList[i] = expected;
        expect(data[i].mtm, closeTo(expected, 1e-9), reason: 'i=$i');
      }
      for (int i = n + m - 1; i < data.length; i++) {
        final window = mtmList.sublist(i - m + 1, i + 1).cast<double>();
        final expected = window.reduce((a, b) => a + b) / m;
        expect(data[i].mtmMa, closeTo(expected, 1e-6), reason: 'i=$i');
      }
    });
  });
}
