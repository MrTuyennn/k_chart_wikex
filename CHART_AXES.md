# Candlestick chart axes — specification

Single source of truth for the time axis and the price axis. Supersedes the
earlier split into `SPEC.md` / `ALGORITHM.md` / `PLAN.md`.

**Audience: an AI coding agent.** This file is self-contained. Implement from it
directly; do not look for a reference implementation.

**Goal:** a candlestick chart whose time axis pans and zooms in perfect lockstep
with the candles and the grid, and whose price axis lands on round numbers —
matching the behaviour of MEXC / Binance / TradingView.

Platform-agnostic. Pseudocode is neutral; per-platform notes are in Appendix C.

Contents: §1 invariants · §2 model · §3 constants · §4 X transform ·
§5 tick selection · §6 price axis · §7 layout · §8 rendering · §9 realtime ·
§10 acceptance tests · appendices A–E.

---

## 0. How to use this document

1. Read §1 (invariants). Violating any of them produces a visibly broken chart.
2. Implement §3–§8 in order. Each has exact formulas — do not improvise.
3. Run every test in §10. They are acceptance criteria, not suggestions.
4. If a test fails, re-read the numbered "FAILURE MODE" note attached to that
   section. Each documents a real bug that this spec exists to prevent.

Do not simplify the algorithm because a simpler version "looks fine" on one
screenshot. Every rule here failed a specific test before it was added.

---

## 1. Invariants

These must hold at all times. State them back to yourself before coding.

- **I1.** The X axis is index-based, never time-based. Candle `i` sits exactly
  `barSpacing` pixels after candle `i−1`, regardless of the real time gap.
- **I2.** Exactly one source of truth for the X transform. Grid, candles, time
  axis and crosshair all read the same viewport object. No second scroll
  controller, no listener syncing two states.
- **I3.** Time ticks are computed **once per frame** at a layer above the
  renderers, then handed to both the grid and the axis. A renderer must never
  select its own ticks.
- **I4.** Tick selection runs in absolute pixel space. `scrollOffset` is
  subtracted only at draw time. Panning cannot change which ticks are selected.
- **I5.** The X and Y axes are separate systems. They touch at exactly one
  point: the visible index range feeds the price range (§6.2). Layout expresses
  this too — see §7.
- **I6.** Grid line and its label share one x coordinate, computed once.
- **I7.** Every timestamp stored is UTC epoch milliseconds. Timezone is a
  formatting concern only — but calendar boundary detection uses **local** time.

### 1.1 The two axes are not symmetric

The most common conceptual error is assuming X and Y work the same way. They do
not, and the difference drives every design decision below.

| | X (time) | Y (price) |
| --- | --- | --- |
| Domain | discrete — candle index | continuous — real numbers |
| Labels anchor to | a **candle** | a **round number** |
| Priority ordering | yes, a 12-rung ladder | none, all values equal |
| On zoom | labels are added/removed; survivors do not move | the whole set is regenerated from a new step |
| State | persists across frames (cached plan) | rebuilt every frame |
| Selection cost | O(n) on zoom, O(1) on pan | O(ticks) every frame |

In one sentence: **X filters, Y generates.**

---

## 2. Data model

### 2.1 Notation

| Symbol | Meaning | Field |
| --- | --- | --- |
| `i` | logical candle index, 0-based | `index` |
| `s` | pixels per candle | `barSpacing` |
| `o` | pixels scrolled from candle 0 | `scrollOffset` |
| `W` | width of the plot area | `viewportWidth` |
| `H` | height of the plot area | `scale.height` |
| `Δt` | milliseconds per candle | `detectInterval()` |
| `g` | minimum label gap | `MIN_GAP_X` = 64, `MIN_GAP_Y` = 32 |
| `n` | candle count | `candleCount` |

```
Candle:
    openTime   : int      # UTC epoch ms, aligned: floor(ts/interval)*interval
    open       : float
    high       : float
    low        : float
    close      : float
    volume     : float
    tickWeight : int      # computed once at load, cached; see §4
```

```
Viewport:                 # X transform, persists across frames
    barSpacing    : float # pixels per candle
    scrollOffset  : float # pixels scrolled from candle 0
    candleCount   : int
    viewportWidth : float # width of the plot area
```

