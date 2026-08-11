import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
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
