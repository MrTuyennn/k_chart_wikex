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

  // §5.2-ext — minVisibleTicks / viewportWidth. Reported bug: 4h candles
  // zoomed way out collapse to Fallback B's single tick because the
  // weight-ladder threshold jumps straight from DAY to MONTH (~30x gap) at
  // that barSpacing, even though the viewport has plenty of room left for
  // more labels. `viewportWidth`/`minVisibleTicks` back-fills those gaps
  // with evenly-spaced synthetic candidates (never displacing a real
  // calendar-boundary tick) so a window of `viewportWidth` reliably shows
  // close to `minVisibleTicks` ticks instead of 1.
  group('buildTimeTickPlan — minVisibleTicks floor (§5.2-ext)', () {
    int worstCaseVisible(
      List<TimeTick> plan,
      double barSpacing,
      int candleCount,
      double viewportWidth,
    ) {
      int worst = 1 << 30;
      for (
        double lo = 0;
        lo < candleCount * barSpacing - viewportWidth;
        lo += viewportWidth / 20
      ) {
        final count = plan.where((t) {
          final absX = t.index * barSpacing + barSpacing / 2;
          return absX >= lo && absX <= lo + viewportWidth;
        }).length;
        if (count < worst) worst = count;
      }
      return worst == 1 << 30 ? plan.length : worst;
    }

    test(
      'reported case: 4h candles zoomed to minScale collapse to 1 tick '
      'without the floor, reach kMinVisibleAxisTicks with it',
      () {
        const intervalMs = 4 * 3600000; // 4h
        const barSpacing = 2.2; // ~pointWidth(11) * default minScale(0.2)
        const viewportWidth = 400.0; // typical phone width
        final candles = _syntheticCandles(count: 4400, intervalMs: intervalMs);

        final withoutFloor = buildTimeTickPlan(
          candles: candles,
          barSpacing: barSpacing,
          intervalMs: intervalMs,
        );
        final withFloor = buildTimeTickPlan(
          candles: candles,
          barSpacing: barSpacing,
          intervalMs: intervalMs,
          viewportWidth: viewportWidth,
          minVisibleTicks: kMinVisibleAxisTicks,
        );

        final before = worstCaseVisible(
          withoutFloor,
          barSpacing,
          candles.length,
          viewportWidth,
        );
        final after = worstCaseVisible(
          withFloor,
          barSpacing,
          candles.length,
          viewportWidth,
        );
        expect(before, lessThan(kMinVisibleAxisTicks), reason: 'reproduces the reported bug');
        expect(after, greaterThanOrEqualTo(kMinVisibleAxisTicks));
      },
    );

    test('kMinGapX never violated by inserted filler ticks', () {
      for (final intervalMs in [4 * 3600000, 86400000, 3600000, 900000]) {
        final candles = _syntheticCandles(count: 6000, intervalMs: intervalMs);
        for (final barSpacing in [2.2, 5.0, 11.0, 30.0]) {
          for (final viewportWidth in [360.0, 400.0, 800.0]) {
            final plan = buildTimeTickPlan(
              candles: candles,
              barSpacing: barSpacing,
              intervalMs: intervalMs,
              viewportWidth: viewportWidth,
              minVisibleTicks: 5,
            );
            final xs =
                plan.map((t) => t.index * barSpacing + barSpacing / 2).toList()
                  ..sort();
            for (int i = 1; i < xs.length; i++) {
              expect(
                xs[i] - xs[i - 1],
                greaterThanOrEqualTo(kMinGapX - 0.01),
                reason:
                    'interval=$intervalMs barSpacing=$barSpacing '
                    'viewportWidth=$viewportWidth',
              );
            }
          }
        }
      }
    });

    test('filler only adds candidates, never displaces a real weight tick', () {
      const intervalMs = 900000; // 15m — dense enough to not need filling
      const barSpacing = 20.0;
      final candles = _syntheticCandles(count: 2000, intervalMs: intervalMs);
      final withoutFloor = buildTimeTickPlan(
        candles: candles,
        barSpacing: barSpacing,
        intervalMs: intervalMs,
      );
      final withFloor = buildTimeTickPlan(
        candles: candles,
        barSpacing: barSpacing,
        intervalMs: intervalMs,
        viewportWidth: 400,
        minVisibleTicks: 5,
      );
      final withoutIdx = withoutFloor.map((t) => t.index).toSet();
      final withIdx = withFloor.map((t) => t.index).toSet();
      expect(withoutIdx.difference(withIdx), isEmpty);
    });

    test('default (viewportWidth: 0) is unchanged — floor is opt-in', () {
      const intervalMs = 4 * 3600000;
      const barSpacing = 2.2;
      final candles = _syntheticCandles(count: 4400, intervalMs: intervalMs);
      final a = buildTimeTickPlan(
        candles: candles,
        barSpacing: barSpacing,
        intervalMs: intervalMs,
      );
      final b = buildTimeTickPlan(
        candles: candles,
        barSpacing: barSpacing,
        intervalMs: intervalMs,
        viewportWidth: 0,
      );
      expect(
        a.map((t) => t.index).toList(),
        equals(b.map((t) => t.index).toList()),
      );
    });
  });

  // axisFormatFor — default X-axis label pattern (used by
  // BaseChartPainter._axisFormatFor when the consumer hasn't set
  // timeFormat/dateTimeFormat). "Scale nhỏ -> gom ngày bỏ giờ, scale lớn ->
  // chi tiết giờ:phút" (user request) — verified across timeframes/zoom.
  group('axisFormatFor', () {
    test('30m: fine detail when zoomed in, gains a date once zoomed out', () {
      const intervalMs = 1800000;
      expect(axisFormatFor(60.0, intervalMs), kAxisFormatMinute);
      expect(axisFormatFor(2.2, intervalMs), kAxisFormatHour);
    });

    test('4H: never bare HH:mm (natural floor), escalates to day-only when zoomed out', () {
      const intervalMs = 4 * 3600000;
      expect(axisFormatFor(60.0, intervalMs), kAxisFormatHour);
      expect(axisFormatFor(2.2, intervalMs), kAxisFormatDay);
    });

    test('1D: always day-only regardless of zoom (candles are always local midnight)', () {
      const intervalMs = 86400000;
      for (final barSpacing in [2.2, 5.0, 11.0, 22.0, 60.0]) {
        expect(
          axisFormatFor(barSpacing, intervalMs),
          kAxisFormatDay,
          reason: 'barSpacing=$barSpacing — a 1D candle is never anything but 00:00 local, '
              'so HH:mm would repeat "00:00" for every tick regardless of zoom',
        );
      }
    });

    test('never coarser than kAxisFormatDay, never finer than kAxisFormatMinute', () {
      const validPatterns = [kAxisFormatMinute, kAxisFormatHour, kAxisFormatDay];
      for (final intervalMs in [60000, 300000, 900000, 1800000, 3600000, 14400000, 86400000]) {
        for (final barSpacing in [1.0, 2.2, 5.0, 11.0, 22.0, 44.0, 60.0]) {
          expect(validPatterns, contains(axisFormatFor(barSpacing, intervalMs)));
        }
      }
    });

    // Reported bug: 1H candles zoomed all the way to the default minScale
    // (0.2 -> barSpacing = pointWidth(11) * 0.2 = 2.2) stayed stuck at
    // "MM-dd HH:mm" forever — thresholdRung() alone never reaches kDay for
    // this interval because it measures candidate ELIGIBILITY *before*
    // kMinGapX packing, not what actually survives packing. Fixed by adding
    // an independent "day density" check: if 1 calendar day spans fewer
    // pixels than kMinGapX, no 2 same-day ticks (real or filler) can ever
    // both survive packing, so kAxisFormatDay is safe regardless of
    // thresholdRung.
    test('1H at minScale reaches kAxisFormatDay (previously stuck at kAxisFormatHour)', () {
      const intervalMs = 3600000;
      const minScaleBarSpacing = 11.0 * 0.2; // pointWidth(11) * default minScale(0.2)
      expect(axisFormatFor(minScaleBarSpacing, intervalMs), kAxisFormatDay);
    });

    test('finer-than-1H timeframes correctly stay at kAxisFormatHour at minScale — not over-corrected', () {
      const minScaleBarSpacing = 11.0 * 0.2;
      for (final intervalMs in [300000, 900000, 1800000]) {
        expect(
          axisFormatFor(minScaleBarSpacing, intervalMs),
          kAxisFormatHour,
          reason: 'interval=$intervalMs: 1 calendar day still spans >= kMinGapX px at this '
              'barSpacing, so 2 same-day ticks COULD both survive packing — date-only would '
              'be ambiguous here, must stay at MM-dd HH:mm',
        );
      }
    });

    test('day-density check never produces 2 adjacent date-only ticks on the same calendar day', () {
      // Xây plan THẬT (không chỉ gọi axisFormatFor) cho 1H ở minScale — verify
      // không có label trùng liền kề (sẽ trùng nếu 2 tick cùng ngày mà format
      // lại là date-only).
      const intervalMs = 3600000;
      const barSpacing = 2.2;
      final candles = _syntheticCandles(count: 20000, intervalMs: intervalMs);
      final format = axisFormatFor(barSpacing, intervalMs);
      expect(format, kAxisFormatDay);
      final plan = buildTimeTickPlan(
        candles: candles,
        barSpacing: barSpacing,
        intervalMs: intervalMs,
        forcedFormat: format,
        viewportWidth: 400,
        minVisibleTicks: kMinVisibleAxisTicks,
      );
      for (int i = 1; i < plan.length; i++) {
        expect(
          plan[i].label == plan[i - 1].label,
          isFalse,
          reason: 'ticks ${plan[i - 1].index}/${plan[i].index} share label "${plan[i].label}"',
        );
      }
    });

    test('day-density boundary: exactly kMinGapX px/day stays conservative (strict <, not <=)', () {
      const barSpacing = 2.2;
      // intervalMs chosen so pixelsPerDay lands exactly on kMinGapX.
      final boundaryIntervalMs = (24 * 60 * 60 * 1000 * barSpacing / kMinGapX).round();
      expect(axisFormatFor(barSpacing, boundaryIntervalMs), isNot(kAxisFormatDay));
      expect(axisFormatFor(barSpacing, boundaryIntervalMs + 1), kAxisFormatDay);
    });
  });
}