```
PriceScale:               # Y transform, rebuilt every frame
    minPrice : float
    maxPrice : float
    height   : float
```

```
TimeTick:  { index: int, x: float, label: string, weight: int }
PriceTick: { price: float, y: float, label: string }
```

---

## 3. Constants

Use these exact values.

| Name | Value | Meaning |
| --- | --- | --- |
| `MIN_GAP_X` | 64.0 | min pixels between time labels |
| `MIN_GAP_Y` | 32.0 | min pixels between price labels |
| `SURPLUS` | 4.0 | candidate surplus factor (§5.1) |
| `TARGET_PRICE_TICKS` | 6 | desired price gridline count |
| `PRICE_PAD_FRACTION` | 0.08 | headroom above/below price range |
| `RIGHT_PAD_FRACTION` | 0.15 | empty space after newest candle |
| `MIN_BAR_SPACING` | 2.0 | |
| `MAX_BAR_SPACING` | 60.0 | |
| `BODY_WIDTH_RATIO` | 0.75 | candle body width as fraction of spacing |

Tick weight ladder — use these exact integers. Gaps are deliberate so rungs can
be inserted later without renumbering.

| Rung | Value | Nominal period (ms) |
| --- | --- | --- |
| `MINOR` | 0 | 0 |
| `MIN1` | 10 | 60 000 |
| `MIN5` | 11 | 300 000 |
| `MIN15` | 12 | 900 000 |
| `MIN30` | 13 | 1 800 000 |
| `HOUR1` | 20 | 3 600 000 |
| `HOUR3` | 21 | 10 800 000 |
| `HOUR6` | 22 | 21 600 000 |
| `HOUR12` | 23 | 43 200 000 |
| `DAY` | 30 | 86 400 000 |
| `MONTH` | 40 | 2 629 746 000 |
| `YEAR` | 50 | 31 556 952 000 |

`LADDER` = that list in ascending order. Month and year periods are averages;
they only select a rung, they never position a tick.

---

## 4. X transform

```
x(i)       = i * barSpacing - scrollOffset
center(i)  = i * barSpacing + barSpacing/2 - scrollOffset     # I6: use for BOTH grid and label
indexAt(x) = floor((x + scrollOffset) / barSpacing)

firstVisible = clamp(floor(scrollOffset / barSpacing), 0, candleCount-1)
lastVisible  = clamp(ceil((scrollOffset + viewportWidth) / barSpacing), 0, candleCount-1)

maxScrollOffset = max(0, candleCount*barSpacing - viewportWidth
                          + viewportWidth*RIGHT_PAD_FRACTION)
clampScroll()   : scrollOffset = clamp(scrollOffset, 0, maxScrollOffset)

isAtRightEdge   = scrollOffset >= maxScrollOffset - barSpacing
```

Zoom anchored on a focal pixel `xf` (the pinch centre or mouse position):

```
zoomAt(xf, newSpacing):
    logical      = (scrollOffset + xf) / barSpacing      # BEFORE changing barSpacing
    barSpacing   = clamp(newSpacing, MIN_BAR_SPACING, MAX_BAR_SPACING)
    scrollOffset = logical * barSpacing - xf
    clampScroll()
```

> **FAILURE MODE 1.** Computing `logical` after mutating `barSpacing` makes the
> chart slide out from under the pointer while zooming.

Always iterate `firstVisible..lastVisible`, never the whole array.

---

## 5. Tick weights

Compute **once** when data loads and for each appended candle. Cache on the
candle. Never recompute per frame — it allocates a date object per candle.

```
assignTickWeights(candles):
    if candles empty: return
    prev = localDateTime(candles[0].openTime)
    candles[0].tickWeight = alignmentWeight(prev)
    for i in 1..n-1:
        cur = localDateTime(candles[i].openTime)
        candles[i].tickWeight = max(alignmentWeight(cur), crossingWeight(prev, cur))
        prev = cur
```

