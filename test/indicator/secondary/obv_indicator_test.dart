import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('OBVIndicator', () {
    test('hand-trace 5 nến: obv tích lũy theo dấu close, signal = SMA5', () {
      final closes = [10.0, 12.0, 11.0, 11.0, 15.0];
      final vols = [100.0, 200.0, 150.0, 50.0, 300.0];
      final data = buildKLinesFromCloses(closes, vols: vols);
      OBVIndicator().calc(data); // calcParams mặc định [5]

      expect(data[0].obv, 100.0);
      expect(data[1].obv, 300.0); // 12 > 10 -> +200
      expect(data[2].obv, 150.0); // 11 < 12 -> -150
      expect(data[3].obv, 150.0); // 11 == 11 -> giữ nguyên
      expect(data[4].obv, 450.0); // 15 > 11 -> +300

      expect(data[0].obvSignal, isNull);
      expect(data[3].obvSignal, isNull);
      expect(data[4].obvSignal, closeTo((100 + 300 + 150 + 150 + 450) / 5, 1e-9));
    });

    test('oracle transcribe độc lập khớp toàn bộ chuỗi tổng hợp', () {
      final data = buildKLines(60);
      const period = 5;
      OBVIndicator().calc(data);

      double obv = data[0].vol;
      final obvList = [obv];
      for (int i = 1; i < data.length; i++) {
        if (data[i].close > data[i - 1].close) {
          obv += data[i].vol;
        } else if (data[i].close < data[i - 1].close) {
          obv -= data[i].vol;
        }
        obvList.add(obv);
      }
      for (int i = 0; i < data.length; i++) {
        expect(data[i].obv, closeTo(obvList[i], 1e-9), reason: 'i=$i obv');
        if (i >= period - 1) {
          final window = obvList.sublist(i - period + 1, i + 1);
          final expectedSignal = window.reduce((a, b) => a + b) / period;
          expect(data[i].obvSignal, closeTo(expectedSignal, 1e-9), reason: 'i=$i signal');
        } else {
          expect(data[i].obvSignal, isNull, reason: 'i=$i signal warm-up');
        }
      }
    });
  });
}
