import 'dart:math';

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

  group('BOLLIndicator', () {
    test('mid/up/dn khớp mean + sample-stdev(n-1) của n close gần nhất', () {
      final data = buildKLines(60);
      const n = 20;
      const k = 2;
      final indicator = BOLLIndicator(); // calcParams mặc định [20, 2]
      indicator.calc(data);

      for (int i = 0; i < data.length; i++) {
        final boll = data[i].boll!;
        if (i < n) {
          expect(boll.mid, isNull, reason: 'i=$i chưa đủ n=$n nến (kể cả gating riêng của mid/up/dn)');
          continue;
        }
        final window = data.sublist(i - n + 1, i + 1).map((e) => e.close).toList();
        final mean = window.reduce((a, b) => a + b) / n;
        final variance = window.map((c) => (c - mean) * (c - mean)).reduce((a, b) => a + b) / (n - 1);
        final stdev = sqrt(variance);
        expect(boll.mid, closeTo(mean, 1e-6), reason: 'i=$i mid');
        expect(boll.up, closeTo(mean + k * stdev, 1e-6), reason: 'i=$i up');
        expect(boll.dn, closeTo(mean - k * stdev, 1e-6), reason: 'i=$i dn');
      }
    });

    test('up luôn >= mid >= dn khi đã có dữ liệu (dải không âm)', () {
      final data = buildKLines(60);
      BOLLIndicator().calc(data);
      for (final e in data) {
        if (e.boll?.mid == null) continue;
        expect(e.boll!.up!, greaterThanOrEqualTo(e.boll!.mid!));
        expect(e.boll!.mid!, greaterThanOrEqualTo(e.boll!.dn!));
      }
    });
  });
}