```
alignmentWeight(t):                      # t is LOCAL time
    if t.minute != 0:
        if t.minute % 30 == 0: return MIN30
        if t.minute % 15 == 0: return MIN15
        if t.minute % 5  == 0: return MIN5
        return MIN1
    if t.hour != 0:
        if t.hour % 12 == 0: return HOUR12
        if t.hour % 6  == 0: return HOUR6
        if t.hour % 3  == 0: return HOUR3
        return HOUR1
    if t.day   != 1: return DAY
    if t.month != 1: return MONTH
    return YEAR

crossingWeight(prev, cur):
    if cur.year  != prev.year:  return YEAR
    if cur.month != prev.month: return MONTH
    if cur.day   != prev.day:   return DAY
    if cur.hour  != prev.hour:  return HOUR1
    return MINOR
```

Both sources are required. `alignmentWeight` keeps labels available at deep
zoom, where no hour or day boundary may be on screen at all. `crossingWeight`
handles intervals that don't line up with local midnight — 4h candles at GMT+7
land on 03:00 / 07:00 / 11:00, so no candle has `hour == 0`, yet the first bar
of each day must still be marked.

> **FAILURE MODE 2.** A coarse 5-rung ladder (`minor/hour/day/month/year`)
> leaves the time axis **completely empty** at most zoom levels. Measured: 1m
> data blank at 4 of 7 zoom levels, 5m at 2 of 7, 1h at 3 of 7. Do not collapse
> the ladder.

Bar interval, used by §5.1:

```
detectInterval(candles):
    # minimum, not mean — exchange downtime must not skew it
    return min(candles[i+1].openTime - candles[i].openTime
               for i in 0..min(n-2, 63) if diff > 0)  or 60000 if none
```

---

## 5.1 Threshold — derive from geometry

A rung with period `P` places a mark every `P * barSpacing / interval` pixels.
Require that to clear `MIN_GAP_X / SURPLUS`:

```
required = MIN_GAP_X * interval / (barSpacing * SURPLUS)

thresholdFor(barSpacing, interval):
    for rung in LADDER:                       # ascending
        period = max(periodOf(rung), interval)
        if period >= required: return rung
    return LADDER.last
```

`SURPLUS = 4` deliberately keeps ~4x more candidates than will survive packing,
so §5.2 has real choices. Clamping to the exact budget makes the axis jump a
whole rung at a time — daily candles go from one "Aug" label straight to nothing
usable.

> **FAILURE MODE 3.** Deriving the threshold by **counting visible candidates**
> instead. That count wobbles by ±1 as you scroll, flipping the rung back and
> forth and making labels flicker. Measured: 168 jitters over 2212 pan steps.
> The formula above depends only on `barSpacing` and `interval`, both invariant
> under panning.

---

## 5.2 Tick planning — absolute space (I4)

**This is the most important section. Read it twice.**

Planning runs on absolute coordinates, with `scrollOffset` excluded:

```
absX(i) = i * barSpacing + barSpacing/2
```

Distances between candidates then depend on `barSpacing` alone, so scrolling
cannot change which candidates win. Stability is structural, not tuned.

```
buildPlan(candles, barSpacing, interval):
    threshold = thresholdFor(barSpacing, interval)

    candidates = [ (i, absX(i), weight_i, label_i)
                   for i in 0..n-1 if candles[i].tickWeight >= threshold ]

    if candidates empty:                                  # fallback A
        step = max(1, ceil(MIN_GAP_X / barSpacing))
        candidates = [ (i, absX(i), ...) for i in 0..n-1 step step ]

    sort candidates by (weight DESC, index ASC)

    buckets = {}          # int -> list of accepted absX
    accepted = []
    for c in candidates:
        b = floor(c.absX / MIN_GAP_X)
        clash = any(|c.absX - ax| < MIN_GAP_X
                    for ax in buckets[b-1] + buckets[b] + buckets[b+1])
        if clash: continue
        buckets[b].append(c.absX)
        accepted.append(c)

    sort accepted by absX
    return accepted
```

Three details that are not optional:

**Sort by weight, not by position.** A plain left-to-right greedy pass takes
whichever candle it meets first in each slot. On 4h data that yields
`11:00, 11:00, 11:00, 11:00, 11:00` — five identical labels. Weight-first lets
the day boundary outrank the arbitrary intraday bar, giving `8, 9, 10`.

