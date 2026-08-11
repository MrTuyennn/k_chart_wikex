import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('MAIndicator', () {
    test('MA(n) khớp trung bình cộng n phiên gần nhất, sentinel 0 khi chưa đủ dữ liệu', () {
      final data = buildKLines(80);
      final params = [5, 10, 30, 60];
      final indicator = MAIndicator(calcParams: params);
      indicator.calc(data);

      for (int i = 0; i < data.length; i++) {
        final list = data[i].maValueList!;
        expect(list.length, params.length);
        for (int j = 0; j < params.length; j++) {
          final p = params[j];
          if (i < p - 1) {
            expect(list[j], 0, reason: 'i=$i p=$p chưa đủ dữ liệu phải là sentinel 0');
          } else {
            final window = data.sublist(i - p + 1, i + 1).map((e) => e.close);
            final expected = window.reduce((a, b) => a + b) / p;
            expect(list[j], closeTo(expected, 1e-9), reason: 'i=$i p=$p');
          }
        }
      }
    });

    test('dataList rỗng không crash', () {
      final indicator = MAIndicator();
      expect(() => indicator.calc(<KLineEntity>[]), returnsNormally);
    });

    test('MA5 3 nến đầu hand-trace: close = 10,20,30,40,50 -> MA5 nến thứ 5 = 30', () {
      final data = buildKLinesFromCloses([10, 20, 30, 40, 50]);
      final indicator = MAIndicator(calcParams: const [5]);
      indicator.calc(data);
      expect(data[0].maValueList![0], 0);
      expect(data[3].maValueList![0], 0);
      expect(data[4].maValueList![0], 30); // (10+20+30+40+50)/5
    });
  });
}
