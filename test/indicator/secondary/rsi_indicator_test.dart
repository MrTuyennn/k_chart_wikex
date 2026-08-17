import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('RSIIndicator', () {
    test('chuỗi tăng liên tục tuyệt đối -> RSI = 100 chính xác từ nến 14 trở đi', () {
      final closes = List.generate(30, (i) => 100.0 + i); // luôn tăng, avgLoss luôn = 0
      final data = buildKLinesFromCloses(closes);
      RSIIndicator().calc(data);
      for (int i = 0; i < 13; i++) {
        expect(data[i].rsi, isNull, reason: 'i=$i warm-up');
      }
      for (int i = 13; i < data.length; i++) {
        expect(data[i].rsi, closeTo(100, 1e-9), reason: 'i=$i');
      }
    });

    test('chuỗi giảm liên tục tuyệt đối -> RSI = 0 chính xác từ nến 14 trở đi', () {
      final closes = List.generate(30, (i) => 200.0 - i); // luôn giảm, avgGain luôn = 0
      final data = buildKLinesFromCloses(closes);
      RSIIndicator().calc(data);
      for (int i = 13; i < data.length; i++) {
        expect(data[i].rsi, closeTo(0, 1e-9), reason: 'i=$i');
      }
    });

    test('RSI luôn nằm trong [0, 100] trên dữ liệu tổng hợp', () {
      final data = buildKLines(60);
      RSIIndicator().calc(data);
      for (final e in data) {
        if (e.rsi == null) continue;
        expect(e.rsi!, inInclusiveRange(0, 100));
      }
    });

    test('calcParams mặc định [6,12,24] khai báo nhưng KHÔNG dùng trong calc() — luôn hard-code 14', () {
      // RSIIndicator không cho constructor tự truyền calcParams (period 14 bị
      // hard-code trong calc(), không đọc từ calcParams) — xem indicator.md §2 RSI.
      expect(RSIIndicator().calcParams, const [6, 12, 24]);
    });
  });
}
