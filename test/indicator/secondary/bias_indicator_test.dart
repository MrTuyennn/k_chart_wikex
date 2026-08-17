import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
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
}
