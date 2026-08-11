import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('KDJIndicator', () {
    test('nến đầu tiên luôn chốt K=D=J=50 (seed cố định trong calc())', () {
      final data = buildKLines(40);
      KDJIndicator().calc(data);
      expect(data[0].k, 50.0);
      expect(data[0].d, 50.0);
      expect(data[0].j, 50.0);
    });

    test('J = 3K - 2D tại mọi điểm', () {
      final data = buildKLines(60);
      KDJIndicator().calc(data);
      for (final e in data) {
        expect(e.j, closeTo(3 * e.k! - 2 * e.d!, 1e-9));
      }
    });

    test('oracle transcribe độc lập (RSV cửa sổ 9 nến, K/D smoothing 1/3-2/3) khớp toàn bộ chuỗi', () {
      final data = buildKLines(60);
      KDJIndicator().calc(data);
      final oracle = _kdjOracle(data);
      for (int i = 0; i < data.length; i++) {
        expect(data[i].k, closeTo(oracle.$1[i], 1e-9), reason: 'i=$i k');
        expect(data[i].d, closeTo(oracle.$2[i], 1e-9), reason: 'i=$i d');
      }
    });
  });
}

/// Transcribe độc lập KDJ (RSV cửa sổ tối đa 9 nến, K/D smoothing 1/3-2/3,
/// seed 50) từ mô tả `indicator.md` §2 KDJ — dùng làm oracle cross-check.
(List<double>, List<double>, List<double>) _kdjOracle(List<KLineEntity> data) {
  final n = data.length;
  final k = List<double>.filled(n, 0);
  final d = List<double>.filled(n, 0);
  final j = List<double>.filled(n, 0);
  double preK = 50, preD = 50;
  k[0] = 50;
  d[0] = 50;
  j[0] = 50;
  for (int i = 1; i < n; i++) {
    final start = max(0, i - 8);
    var low = data[i].low;
    var high = data[i].high;
    for (int idx = start; idx < i; idx++) {
      if (data[idx].low < low) low = data[idx].low;
      if (data[idx].high > high) high = data[idx].high;
    }
    var rsv = (data[i].close - low) * 100.0 / (high - low);
    if (rsv.isNaN) rsv = 0;
    final kv = (2 * preK + rsv) / 3.0;
    final dv = (2 * preD + kv) / 3.0;
    k[i] = kv;
    d[i] = dv;
    j[i] = 3 * kv - 2 * dv;
    preK = kv;
    preD = dv;
  }
  return (k, d, j);
}
