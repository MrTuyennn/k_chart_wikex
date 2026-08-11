import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('EMAIndicator', () {
    test('EMA(n) khớp công thức multiplier = 2/(n+1), seed = close đầu tiên', () {
      final data = buildKLines(80);
      final params = [5, 10, 30, 60];
      final indicator = EMAIndicator(calcParams: params);
      indicator.calc(data);

      // Oracle độc lập: tự đệ quy lại công thức EMA trên chuỗi close.
      for (int j = 0; j < params.length; j++) {
        final p = params[j];
        final multiplier = 2 / (p + 1);
        double ema = data[0].close;
        expect(data[0].emaValueList![j], closeTo(ema, 1e-9));
        for (int i = 1; i < data.length; i++) {
          ema = (data[i].close - ema) * multiplier + ema;
          expect(data[i].emaValueList![j], closeTo(ema, 1e-9), reason: 'i=$i p=$p');
        }
      }
    });

    test('EMA phản ứng nhanh hơn MA khi giá nhảy bậc (weight gần nhất lớn hơn)', () {
      // Chuỗi phẳng rồi nhảy bậc mạnh ở cuối — EMA(5) phải tiến gần giá mới
      // nhanh hơn MA(5) vì trọng số giá gần nhất cao hơn 1/5.
      final closes = [...List.filled(10, 100.0), 200.0];
      final data = buildKLinesFromCloses(closes);
      final ma = MAIndicator(calcParams: const [5]);
      final ema = EMAIndicator(calcParams: const [5]);
      ma.calc(data);
      ema.calc(data);
      final last = data.last;
      expect(last.emaValueList![0], greaterThan(last.maValueList![0]));
    });
  });
}