**Tie-break by index**, never by "distance from viewport start" — the result
must not depend on where the visible range happens to begin.

**Bucketed clash test.** A candidate can only collide with something in its own
cell or the two neighbours, so this is O(1) per candidate. A naive scan over
everything accepted so far is O(k²) and stalls the frame: measured 688 ms for
20 000 candles versus 5.1 ms bucketed; 100 000 candles is 63 ms bucketed.

> **FAILURE MODE 4.** Planning only over the **visible** range. A candidate
> entering at the screen edge displaces one already on screen, and the
> displacement chains inward. Measured 217 jitters over 2212 pan steps even
> after Failure Mode 3 was fixed. Absolute-space planning measures 0. Padding
> the visible range does not fix this properly — it took ~1024 px of padding to
> reach zero jitter, at 3x the candidate cost.

### Caching

The plan depends only on `(barSpacing, candleCount, interval)`. Cache it.
Rebuild on zoom or data change; reuse unchanged across every pan frame.

This is what makes the O(n) rebuild affordable: pan frames cost a binary search
plus a short walk, independent of history length. Measured on 100 000 candles:
rebuild 122 ms, pan frame 0.005 ms (Python; a compiled language is ~5–10x
faster on the rebuild).

For datasets beyond roughly 50 000 candles the rebuild becomes a visible hitch
on the first frame of a zoom gesture. Mitigations, in order of preference:
debounce the rebuild until the pinch settles and paint the previous plan
meanwhile; or cap retained history. Do **not** switch back to viewport-local
planning to make it cheaper — that reintroduces Failure Mode 4.

### Per-frame projection

```
ticksFor(viewport, candles):
    if plan stale: rebuild
    out = []
    for p in plan where absX >= scrollOffset:        # binary search the start
        x = p.absX - scrollOffset
        if x > viewportWidth: break
        if x < 0: continue
        out.append(TimeTick(p.index, x, p.label, p.weight))

    if out empty:                                    # fallback B
        mid = clamp(indexAt(viewportWidth/2), 0, n-1)
        out = [ TimeTick(mid, center(mid), label(candles[mid]), weight) ]
    return out
```

Fallbacks A and B together guarantee the axis is never blank. Do not remove
them; §10 tests for it across 4410 configurations.

---

## 5.3 Label text

Depends on the tick's own weight:

```
weight >= YEAR  -> "2026"
weight >= MONTH -> "Aug"
weight >= DAY   -> "10"
otherwise       -> "09:05"
```

This is why the first candle of a day reads `10` while the rest of that day
reads `09:05`. Compute labels at plan time and cache them in the plan.

---

## 6. Price axis

### 6.1 Mapping

```
range = max(maxPrice - minPrice, 1e-9)
y(p)  = height - (p - minPrice)/range * height
p(y)  = minPrice + (height - y)/range * range
```

### 6.2 Auto-scale — the only X/Y coupling (I5)

```
lo = min(candles[i].low)   for i in firstVisible..lastVisible
hi = max(candles[i].high)  for i in firstVisible..lastVisible
pad = (hi - lo) * PRICE_PAD_FRACTION
minPrice = lo - pad;  maxPrice = hi + pad
```

Rebuild every frame. Panning X changes the visible set, which changes the price
range — that is correct and expected behaviour.

"Locked" mode (user drags on the price axis) simply stops rebuilding the scale.

If `hi <= lo` (single flat candle), fall back to `[mid-1, mid+1]`.

### 6.3 Nice numbers

```
target = min(TARGET_PRICE_TICKS, max(2, floor(height / MIN_GAP_Y)))
raw    = range / target
mag    = 10 ^ floor(log10(raw))
n      = raw / mag
step   = mag * (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10)
```

Tick values — **multiply by index, never accumulate**:

```
firstIndex = ceil(minPrice / step)
p_k        = (firstIndex + k) * step,  k = 0,1,2,...  while p_k <= maxPrice
```

> **FAILURE MODE 5.** `p += step` in a loop drifts and produces labels like
> `63000.000000001` after a few dozen steps.

Cap the loop at 64 iterations as a guard.

### 6.4 Decimal places

