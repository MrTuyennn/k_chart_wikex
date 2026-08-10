import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/k_line_entity.dart';
import 'package:k_chart_jk/utils/time_ticks.dart';

List<KLineEntity> _syntheticCandles({
  required int count,
  required int intervalMs,
  int startTime = 1700000000000,
}) {
  return List.generate(
    count,
    (i) => KLineEntity.fromCustom(
      time: startTime + i * intervalMs,
      open: 100,
      close: 100,
      high: 101,
      low: 99,
      vol: 1,
    ),
  );
}

void main() {
  // Sweep loosely modelled on CHART_AXES.md §10 T1/T2 (never blank, no
  // overlapping labels) — not the full 4410-configuration matrix, but enough
  // to catch a broken threshold/bucket implementation.
  const barSpacings = [2.0, 5.0, 11.0, 22.0, 44.0, 60.0];
  const intervals = [60000, 300000, 3600000, 86400000]; // 1m, 5m, 1h, 1D

  group('buildTimeTickPlan — never blank (T1) / min gap (T2)', () {
    for (final barSpacing in barSpacings) {
      for (final intervalMs in intervals) {
        test('barSpacing=$barSpacing interval=$intervalMs', () {
          final candles = _syntheticCandles(count: 1500, intervalMs: intervalMs);
          final plan = buildTimeTickPlan(
            candles: candles,
            barSpacing: barSpacing,
            intervalMs: intervalMs,
          );
          expect(plan, isNotEmpty, reason: 'axis must never be blank');

          // Reconstruct absX the same way the planner does, to check spacing.
          double absX(int i) => i * barSpacing + barSpacing / 2;
          for (int i = 1; i < plan.length; i++) {
            final gap = (absX(plan[i].index) - absX(plan[i - 1].index)).abs();
            expect(
              gap,
              greaterThanOrEqualTo(kMinGapX - 1e-9),
              reason: 'ticks ${plan[i - 1].index} and ${plan[i].index} are too close',
            );
          }
        });
      }
    }
  });

  test('no adjacent duplicate labels (T3)', () {
    final candles = _syntheticCandles(count: 1500, intervalMs: 14400000); // 4h
    final plan = buildTimeTickPlan(
      candles: candles,
      barSpacing: 8.0,
      intervalMs: 14400000,
    );
    for (int i = 1; i < plan.length; i++) {
      expect(
        plan[i].label == plan[i - 1].label,
        isFalse,
        reason: 'adjacent ticks must not share the same label text',
      );
    }
  });

  test('pan does not change tick selection (I4)', () {
    // The planner only takes barSpacing/interval — it has no scrollOffset
    // input at all, so two calls with the same key must be identical
    // regardless of any notion of "where the viewport currently is".
    final candles = _syntheticCandles(count: 1500, intervalMs: 60000);
    final plan1 = buildTimeTickPlan(
      candles: candles,
      barSpacing: 11.0,
      intervalMs: 60000,
    );
    final plan2 = buildTimeTickPlan(
      candles: candles,
      barSpacing: 11.0,
      intervalMs: 60000,
    );
    expect(
      plan1.map((t) => t.index).toList(),
      plan2.map((t) => t.index).toList(),
    );
  });

  test('append stability (T5) — existing candles keep their tickWeight', () {
    final candles = _syntheticCandles(count: 200, intervalMs: 3600000);
    buildTimeTickPlan(candles: candles, barSpacing: 20.0, intervalMs: 3600000);
    final before = candles.map((c) => c.tickWeight).toList();

    candles.add(
      KLineEntity.fromCustom(
        time: (candles.last.time ?? 0) + 3600000,
        open: 100,
        close: 100,
        high: 101,
        low: 99,
        vol: 1,
      ),
    );
    buildTimeTickPlan(candles: candles, barSpacing: 20.0, intervalMs: 3600000);
    final after = candles.sublist(0, before.length).map((c) => c.tickWeight);

    expect(after, before);
    expect(candles.last.tickWeight, isNotNull);
  });

  test('detectIntervalMs ignores non-positive/duplicate gaps', () {
    final candles = _syntheticCandles(count: 5, intervalMs: 60000);
    // Duplicate the second timestamp (0 diff) — should be ignored, not
    // collapse the detected interval to 0.
    candles[2] = KLineEntity.fromCustom(
      time: candles[1].time,
      open: 100,
      close: 100,
      high: 101,
      low: 99,
      vol: 1,
    );
    expect(detectIntervalMs(candles), 60000);
  });

  test('detectIntervalMs falls back to 60s with no positive gaps', () {
    expect(detectIntervalMs([]), 60000);
  });

  test('label granularity escalates with weight (§5.3)', () {
    final yearStart = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    final monthStart = DateTime(2026, 8, 1).millisecondsSinceEpoch;
    final dayStart = DateTime(2026, 8, 10).millisecondsSinceEpoch;
    final midDay = DateTime(2026, 8, 10, 9, 5).millisecondsSinceEpoch;

    final candles = [
      KLineEntity.fromCustom(
        time: yearStart,
        open: 1,
        close: 1,
        high: 1,
        low: 1,
        vol: 1,
      ),
      KLineEntity.fromCustom(
        time: monthStart,
        open: 1,
        close: 1,
        high: 1,
        low: 1,
        vol: 1,
      ),
      KLineEntity.fromCustom(
        time: dayStart,
        open: 1,
        close: 1,
        high: 1,
        low: 1,
        vol: 1,
      ),
      KLineEntity.fromCustom(
        time: midDay,
        open: 1,
        close: 1,
        high: 1,
        low: 1,
        vol: 1,
      ),
    ];
    // Force every candle to be a candidate (threshold = MINOR) with a huge
    // barSpacing, and a large enough gap in ms that nothing collides.
    final plan = buildTimeTickPlan(
      candles: candles,
      barSpacing: 1000.0,
      intervalMs: 86400000,
    );
    final byIndex = {for (final t in plan) t.index: t.label};
    expect(byIndex[0], '2026');
    expect(byIndex[1], 'Aug');
    expect(byIndex[2], '10');
    expect(byIndex[3], '09:05');
  });

  test('forcedFormat overrides adaptive labelling', () {
    final candles = _syntheticCandles(count: 10, intervalMs: 86400000);
    final plan = buildTimeTickPlan(
      candles: candles,
      barSpacing: 40.0,
      intervalMs: 86400000,
      forcedFormat: const ['x'],
    );
    expect(plan, isNotEmpty);
    for (final t in plan) {
      expect(t.label, 'x');
    }
  });
}
