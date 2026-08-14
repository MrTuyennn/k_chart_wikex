# k_chart_jk

A Flutter candlestick chart package with support for multiple technical indicators, smooth gesture interactions, and customizable themes.

## Features

- Candlestick and line chart rendering
- **Free pan:** drag 1 ngón tay scroll nến (X) luôn; dịch vùng giá (Y) thêm khi đã zoom Y trước đó (`scaleY != 1.0`)
- **Zoom X:** pinch 2 ngón tay, giới hạn bởi `minScale` / `maxScale`
- **Zoom Y:** drag dọc trong strip trục giá bên phải, ngang hàng main chart (width tự đo theo label giá, co khi chart hẹp; strip ngang hàng volume/secondary KHÔNG kích hoạt — chỉ scale main chart)
- **Double tap** cùng vùng: reset zoom Y và pan Y về mặc định
- **Tap-to-toggle crosshair:** tap hiện crosshair, tap lại ẩn; kéo khi crosshair đang hiện sẽ di chuyển crosshair thay vì scroll
- **Price labels đồng bộ scaleY + offsetY:** labels trục Y luôn hiển thị đúng giá theo vị trí visual của nến
- Fling (quán tính) khi scroll, không fling khi đang kéo crosshair
- **Main indicators (8):** MA, EMA, BOLL, SAR, ZigZag, SuperTrend, AVL, Ichimoku
- **Secondary indicators (13):** MACD, KDJ, RSI, WR, CCI, OBV, TRIX, MTM, StochRSI, BRAR, BIAS, PSY, ATR
- Volume bar chart with MA5 / MA10 overlay
- Long-press info dialog with custom `detailBuilder`
- Programmatic control via `KChartController` (zoom in/out, reset)
- Save & restore zoom state across timeframe changes via `KChartScaleState`
- Real-time price ticker via `livePrice` (no full repaint needed)
- Dark / light theme support via `KChartColors`
- **Per-area & per-indicator styling:** `CandleStyle`/`VolumeStyle` (color + text riêng cho main chart/volume panel) và 16 style field riêng từng indicator (`avlStyle`, `maStyle`, `rsiStyle`, `macdStyle`...) — set màu toàn bộ chart từ 1 `KChartColors` duy nhất, không cần tự tạo từng instance indicator
- Background watermark support via `backgroundLogo`
- Depth chart widget for order book visualization

---

## Installation

In your `pubspec.yaml`:

```yaml
dependencies:
  k_chart_jk:
    git:
      url: https://github.com/MrTuyennn/k_chart_jk.git
```

Then run:

```bash
flutter pub get
```

---

## Quick start

### 1. Import

```dart
import 'package:k_chart_jk/k_chart_plus.dart';
```

### 2. Prepare data

```dart
List<KLineEntity> data = [
  KLineEntity.fromCustom(
    time: DateTime.now().millisecondsSinceEpoch,
    open: 65000,
    high: 65800,
    low: 64500,
    close: 65400,
    vol: 120.5,
    amount: 65400 * 120.5,
  ),
  // ...more candles
];

// Must call before rendering; call again whenever data changes
DataUtil.calculateAll(data, [MAIndicator()], [MACDIndicator()]);
```

Or from JSON:

```dart
final data = jsonList.map((e) => KLineEntity.fromJson(e)).toList();
DataUtil.calculateAll(data, [MAIndicator()], [MACDIndicator()]);
```

### 3. Render chart

```dart
KChartWidget(
  data,
  const KChartStyle(),
  const KChartColors(),
  isTrendLine: false,
  isLine: false,
  volHidden: false,
  mainIndicators: [MAIndicator()],
  secondaryIndicators: [MACDIndicator()],
  showNowPrice: true,
  showInfoDialog: true,
  mBaseHeight: 300,
  // timeFormat: omitted → axis format adapts to zoom, crosshair follows candle interval (recommended default, see "Time format" below)
  onLoadMore: (isLeft) {
    // load more data when user scrolls to the edge
  },
  detailBuilder: (entity) {
    return YourInfoCard(entity: entity);
  },
)
```

