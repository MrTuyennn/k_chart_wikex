import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('IchimokuIndicator', () {
    test('tenkan/kijun/spanA/spanB khớp oracle sliding-window naive (O(n*period))', () {
      final data = buildKLines(80);
      const tenkanP = 9, kijunP = 26, spanBP = 52;
      IchimokuIndicator().calc(data); // calcParams mặc định [9, 26, 52]

      for (int i = 0; i < data.length; i++) {
        final v = data[i].ichimoku!;

        final tenkan = _midOfWindow(data, i, tenkanP);
        final kijun = _midOfWindow(data, i, kijunP);
        final spanB = _midOfWindow(data, i, spanBP);

        expect(v.tenkan, tenkan == null ? isNull : closeTo(tenkan, 1e-9), reason: 'i=$i tenkan');
        expect(v.kijun, kijun == null ? isNull : closeTo(kijun, 1e-9), reason: 'i=$i kijun');
        expect(v.spanB, spanB == null ? isNull : closeTo(spanB, 1e-9), reason: 'i=$i spanB');

        if (tenkan != null && kijun != null) {
          expect(v.spanA, closeTo((tenkan + kijun) / 2, 1e-9), reason: 'i=$i spanA');
        } else {
          expect(v.spanA, isNull, reason: 'i=$i spanA');
        }
      }
    });

    test('shift == calcParams[1] (kijun period) và futureShift == shift', () {
      final indicator = IchimokuIndicator(calcParams: const [9, 26, 52]);
      expect(indicator.shift, 26);
      expect(indicator.futureShift, 26);

      final custom = IchimokuIndicator(calcParams: const [7, 22, 44]);
      expect(custom.shift, 22);
      expect(custom.futureShift, 22);
    });

    test('dataList rỗng không crash', () {
      expect(() => IchimokuIndicator().calc(<KLineEntity>[]), returnsNormally);
    });
  });
}

/// Oracle sliding-window kiểu naive (duyệt trực tiếp `period` nến gần nhất,
/// KHÔNG dùng monotonic deque) — thuật toán khác hẳn `_slidingMax`/`_slidingMin`
/// trong source, dùng để cross-check độc lập.
double? _midOfWindow(List<KLineEntity> data, int i, int period) {
  if (i < period - 1) return null;
  double maxH = data[i - period + 1].high;
  double minL = data[i - period + 1].low;
  for (int j = i - period + 2; j <= i; j++) {
    if (data[j].high > maxH) maxH = data[j].high;
    if (data[j].low < minL) minL = data[j].low;
  }
  return (maxH + minL) / 2;
}