```
decimalsFor(step):
    d = 0; s = step
    while d < 8 and |s - round(s)| > 1e-9:
        s *= 10; d += 1
    return d
```

> **FAILURE MODE 6.** Deriving decimals from magnitude — `step >= 1 ? 0 :
> -floor(log10(step))` — is wrong for the 2.5 family. `step = 2.5` gives 0
> decimals, so the values 2.5 / 5.0 / 7.5 render as `2` / `5` / `8`: duplicated
> and factually wrong labels.

### 6.5 The 2.5 nesting caveat (design decision, document it)

The ladder `1 · 2 · 2.5 · 5` is almost nested — multiples of 5 are a subset of
multiples of 2.5, multiples of 2 are a subset of multiples of 1 — so zooming
keeps existing labels in place and inserts new ones between them.

One transition breaks: `2.5 -> 2`. Multiples of 2.5 are `0, 2.5, 5, 7.5, 10`;
multiples of 2 are `0, 2, 4, 6, 8, 10`. They share only the endpoints, so the
whole label column jumps.

Either behaviour is acceptable; pick one and note it:
- keep 2.5 → finer zoom granularity, one visible jump (TradingView's choice);
- drop 2.5 → perfectly smooth axis, coarser `5 -> 2` steps (2.5x instead of 2x).

---

## 7. Layout

```
        0                                        plotW      totalW
        +----------------------------------------+-----------+  0
        |                                        |           |
        |              PLOT AREA                 |   PRICE   |
        |          grid + candles                |    AXIS   |
        |                                        |           |
        |   x = center(i)                        | y shared  |
        |   y = scale.y(price)                   | with plot |
        |                                        |           |
        +----------------------------------------+-----------+  plotH
        |              TIME AXIS                 |  CORNER   |
        |          x shared with plot            |   (dead)  |
        +----------------------------------------+-----------+  totalH
```

### 7.1 Region math

```
priceAxisWidth = measured, see 7.6      # default 64
timeAxisHeight = 26

plotW = max(1, totalW - priceAxisWidth)
plotH = max(1, totalH - timeAxisHeight)

plot      = rect(0,     0,     plotW,          plotH)
priceAxis = rect(plotW, 0,     priceAxisWidth, plotH)
timeAxis  = rect(0,     plotH, plotW,          timeAxisHeight)
corner    = rect(plotW, plotH, priceAxisWidth, timeAxisHeight)
```

Set `viewport.viewportWidth = plotW` and `scale.height = plotH`. Feeding the
full widget size instead is a common and subtle error: the visible index range
then covers candles that are actually hidden behind the price axis, which skews
the auto-scaled price range (§6.2).

### 7.2 The two hard rules

**R1 — the time axis is exactly as wide as the plot, with the same x origin.**
Not the full widget width. Both consume the identical `tick.x` value, so any
horizontal offset or width difference between them puts labels under the price
axis or shifts them off their grid lines.

**R2 — the price axis is exactly as tall as the plot, with the same y origin.**
Same reasoning for `tick.y`.

Each axis strip shares exactly one axis with the plot and is translated only
along the axis it does *not* measure. That is the entire trick: a tick
coordinate computed once stays valid in both places, with no transform between
them. This is invariant I6 expressed as layout.

### 7.3 Coordinate systems

If each region is its own painter with a local origin at its top-left:

| Region | local x | local y |
| --- | --- | --- |
| plot | `center(i)` | `scale.y(price)` |
| time axis | **identical** to plot x | `0 .. timeAxisHeight` |
| price axis | `0 .. priceAxisWidth` | **identical** to plot y |
| corner | local | local |

Never add a compensating offset in an axis painter. If a label looks misaligned,
the bug is in the region rectangles, not in the tick math.

### 7.4 The dead corner

The bottom-right block belongs to neither axis. Paint it with the background so
the two axis separator lines terminate cleanly instead of running into empty
space. Exchanges typically put a timezone label, a settings gear, or the price
axis auto/lock toggle here. Leaving it transparent looks like a rendering gap.

### 7.5 Clipping and z-order

Clip candles and grid to the plot rect. Without it, the wick of a partially
visible candle at the right edge draws underneath the price axis labels.

Culling is not clipping. Skipping candles whose centre falls outside the plot
still lets the last drawn candle spill half a body width past the edge. Most
canvas APIs do **not** clip a painter to the size you hand it — you must set the
clip rect explicitly.

The crosshair is the one layer that is **not** clipped to the plot: it draws its
readout labels into the time axis and price axis strips, so it spans the whole
widget.

Bottom to top:

```
1. background
2. grid                (vertical from time ticks, horizontal from price ticks)
3. candles             (clipped to plot)
4. axis separator lines
5. axis labels
6. crosshair + its two readout labels   (spans full widget, not clipped)
7. optional overlays: last-price line, position markers
```

Suggested repaint/compositing boundaries — four separate ones:

| Boundary | Contents | Repaints when |
| --- | --- | --- |
| A | grid + candles | pan, zoom, data |
| B | time axis | pan, zoom |
| C | price axis | price range change |
| D | crosshair | every pointer move |

D must be separate. Without it, moving the pointer one pixel repaints every
candle underneath.

### 7.6 Sizing the price axis

A hardcoded width fails at both extremes: `109,432.50` needs about 64 px,
`0.00001234` needs about 70, and `12.34` wastes half the strip. Measure the
widest label in the current tick set:

```
priceAxisWidth = clamp(maxLabelWidth + 14, 48, 96)
rounded up to a multiple of 8
```

> **FAILURE MODE 7.** Sizing the axis from the labels creates a feedback loop:
> width → `plotW` → visible index range → price range → labels → width. Without
> damping it oscillates and the chart visibly breathes while panning. Quantising
> to 8 px steps plus hysteresis (only shrink when the requirement drops a full
> step below current) breaks the loop.

The time axis height can stay fixed — label height does not vary.

### 7.7 Gesture regions

| Region | Gesture | Action |
| --- | --- | --- |
| plot | drag horizontal | pan X |
| plot | pinch | zoom X anchored on the focal point (§4) |
| price axis | drag vertical | scale Y **and** switch to locked mode |
| price axis | double tap | back to auto-scale |
| time axis | drag horizontal | zoom X anchored on the right edge |
| corner | tap | reset both axes |

Dragging on an axis is how every exchange exposes locked mode — users discover
it by accident, so it is worth implementing.

### 7.8 Degenerate sizes

If `plotW <= 0` or `plotH <= 0`, skip drawing entirely rather than clamping to 1
and painting garbage. This happens during the first layout pass and on collapse
animations.

---

## 8. Rendering

```
snap(v, dpr) = round(v * dpr) / dpr
```

Apply `snap` to every 1px line coordinate. A hairline at a fractional coordinate
gets anti-aliased into a blurry 2px smear; a candlestick chart is mostly thin
vertical lines, so unsnapped grids look dirty and shimmer while panning.

Rules:

- Vertical grid line at `snap(tick.x)`. Label left edge at `tick.x - textWidth/2`,
  then clamped to `[2, width - 2 - textWidth]`. **Clamp the text, never the grid
  line** — the two must not diverge (I6).
- Candle body: `width = max(1, barSpacing * BODY_WIDTH_RATIO)`,
  `height = max(1, |y(close) - y(open)|)`. The height floor stops doji candles
  from rendering as nothing.
- Wick: 1px line at `snap(center(i))`, from `y(high)` to `y(low)`.
- Price label vertical position clamped to stay inside the axis strip.

### Performance checklist

| Concern | Requirement |
| --- | --- |
| Text layout | Cache laid-out text by `(string, colour, size, weight)`. It is the single most expensive operation; laying out ~30 labels per frame costs roughly a third of the frame budget. |
| Repaint gating | Compare `barSpacing`, `scrollOffset`, candle count. Never unconditionally repaint. |
| Crosshair | Own compositing layer. It follows the pointer continuously and must not drag the candles into every repaint. |
| Iteration | Visible index range only. |
| Weights | Cached on the candle (§5). |
| Tick plan | Cached; rebuilt on zoom only (§5.2). |
| Realtime | Throttle repaints to one per frame (~16 ms). |

---

## 9. Realtime updates

```
onKline(msg):
    if msg.openTime == last.openTime:
        last.high   = max(last.high, msg.high)
        last.low    = min(last.low,  msg.low)
        last.close  = msg.close
        last.volume = msg.volume
    else if msg.openTime > last.openTime:
        append candle
        newCandle.tickWeight = max(alignmentWeight(new), crossingWeight(prev, new))
        invalidate tick plan
        if wasAtRightEdge: scrollToRightEdge()
```

Capture `isAtRightEdge` **before** appending. Auto-scrolling a user who has
panned into history is hostile; every exchange gates on this.

---

## 10. Acceptance tests

Implement these as automated tests. They are the definition of done.

Generate synthetic OHLCV: 1500 candles, deterministic seed, for each interval in
`{1m, 5m, 15m, 1h, 4h, 1D, 1W}`.

**T1 — never blank.** For every combination of interval × `barSpacing` in
`{2,3,4,5,6,8,10,12,16,20,25,30,40,50,60}` × viewport width in
`{280,320,380,600,900,1400}` × pan fraction in `{0,0.19,0.37,0.53,0.71,0.88,1}`:
tick list is non-empty. **4410 configurations, 0 failures required.**

**T2 — min gap.** In the same sweep, no two adjacent ticks are closer than
`MIN_GAP_X`. Required: 0 violations.

**T3 — no adjacent duplicate labels.** No two neighbouring ticks carry identical
text. Required: 0. (Identical text far apart — `12:00` on two different days —
is legitimate; only adjacency is a defect.)

**T4 — pan stability.** For each interval and `barSpacing` in `{3,8,20,45}`:
record ticks at some offset, then step the offset by 1 px, 80 times. Any tick
that was in the middle 50 % of the screen and is still geometrically in that
region must still be selected. **Required: 0 jitters over 2212 pan steps.**

**T5 — append stability.** Append one candle at `last.openTime + interval`,
give it `max(alignmentWeight(new), crossingWeight(prev, new))`, and assert no
existing candle's `tickWeight` changed.

> Test-authoring note: do not "append" by regenerating a longer synthetic
> series. If the generator derives its start time from the candle count, the
> whole series shifts and the comparison is meaningless. Append to the same
> list.

**T6 — price ticks.** For ranges `(63000,65000)`, `(0.00021,0.00034)`,
`(1.5,1.52)`, `(43217.83,51999.01)`, `(100,100.0001)`, `(0.5,900000)` × heights
`{200,400,800}`: every tick lies within `[minPrice, maxPrice]`, `y` within
`[0, height]`, no duplicate label strings, no gap below `MIN_GAP_Y`.
**18 cases, 0 failures required.**

**T7 — decimals.** `decimalsFor(2.5) == 1`, `decimalsFor(0.25) == 2`,
`decimalsFor(500) == 0`, `decimalsFor(0.000025) == 6`.

**T8 — plan cost.** Building the tick plan for 100 000 candles completes in a
time consistent with the bucketed algorithm, and does not run on pan-only
frames.

### Reference results

This spec was validated by writing a fresh implementation from it alone — no
reference code consulted — and running the suite above:

```
T1 never blank        : 4410 configs, 0 blank          PASS
T2 min gap            : 0 violations                   PASS
T3 adjacent dup labels: 0                              PASS
   avg fill ratio     : 0.67
T4 pan stability      : 0 jitters / 2240 steps         PASS
T5 append stability   : PASS
T6 price ticks        : 18 cases, 0 failures           PASS
T7 decimals           : PASS
T8 plan cost (100k)   : build 122 ms, pan 0.005 ms     PASS
```

An implementation that follows this document should reproduce these numbers. A
fill ratio between roughly 0.6 and 0.8 is healthy — 1.0 would mean labels packed
edge to edge with no breathing room.

---

## Appendix A — build order

Each step is testable before the next one exists.

1. **Viewport + Candle.** Foundations, no dependencies.
2. **Weights, threshold, planner, price ticks.** Pure logic — write the unit
   tests from §10 here, before any pixel is drawn. Most of the specification's
   value lives in this step.
3. **Grid + candle renderer.** First visible output.
4. **Time axis + price axis.** Check by eye that lines and labels coincide.
5. **Pan and zoom gestures.** This is the real test. Label jitter, rung
   flipping and edge-effect bugs are invisible until something drags
   continuously — a stepped slider will not reveal them. Drag slowly across a
   zoom-level boundary and watch whether any mid-screen label moves.
6. **Crosshair + compositing boundaries.**
7. **Realtime feed.**

Do not reorder 2 and 3. Drawing first tempts you into tuning constants against
one screenshot instead of implementing §5 properly.

## Appendix B — suggested module layout

```
models/candle          Candle + weight ladder constants
chart/viewport         X transform, zoom/pan/clamp math
chart/time_ticks       weights, threshold, planner, label formatting
chart/price_ticks      PriceScale + nice numbers
chart/grid_renderer    draws from the shared tick lists
chart/candle_renderer  bodies + wicks
chart/time_axis        time labels
chart/price_axis       price labels
chart/crosshair        separate layer
chart/text_cache       laid-out text cache + snap()
chart/chart_view       owns viewport + planner, computes ticks once per frame
```

The planner is stateful (it caches the plan). It must be owned by the view/
component instance, not constructed inside the render function.

## Appendix C — platform notes

**Flutter / Dart.** `CustomPainter` for each layer; `RepaintBoundary` around the
crosshair. Handle pan and zoom in one `onScaleUpdate` — `scale == 1.0` means a
plain pan and `focalPointDelta.dx` gives the delta. Do not use a horizontal
`ListView`: no zoom support, and one widget per candle is far too heavy. Note
that `num.clamp` returns `num`; add an explicit conversion when assigning to
`double`/`int`.

**Web / Canvas 2D.** Set `canvas.width = cssWidth * devicePixelRatio` and scale
the context; the `snap()` helper assumes this. Avoid SVG/DOM nodes per candle.
Use `requestAnimationFrame` to coalesce websocket updates.

**iOS / Swift.** `CAShapeLayer` per layer or a single `draw(_:)`. `UIScreen.scale`
is the DPR. Cache `NSAttributedString` sizing.

**Android / Compose.** `Canvas` with `drawIntoCanvas`; cache `TextLayoutResult`
via `TextMeasurer`. `LocalDensity.current.density` is the DPR.

## Appendix D — quick reference

```
center(i)       = i*barSpacing + barSpacing/2 - scrollOffset
absX(i)         = i*barSpacing + barSpacing/2
required period = MIN_GAP_X * interval / (barSpacing * SURPLUS)
bucket(x)       = floor(x / MIN_GAP_X)
nice step       = 10^floor(log10(raw)) * {1, 2, 2.5, 5, 10}
price tick k    = (ceil(minPrice/step) + k) * step
snap(v)         = round(v*dpr) / dpr
```

---

## Appendix E — failure mode index

Every rule in this document that looks like over-engineering traces to one of
these. Each was found by a test, not by reading code.

| # | Section | Symptom | Cause |
| --- | --- | --- | --- |
| FM1 | §4 | Chart slides out from under the pointer while pinching | `logical` computed after mutating `barSpacing` |
| FM2 | §5 | Time axis completely blank at most zoom levels (1m blank at 4 of 7) | weight ladder too coarse (5 rungs) |
| FM3 | §5.1 | Labels flicker while dragging — 168 jitters / 2212 steps | threshold derived from a count of visible candles, which wobbles ±1 |
| FM4 | §5.2 | Labels still jitter — 217 jitters / 2212 steps | selection run over the visible range; edge entries displace on-screen ticks, chaining inward |
| FM5 | §6.3 | Price labels read `63000.000000001` | `p += step` accumulation drift |
| FM6 | §6.4 | Price labels `2.5 / 5.0 / 7.5` render as `2 / 5 / 8` | decimals derived from magnitude, wrong for the 2.5 family |
| FM7 | §7.6 | Chart visibly breathes while panning | price axis width measured from labels without quantisation — feedback loop |

Two more that produce no crash and no warning, so they survive review:

- A left-to-right greedy pass over 4h candles emits `11:00, 11:00, 11:00,
  11:00, 11:00`. Sort candidates by weight first (§5.2).
- Culling candles by centre is not clipping; the last candle still spills over
  the price axis. Set an explicit clip rect (§7.5).