---

## Indicators

### Main indicators (overlay on candles)

| Class                   | Description                        | Default params |
| ----------------------- | ---------------------------------- | -------------- |
| `MAIndicator()`         | Moving Average                     | 5, 10, 30, 60  |
| `EMAIndicator()`        | Exponential Moving Average         | 5, 10, 30, 60  |
| `BOLLIndicator()`       | Bollinger Bands                    | 20, 2          |
| `SARIndicator()`        | Parabolic SAR                      | 2, 2, 20       |
| `ZigZagIndicator()`     | ZigZag                             | 12, 2, 5       |
| `SuperTrendIndicator()` | SuperTrend                         | 10, 30         |
| `AVLIndicator()`        | Average Value Line (Binance-style) | — (no period)  |
| `IchimokuIndicator()`   | Ichimoku Kinko Hyo (5 lines + cloud) | 9, 26, 52    |

### Secondary indicators (panel below chart)

| Class                 | Description                | Default params |
| --------------------- | -------------------------- | -------------- |
| `MACDIndicator()`     | MACD                       | 12, 26, 9      |
| `KDJIndicator()`      | KDJ                        | —              |
| `RSIIndicator()`      | Relative Strength Index    | 6, 12, 24      |
| `WRIndicator()`       | Williams %R                | 26, 6          |
| `CCIIndicator()`      | Commodity Channel Index    | 20             |
| `OBVIndicator()`      | On-Balance Volume          | 5              |
| `TRIXIndicator()`     | Triple Exponential Average | 12, 20         |
| `MTMIndicator()`      | Momentum                   | 12, 6          |
| `StochRSIIndicator()` | Stochastic RSI             | 14, 14, 3, 3   |
| `BRARIndicator()`     | Popularity/Willingness Index | 26           |
| `BIASIndicator()`     | Bias Ratio                 | 6, 12, 24      |
| `PSYIndicator()`      | Psychological Line         | 12, 6          |
| `ATRIndicator()`      | Average True Range         | 14, 6          |

Volume hiển thị trong panel riêng giữa main chart và date axis. Toggle bằng `volHidden`.

Combine multiple indicators by passing a list:

```dart
mainIndicators: [MAIndicator(), BOLLIndicator()],
secondaryIndicators: [MACDIndicator()],
```

Always call `DataUtil.calculateAll` after changing indicators or data:

```dart
DataUtil.calculateAll(data, mainIndicators, secondaryIndicators);
```

---

## KChartWidget parameters

### Required / core

| Parameter       | Type                  | Default | Description                    |
| --------------- | --------------------- | ------- | ------------------------------ |
| `datas`         | `List<KLineEntity>?`  | —       | Candle data list               |
| `chartStyle`    | `KChartStyle`         | —       | Style config (spacing, widths) |
| `chartColors`   | `KChartColors`        | —       | Color config                   |
| `isTrendLine`   | `bool`                | —       | Enable trend line drawing      |
| `detailBuilder` | `WidgetDetailBuilder` | —       | Custom info card widget        |

### Display

