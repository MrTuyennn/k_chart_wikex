import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('AVLIndicator', () {
    test('AVL = amount / vol khi có amount hợp lệ', () {
      final data = buildKLines(40); // builder luôn cho amount > 0, vol > 0
      AVLIndicator().calc(data);
      for (final e in data) {
        expect(e.avl, closeTo(e.amount! / e.vol, 1e-9));
      }
    });

    test('fallback (high+low+close)/3 khi amount null', () {
      final e = KLineEntity.fromCustom(
        open: 10,
        close: 12,
        high: 15,
        low: 9,
        vol: 100,
        time: 0,
      ); // amount không truyền -> null
      AVLIndicator().calc([e]);
      expect(e.avl, closeTo((15 + 9 + 12) / 3, 1e-9));
    });

    test('fallback (high+low+close)/3 khi amount <= 0', () {
      final e = KLineEntity.fromCustom(
        open: 10,
        close: 12,
        high: 15,
        low: 9,
        vol: 100,
        amount: 0,
        time: 0,
      );
      AVLIndicator().calc([e]);
      expect(e.avl, closeTo((15 + 9 + 12) / 3, 1e-9));
    });

    test('fallback (high+low+close)/3 khi vol = 0', () {
      final e = KLineEntity.fromCustom(
        open: 10,
        close: 12,
        high: 15,
        low: 9,
        vol: 0,
        amount: 500,
        time: 0,
      );
      AVLIndicator().calc([e]);
      expect(e.avl, closeTo((15 + 9 + 12) / 3, 1e-9));
    });

    test('AVL luôn nằm trong [low, high] của chính nến đó', () {
      final data = buildKLines(40);
      AVLIndicator().calc(data);
      for (final e in data) {
        expect(e.avl!, greaterThanOrEqualTo(e.low - 1e-9));
        expect(e.avl!, lessThanOrEqualTo(e.high + 1e-9));
      }
    });

    test('dataList rỗng không crash', () {
      expect(() => AVLIndicator().calc(<KLineEntity>[]), returnsNormally);
    });
  });
}
