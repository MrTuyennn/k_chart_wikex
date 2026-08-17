import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

/// SAR là stateful/path-dependent (trailing-stop) — không có công thức đóng
/// kín để tính độc lập bằng 1 dòng như MA/EMA. Chiến lược test:
///  1. Bất biến toán học suy ra được TRỰC TIẾP từ input (không phụ thuộc cách
///     indicator cài đặt) — vd nến đầu tiên luôn = low[0].
///  2. Oracle transcribe lại thuật toán một cách độc lập (không copy-paste
///     file nguồn) rồi so khớp — bắt được lỗi index/thứ tự phép toán nếu
///     refactor sau này làm lệch hành vi.
void main() {
  group('SARIndicator', () {
    test('nến đầu tiên luôn chốt sar = low[0] (bất biến từ điều kiện khởi tạo)', () {
      final data = buildKLines(40);
      SARIndicator().calc(data);
      expect(data[0].sar, closeTo(data[0].low, 1e-9));
    });

    test('oracle transcribe độc lập khớp toàn bộ chuỗi', () {
      final data = buildKLines(50);
      SARIndicator().calc(data);
      final oracle = _sarOracle(data, startAf: 0.02, step: 0.02, maxAf: 0.20);
      for (int i = 0; i < data.length; i++) {
        expect(data[i].sar, closeTo(oracle[i], 1e-9), reason: 'i=$i');
      }
    });

    test('dataList rỗng không crash', () {
      expect(() => SARIndicator().calc(<KLineEntity>[]), returnsNormally);
    });

    test('không sinh NaN/Infinity trên toàn bộ chuỗi', () {
      final data = buildKLines(60);
      SARIndicator().calc(data);
      for (final e in data) {
        expect(e.sar!.isFinite, isTrue);
      }
    });
  });
}

/// Transcribe độc lập thuật toán SAR (không copy file nguồn) từ mô tả công
/// thức trong `indicator.md` §1 SAR — dùng làm oracle cross-check.
List<double> _sarOracle(
  List<KLineEntity> data, {
  required double startAf,
  required double step,
  required double maxAf,
}) {
  double af = startAf;
  double ep = -100;
  bool isIncreasing = false;
  double sar = 0;
  final out = <double>[];
  for (int i = 0; i < data.length; i++) {
    final preSar = sar;
    final high = data[i].high;
    final low = data[i].low;
    if (isIncreasing) {
      if (ep == -100 || ep < high) {
        ep = high;
        af = min(af + step, maxAf);
      }
      sar = preSar + af * (ep - preSar);
      final lowMin = min(data[max(1, i) - 1].low, low);
      if (sar > data[i].low) {
        sar = ep;
        af = startAf;
        ep = -100;
        isIncreasing = !isIncreasing;
      } else if (sar > lowMin) {
        sar = lowMin;
      }
    } else {
      if (ep == -100 || ep > low) {
        ep = low;
        af = min(af + step, maxAf);
      }
      sar = preSar + af * (ep - preSar);
      final highMax = max(data[max(1, i) - 1].high, high);
      if (sar < data[i].high) {
        sar = ep;
        af = 0;
        ep = -100;
        isIncreasing = !isIncreasing;
      } else if (sar < highMax) {
        sar = highMax;
      }
    }
    out.add(sar);
  }
  return out;
}
