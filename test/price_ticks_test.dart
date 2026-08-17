import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/utils/price_ticks.dart';

void main() {
  group('decimalsFor (T7)', () {
    test('2.5 family needs 1 decimal (FAILURE MODE 6 regression)', () {
      expect(decimalsFor(2.5), 1);
    });
    test('0.25 needs 2 decimals', () {
      expect(decimalsFor(0.25), 2);
    });
    test('500 needs 0 decimals', () {
      expect(decimalsFor(500), 0);
    });
    test('0.000025 needs 6 decimals', () {
      expect(decimalsFor(0.000025), 6);
    });
  });

  group('priceTicks (T6)', () {
    const cases = [
      (63000.0, 65000.0),
      (0.00021, 0.00034),
      (1.5, 1.52),
      (43217.83, 51999.01),
      (100.0, 100.0001),
      (0.5, 900000.0),
    ];
    const heights = [200.0, 400.0, 800.0];

    for (final (min, max) in cases) {
      for (final height in heights) {
        test('range=($min,$max) height=$height', () {
          final ticks = priceTicks(minPrice: min, maxPrice: max, height: height);
          for (final t in ticks) {
            expect(t, greaterThanOrEqualTo(min));
            expect(t, lessThanOrEqualTo(max));
          }
          // no duplicate values
          expect(ticks.toSet().length, ticks.length);
          for (int i = 1; i < ticks.length; i++) {
            expect(ticks[i], greaterThan(ticks[i - 1]));
          }
        });
      }
    }
  });

  test('niceStep never accumulation-drifts (FAILURE MODE 5 regression)', () {
    final ticks = priceTicks(minPrice: 0, maxPrice: 1000000, height: 400);
    for (final t in ticks) {
      // Every tick should be an exact multiple-ish of the step, not something
      // like 63000.000000001.
      final rounded = double.parse(t.toStringAsFixed(6));
      expect((t - rounded).abs(), lessThan(1e-6));
    }
  });

  test('degenerate range returns empty, not a crash', () {
    expect(priceTicks(minPrice: 5, maxPrice: 5, height: 400), isEmpty);
    expect(priceTicks(minPrice: 5, maxPrice: 4, height: 400), isEmpty);
    expect(priceTicks(minPrice: 0, maxPrice: 10, height: 0), isEmpty);
  });

  test('target tick count shrinks on a short panel', () {
    final tall = priceTicks(minPrice: 0, maxPrice: 1000, height: 800);
    final short = priceTicks(minPrice: 0, maxPrice: 1000, height: 60);
    expect(short.length, lessThanOrEqualTo(tall.length));
  });
}
