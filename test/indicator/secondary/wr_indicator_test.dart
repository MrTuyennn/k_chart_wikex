import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('WRIndicator', () {
    test('sentinel -10 khi i < 13, sau đó luôn trong [-100, 0]', () {
      final data = buildKLines(50);
      WRIndicator().calc(data);
      for (int i = 0; i < 13; i++) {
        expect(data[i].r, -10.0, reason: 'i=$i');
      }
      for (int i = 13; i < data.length; i++) {
        if (data[i].r == null) continue; // NaN-guard branch (max==min)
        expect(data[i].r!, inInclusiveRange(-100, 0), reason: 'i=$i');
      }
    });

    test('oracle transcribe độc lập (cửa sổ [max(0,i-14), i]) khớp toàn bộ chuỗi', () {
      final data = buildKLines(50);
      WRIndicator().calc(data);
      for (int i = 13; i < data.length; i++) {
        final start = max(0, i - 14);
        final window = data.sublist(start, i + 1);
        final max14 = window.map((e) => e.high).reduce(max);
        final min14 = window.map((e) => e.low).reduce(min);
        final expected = -100 * (max14 - data[i].close) / (max14 - min14);
        expect(data[i].r, closeTo(expected, 1e-9), reason: 'i=$i');
      }
    });
  });
}
