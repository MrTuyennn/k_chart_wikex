import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('TRIXIndicator', () {
    test('trix[0] luôn null (chưa có prevEma3), trixMa null cho tới khi đủ m trix', () {
      final data = buildKLines(60);
      TRIXIndicator().calc(data); // calcParams mặc định [12, 20]
      expect(data[0].trix, isNull);
      for (int i = 0; i < 20; i++) {
        expect(data[i].trixMa, isNull, reason: 'i=$i chưa đủ 20 giá trị trix (trix có từ i=1)');
      }
      expect(data[20].trixMa, isNotNull);
    });

    test('oracle transcribe độc lập (EMA×3 nối tiếp, seed=close[0]) khớp toàn bộ chuỗi', () {
      final data = buildKLines(60);
      const n = 12, m = 20;
      TRIXIndicator().calc(data);

      final multiplier = 2 / (n + 1);
      double ema1 = 0, ema2 = 0, ema3 = 0;
      double? prevEma3;
      final trixList = <double?>[];
      for (int i = 0; i < data.length; i++) {
        final close = data[i].close;
        if (i == 0) {
          ema1 = close;
          ema2 = ema1;
          ema3 = ema2;
        } else {
          ema1 = (close - ema1) * multiplier + ema1;
          ema2 = (ema1 - ema2) * multiplier + ema2;
          ema3 = (ema2 - ema3) * multiplier + ema3;
        }
        double? trix;
        if (prevEma3 != null && prevEma3 != 0) {
          trix = (ema3 - prevEma3) / prevEma3 * 100;
        }
        prevEma3 = ema3;
        trixList.add(trix);
        expect(data[i].trix, trix == null ? isNull : closeTo(trix, 1e-6), reason: 'i=$i trix');
      }
      for (int i = 0; i < data.length; i++) {
        final window = trixList.sublist((i - m + 1).clamp(0, i + 1), i + 1);
        if (window.length == m && window.every((v) => v != null)) {
          final expected = window.cast<double>().reduce((a, b) => a + b) / m;
          expect(data[i].trixMa, closeTo(expected, 1e-6), reason: 'i=$i trixMa');
        }
      }
    });
  });
}
