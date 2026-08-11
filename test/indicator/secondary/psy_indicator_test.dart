import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
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
}