| Parameter               | Type                       | Default                   | Description                         |
| ----------------------- | -------------------------- | ------------------------- | ----------------------------------- |
| `mainIndicators`        | `List<MainIndicator>`      | `[]`                      | Main overlay indicators             |
| `secondaryIndicators`   | `List<SecondaryIndicator>` | `[]`                      | Secondary panel indicators          |
| `isLine`                | `bool`                     | `false`                   | Line chart mode                     |
| `volHidden`             | `bool`                     | `false`                   | Hide volume panel                   |
| `showNowPrice`          | `bool`                     | `true`                    | Show current price line             |
| `showInfoDialog`        | `bool`                     | `true`                    | Show info on long-press/tap         |
| `isTapShowInfoDialog`   | `bool`                     | `false`                   | Single tap shows crosshair + dialog |
| `materialInfoDialog`    | `bool`                     | `true`                    | Material vs Cupertino dialog style  |
| `timeFormat`            | `List<String>?`            | `null`                    | Force 1 fixed format for every tick. `null` (default) = axis picks minute/hour/day pattern from the current zoom level, crosshair picks it once from the candle interval — see [Time format](#time-format) |
| `fixedLength`           | `int`                      | `2`                       | Decimal places for price labels     |
| `verticalTextAlignment` | `VerticalTextAlignment`    | `right`                   | Price label side (`left`/`right`)   |
| `hideGrid`              | `bool`                     | `false`                   | Hide grid lines                     |

### Layout & sizing

| Parameter          | Type      | Default              | Description                                                                           |
| ------------------ | --------- | -------------------- | ------------------------------------------------------------------------------------- |
| `mBaseHeight`      | `double`  | `360`                | Main chart height (px)                                                                |
| `mSecondaryHeight` | `double?` | 20% of `mBaseHeight` | Secondary panel height (px)                                                           |
| `xFrontPadding`    | `double`  | `100`                | Right padding after last candle (px at ≥375px chart; scales down on narrower screens) |

### Zoom / scroll

| Parameter    | Type                | Default             | Description                     |
| ------------ | ------------------- | ------------------- | ------------------------------- |
| `minScale`   | `double`            | `0.2`                | Minimum zoom scale X            |
| `maxScale`   | `double`            | `2.2`               | Maximum zoom scale X            |
| `flingTime`  | `int`               | `600`               | Fling animation duration (ms)   |
| `flingRatio` | `double`            | `0.5`               | Fling velocity multiplier       |
| `flingCurve` | `Curve`             | `Curves.decelerate` | Fling animation curve           |
| `chartScale` | `KChartScaleState?` | `null`              | Saved scale to restore on mount |

### Data loading & callbacks

| Parameter              | Type                    | Description                                            |
| ---------------------- | ----------------------- | ------------------------------------------------------ |
| `onLoadMore`           | `void Function(bool)?`  | Called when scrolled to edge; `true` = load left       |
| `isLoadingMore`        | `bool`                  | Lock flag to prevent duplicate load requests           |
| `isOnDrag`             | `void Function(bool)?`  | Called on drag start/stop                              |
| `controller`           | `KChartController?`     | Programmatic zoom/reset control                        |
| `onChartScaleChanged`  | `OnChartScaleChanged?`  | Emitted after pinch / scaleY / zoom / reset ends       |
| `onVerticalOverscroll` | `ValueChanged<double>?` | Fired when pan Y hits clamp (for outer scroll handoff) |

### Real-time & decorative

| Parameter               | Type      | Default | Description                                  |
| ----------------------- | --------- | ------- | -------------------------------------------- |
| `livePrice`             | `double?` | `null`  | Real-time price for now-price line           |
| `backgroundLogo`        | `Widget?` | `null`  | Watermark widget centered in main chart area |
| `backgroundLogoOpacity` | `double`  | `1.0`   | Watermark opacity (0.0–1.0)                  |

---

## Real-time price ticker

Use `livePrice` to update the now-price line on every WebSocket tick **without rebuilding the full candle list**:

```dart
double? _livePrice;
List<KLineEntity> _datas = [];

// WebSocket tick — only update live price
void _onTick(double price) {
  setState(() => _livePrice = price);
}

// New candle closed — append to data list
void _onCandleClose(KLineEntity newCandle) {
  final next = [..._datas, newCandle];
  DataUtil.calculateAll(next, mains, secondaries);
  setState(() {
    _datas = next;
    _livePrice = null; // fallback to last candle's close
  });
}

// Build:
KChartWidget(
  _datas,
  chartStyle, chartColors,
  livePrice: _livePrice,
  ...
)
```

> `livePrice` changing triggers a targeted repaint of `drawNowPrice` only.  
> `datas` reference changing triggers a full repaint (min/max recalculation, entire chart).

**Anti-pattern — do NOT mutate datas in place:**

```dart
// ❌ same list reference → shouldRepaint returns false → no repaint
_datas.last.close = newPrice;
setState(() {});
```

**Throttle for high-frequency ticks (>10/s):**

```dart
_livePrice = newPrice;
if (_lastRender == null || now - _lastRender! > 16) {
  setState(() {});
  _lastRender = now;
}
```

---

## Save & restore zoom state

Use `KChartScaleState` to preserve zoom / scroll position when switching timeframes:

```dart
KChartScaleState? _savedScale;

KChartWidget(
  _data, chartStyle, chartColors,
  chartScale: _savedScale,
  onChartScaleChanged: (s) => setState(() => _savedScale = s),
  ...
)
// Switching timeframe: pass _savedScale into the new widget instance → auto-restored.
```

`onChartScaleChanged` fires after every pinch, scaleY drag, controller zoom, or double-tap reset.

---

## Load more (historical data)

```dart
KChartWidget(
  data, style, colors,
  detailBuilder: ...,
  isTrendLine: false,
  isLoadingMore: _isFetching,
  onLoadMore: (isLeft) async {
    if (!isLeft || _isFetching) return;
    setState(() => _isFetching = true);
    final older = await fetchOlderCandles(from: data.first.time!);
    final merged = [...older, ...data];
    DataUtil.calculateAll(merged, mains, secondaries);
    setState(() {
      data = merged;
      _isFetching = false;
    });
  },
)
```

> `onLoadMore` is also triggered when scaleX is small enough that all data fits the screen (`maxScrollX == 0`).

---

## Gesture interaction

| Gesture                     | Hành động                                                 |
| --------------------------- | --------------------------------------------------------- |
| 1 ngón kéo tự do trong main chart | Scroll X (luôn); pan Y **chỉ khi đã zoom Y trước đó** (`scaleY != 1.0`) — cả 2 trục cập nhật CÙNG lúc trên 1 cú kéo chéo, không tách riêng thành 2 gesture |
| Pinch 2 ngón                | Zoom scaleX (thu phóng số nến hiển thị)                   |
| Kéo dọc strip trục giá bên phải, ngang hàng main chart | Zoom scaleY (thu phóng vùng giá) — strip ngang hàng volume/secondary KHÔNG kích hoạt |
| Double tap cùng vùng        | Reset scaleY và offsetY về mặc định                       |
| Tap vào nến                 | Hiện crosshair + info dialog                              |
| Tap lại                     | Ẩn crosshair                                              |
| Kéo khi crosshair đang hiện | Di chuyển crosshair theo ngón tay                         |
| Long press + kéo            | Di chuyển crosshair                                       |

---

## Vertical overscroll handoff

When the chart is nested inside a `SingleChildScrollView`, use `onVerticalOverscroll` to forward excess pan-Y to the outer scroll:

```dart
void _onChartVerticalOverscroll(double delta) {
  if (!_outerController.hasClients) return;
  final pos = _outerController.position;
  final target = (pos.pixels - delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
  if (target != pos.pixels) _outerController.jumpTo(target);
}

SingleChildScrollView(
  controller: _outerController,
  physics: (_scaleYActive && _pointerOnChart)
      ? const NeverScrollableScrollPhysics()
      : const ClampingScrollPhysics(),
  child: Column(children: [
    KChartWidget(..., onVerticalOverscroll: _onChartVerticalOverscroll),
    const OrderBookSection(),
  ]),
)
```

---

## Theming

### Light theme (default)

```dart
const KChartColors()
```

### Dark theme

```dart
const KChartColors(
  bgColor: Color(0xFF1C1C1E),
  defaultTextColor: Color(0xFF8E8E93),
  gridColor: Color(0xFF2C2C2E),
  selectFillColor: Color(0xFF2C2C2E),
  selectBorderColor: Color(0xFF636366),
  crossColor: Color(0xFFEBEBF5),
  crossTextColor: Color(0xFFEBEBF5),
  maxColor: Color(0xFFEBEBF5),
  minColor: Color(0xFFEBEBF5),
)
```

### Per-area color/text style: `CandleStyle` & `VolumeStyle`

Main chart (candles/line) và panel volume mỗi khu vực có 1 style riêng — gồm cả màu lẫn `TextStyle` (mặc định fontSize 10), tách khỏi các field chung của `KChartColors`:

```dart
const KChartColors(
  candleStyle: CandleStyle(
    upColor: Color(0xFF14AD8F),
    dnColor: Color(0xFFD5405D),
    kLineColor: Color(0xFF217AFF),   // line-chart mode (isLine: true)
    kLineFillColors: [Color(0x80217aff), Color(0x00217AFF)],
    textStyle: TextStyle(fontSize: 11), // trục giá/thời gian, crosshair, max/min, now-price
  ),
  volumeStyle: VolumeStyle(
    upColor: Color(0xFF14AD8F),
    dnColor: Color(0xFFD5405D),
    ma5Color: Color(0xFFFFC634),
    ma10Color: Color(0xff35cdac),
    textStyle: TextStyle(fontSize: 10), // riêng panel volume
  ),
)
```

> `textStyle.color` nếu tự set (vd `TextStyle(fontSize: 11, color: Colors.amber)`) sẽ **luôn thắng** — không bị `defaultTextColor`/`crossTextColor`/`maxColor`/... ghi đè. Không set `color` (mặc định `null`) thì mỗi chỗ vẽ tự chọn màu ngữ nghĩa của nó như trước giờ (trục dùng `defaultTextColor`, crosshair dùng `crossTextColor`, v.v.). Cùng quy tắc áp dụng cho `textStyle` của mọi indicator style (`avlStyle.textStyle`, `rsiStyle.textStyle`...) và `livePriceStyle.textStyle`.

### Per-indicator color: 16 style fields

Thay vì tự tạo từng indicator instance với `indicatorStyle` riêng, set màu tập trung ngay trong `KChartColors` — field nào đặt tên trùng loại indicator (`avlStyle`, `maStyle`, `emaStyle`, `bollStyle`, `sarStyle`, `zigzagStyle`, `superTrendStyle`, `macdStyle`, `kdjStyle`, `rsiStyle`, `wrStyle`, `cciStyle`, `obvStyle`, `trixStyle`, `mtmStyle`, `stochRsiStyle`):

```dart
KChartWidget(
  data,
  const KChartStyle(),
  const KChartColors(
    avlStyle: AVLStyle(avlColor: Colors.purple),
    rsiStyle: RSIStyle(rsiColor: Colors.pink),
    macdStyle: MACDStyle(macdColor: Colors.green),
  ),
  mainIndicators: [AVLIndicator()],       // không cần tự truyền indicatorStyle
  secondaryIndicators: [RSIIndicator(), MACDIndicator()],
  ...
)
```

> Instance nào tự truyền `indicatorStyle` riêng (vd `AVLIndicator(indicatorStyle: AVLStyle(avlColor: Colors.red))`) sẽ **không** bị `KChartColors` ghi đè — style ở instance luôn thắng. Chi tiết cơ chế + bảng đầy đủ 16 field: xem [`chart_jk_arch.md` §8.2](chart_jk_arch.md#82-kchartcolors).

Mỗi `XxxStyle` (`AVLStyle`, `RSIStyle`, `MACDStyle`...) còn có `textStyle` riêng (mặc định fontSize 10) — chỉnh font label từng indicator độc lập nhau, không dùng chung `CandleStyle.textStyle`:

```dart
avlStyle: AVLStyle(avlColor: Colors.purple, textStyle: TextStyle(fontSize: 12)),
```

### Now-price badge: `LivePriceStyle`

Đường + badge giá hiện tại (`ChartPainter.drawNowPrice`, dùng `livePrice ?? datas.last.close` so với `open` nến cuối để chọn màu) cấu hình qua `livePriceStyle`. **`upColor`/`dnColor` chỉ tô nền badge + đường kẻ — màu chữ luôn lấy từ `textStyle.color`** (mặc định trắng), không dùng chung với `upColor`/`dnColor` (nền đặc + chữ cùng màu sẽ vô hình):

```dart
const KChartColors(
  livePriceStyle: LivePriceStyle(
    upColor: Colors.blueAccent,
    dnColor: Colors.red,
    textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
  ),
)
```

Badge vẽ qua `LivePriceBadgePainter` (convert từ `assets/Number.svg`) — nền bo góc + mũi tên nhỏ trỏ vào chart, tự co giãn theo độ dài số giá.

### Volume bar opacity

`KChartStyle.volBarOpacity` (0.0–1.0) **nhân dồn** với alpha sẵn có trong `volumeStyle.upColor`/`dnColor` — không ghi đè. Set alpha thẳng trong `Color` (vd `Color(0x8076FF03)`) hoặc qua `volBarOpacity` đều dùng được, kết hợp được cả hai:

```dart
KChartWidget(
  data,
  const KChartStyle(null, 0.6), // volBarOpacity = 0.6, nhân thêm vào alpha của Color
  const KChartColors(volumeStyle: VolumeStyle(upColor: Color(0x8076FF03))),
  ...
)
```

---

## KChartController

Use `KChartController` to control the chart programmatically:

```dart
final controller = KChartController();

// pass to widget
KChartWidget(..., controller: controller)

controller.zoomIn();   // scaleX += 0.1
controller.zoomOut();  // scaleX -= 0.1
controller.reset();    // scaleX = 1.0, scrollX = 0.0 (does NOT reset scaleY)

// dispose when done
controller.dispose();
```

---

## Custom info dialog

The `detailBuilder` callback is called on long-press or tap with the selected candle:

```dart
detailBuilder: (KLineEntity entity) {
  return Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Open:  ${entity.open.toStringAsFixed(2)}'),
        Text('High:  ${entity.high.toStringAsFixed(2)}'),
        Text('Low:   ${entity.low.toStringAsFixed(2)}'),
        Text('Close: ${entity.close.toStringAsFixed(2)}'),
        Text('Vol:   ${entity.vol.toStringAsFixed(2)}'),
      ],
    ),
  );
},
```

---

## Time format

`timeFormat` (equivalently `KChartStyle.dateTimeFormat`) uses the same 3 patterns in both places time gets rendered — **X-axis ticks** and the **crosshair label** — but with `timeFormat: null` (default) each picks WHICH of the 3 patterns differently:

- `HH:mm`
- `MM-dd HH:mm`
- `yy-MM-dd`

**Crosshair — picked once from the candle interval**, fixed for the chart's lifetime: gap between your first two candles < 1 hour (1m/5m/15m/30m) → `HH:mm`; < 1 day (1H/4H) → `MM-dd HH:mm`; ≥ 1 day (1D) → `yy-MM-dd`. Reasonable since the crosshair only ever shows 1 value at a time — no risk of two labels colliding.

**X-axis ticks — re-evaluated every frame from the current zoom level**, so it changes as you pinch in/out on the same dataset instead of staying fixed to the candle interval:

- Zoomed in enough that ticks are still sub-hourly apart → `HH:mm` (compact, no date needed).
- Ticks are sub-daily apart, or the candle interval itself is ≥ 1 hour (1H/4H, so any 2 ticks could land on the same time-of-day on different days) → `MM-dd HH:mm`.
- Zoomed out far enough that only day/month/year-boundary candles survive, or the candle interval itself is ≥ 1 day (1D, which is always local midnight) → `yy-MM-dd` — the hour/minute is dropped because at that point it's either meaningless (1D candles have no real time-of-day) or actively misleading (every surviving tick would print `"00:00"` with nothing to tell the days apart).

In short: zoom out and the axis collapses to dates; zoom in and it opens back up to `HH:mm` — automatically, per timeframe, without you tracking which timeframe is selected.

**Force 1 fixed format for both, regardless of zoom** — use a predefined format or build your own (`List<String>`, tokens from `lib/utils/date_format_util.dart`: `yyyy`, `yy`, `mm`, `dd`, `hour24Padded`, `nn`...) to override both defaults above:

```dart
// 2024-01-15
timeFormat: TimeFormat.yearMonthDay

// 2024-01-15 08:30
timeFormat: TimeFormat.yearMonthDayWithHour

// custom
timeFormat: const [yyyy, '/', mm, '/', dd]
```

### Migrating off a hand-rolled per-timeframe format

If your app previously mapped its own timeframe (1m/5m/15m/.../1D) to a `List<String>` and passed it in as `timeFormat` on every rebuild, that logic is now redundant — and worse than the built-in default, since a format picked once from the timeframe can't react to zoom the way the axis default does (see above).

```dart
// Before
List<String> get axisTimeFormat {
  if (interval < const Duration(hours: 1)) return const [hour24Padded, ':', nn];
  if (interval < const Duration(days: 1)) {
    return const [mm, '-', dd, ' ', hour24Padded, ':', nn];
  }
  return const [yy, '-', mm, '-', dd];
}
// ...
KChartWidget(
  // ...
  timeFormat: state.timeframe.axisTimeFormat,
)

// After — just delete the getter and the parameter
KChartWidget(
  // ...
  // timeFormat: omitted, axis + crosshair pick their own defaults
)
```

Keep `timeFormat` around only if you actually want the SAME fixed pattern on the axis at every zoom level (a different locale, always-show-year, matching some other UI element, etc.) — otherwise the zoom-aware default reads better once you've compared the two.

Either way, tick *selection* (which candles get a label, spacing, pan/zoom stability) always follows the same weight-ladder algorithm — `timeFormat`/`dateTimeFormat` only changes the TEXT on each tick.

---

## Background logo (watermark)

Pass any widget as `backgroundLogo` to display it centered in the main chart area — rendered above the background color but below candles and indicators:

```dart
KChartWidget(
  data,
  chartStyle,
  chartColors,
  backgroundLogo: Builder(
    builder: (context) {
      final size = MediaQuery.sizeOf(context).width / 6;
      return SvgPicture.asset('assets/logo.svg', width: size, height: size);
    },
  ),
  backgroundLogoOpacity: 0.15,
  ...
)
```

> The logo uses `IgnorePointer` internally and does not interfere with gestures.

---

## Example

See the full working demo in the [`example/`](example/lib/main.dart) folder — bloc-based, kết nối REST + WebSocket thật (kline lịch sử, live tick, order book), toggle theme/indicator, tất cả 8 main + 13 secondary indicator có sẵn để bật thử (mặc định tắt hết, tự bật qua chip).

Demo cần file env chứa endpoint thật (git-ignored — không commit trong repo). Tạo từ template rồi điền giá trị:

```bash
cd example
flutter pub get
cp env.example.json env.dev.json   # điền MARKET_API_BASE, MARKET_STOMP_URL... giá trị thật
flutter run --dart-define-from-file=env.dev.json
```

Thiếu file/thiếu giá trị → app hiển thị màn "Chưa cấu hình endpoint API" thay vì crash.

Muốn 1 ví dụ tự chứa, không cần bloc/network, copy-paste chạy ngay (mock data) — xem [**Ví dụ đầy đủ** trong `chart_jk_arch.md`](chart_jk_arch.md#ví-dụ-đầy-đủ).

---

## License

Copyright (c) 2026 JK. All rights reserved. See [LICENSE](LICENSE).
