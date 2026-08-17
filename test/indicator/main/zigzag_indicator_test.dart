import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('ZigZagIndicator', () {
    test('trace tay: depth=1,backstep=0 -> mọi điểm (trừ điểm đầu) là pivot, zigzag = chính giá đó', () {
      // Với depth=1 & backstep=0, không có bước "xác nhận không bị phá" (vòng
      // for k=1..backstep rỗng) nên bất kỳ điểm nào không nhỏ hơn/lớn hơn
      // hàng xóm bên trái đều được coi là pivot — với dãy zig-zag thực sự thì
      // MỌI điểm từ index 1 trở đi đều là pivot, giá trị giữ nguyên.
      final prices = [1.0, 3.0, 2.0, 5.0, 1.0, 4.0, 2.0];
      // Nến "điểm" — open=high=low=close=price[i] (KHÔNG dùng buildKLinesFromCloses
      // vì nó tạo thân nến open=close[i-1]..close[i], khiến high/low lệch khỏi price[i]).
      final data = buildKLinesFromOHLCV([for (final p in prices) (p, p, p, p, 1.0)]);
      final indicator = ZigZagIndicator(calcParams: const [1, 0, 5]);
      indicator.calc(data);

      expect(data[0].zigzag, isNull);
      for (int i = 1; i < prices.length; i++) {
        expect(data[i].zigzag, closeTo(prices[i], 1e-9), reason: 'i=$i');
      }
    });

    test('mọi giá trị zigzag không-null nằm trong [min low, max high] toàn chuỗi', () {
      final data = buildKLines(80); // calcParams mặc định [12, 2, 5]
      ZigZagIndicator().calc(data);
      final minLow = data.map((e) => e.low).reduce(min);
      final maxHigh = data.map((e) => e.high).reduce(max);
      for (final e in data) {
        if (e.zigzag == null) continue;
        expect(e.zigzag!, greaterThanOrEqualTo(minLow - 1e-9));
        expect(e.zigzag!, lessThanOrEqualTo(maxHigh + 1e-9));
      }
    });

    test('dataList rỗng không crash', () {
      expect(() => ZigZagIndicator().calc(<KLineEntity>[]), returnsNormally);
    });

    test('gọi calc 2 lần cho kết quả giống hệt nhau (idempotent, reset đúng field cũ)', () {
      final data = buildKLines(50);
      final indicator = ZigZagIndicator();
      indicator.calc(data);
      final first = data.map((e) => e.zigzag).toList();
      indicator.calc(data);
      final second = data.map((e) => e.zigzag).toList();
      expect(second, first);
    });
  });
}
