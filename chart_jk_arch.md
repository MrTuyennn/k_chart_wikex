# k_chart_jk — Tài liệu tổng hợp

> Tổng hợp từ: `HANDBOOK.md`, `chart_jk.md`, `chart_plush.md`, `CHANGELOG.md`, `chart_jk_arch.md`.
>
> **Changelog đã chuyển sang [`CHANGELOG.md`](CHANGELOG.md), tổ chức theo ngày.** File này chỉ còn kiến trúc/công thức/tài liệu API — không còn lịch sử thay đổi.

---

## Mục lục

1. [Tổng quan kiến trúc](#1-tổng-quan-kiến-trúc)
2. [Cài đặt & Quick Start](#2-cài-đặt--quick-start)
3. [Entry point & exports](#3-entry-point--exports)
4. [Entity — data models](#4-entity--data-models)
5. [KChartWidget — API đầy đủ](#5-kchartwidget--api-đầy-đủ)
6. [KChartController](#6-kchartcontroller)
7. [KChartStyle & KChartColors](#7-kchartstyle--kchartcolors)
8. [Indicators — main & secondary](#8-indicators--main--secondary)
9. [DataUtil & helpers](#9-datautil--helpers)
10. [DepthChart — orderbook depth](#10-depthchart--orderbook-depth)
11. [Renderer internals](#11-renderer-internals)
12. [Gesture model](#12-gesture-model)
13. [Recipes — công thức thường dùng](#13-recipes--công-thức-thường-dùng)
    - [13.10 Real-time WebSocket price ticker](#1310-real-time-websocket-price-ticker)
14. [Troubleshooting & pitfalls](#14-troubleshooting--pitfalls)
15. [Phân tích cơ chế Y Grid & Anchor Zoom (MEXC / TradingView)](#15-phân-tích-cơ-chế-y-grid--anchor-zoom-mexc--tradingview)

---

## 1. Tổng quan kiến trúc

Mã nguồn chart được thiết kế theo mô hình:

- `KChartWidget`: widget chứa, xử lý tương tác (gesture, scroll, scale, long-press, pointer tracking cho parent), và tạo `ChartPainter`.
- `ChartPainter`: lớp vẽ chính, kế thừa `BaseChartPainter`.
- `BaseChartPainter`: xử lý layout (chia rect), phạm vi dữ liệu (visible window), và điều phối paint.
- `MainRenderer`: vẽ đồ thị chính (nến hoặc line), chạy từng `MainIndicator` (MA/BOLL/EMA/SAR/ZigZag/SuperTrend/AVL) trong cùng vùng `mMainRect`.
- `VolRenderer`: vẽ panel volume (bars + MA5/MA10) trong `mVolRect`. Toggle bằng `volHidden` ở `KChartWidget`.
- `SecondaryRenderer`: vẽ một panel indicator phụ (MACD/KDJ/RSI/WR/CCI/OBV/TRIX/MTM/StochRSI). Mỗi entry trong `secondaryIndicators` có 1 instance riêng.
- `DepthChartPainter`: vẽ orderbook depth (Buy/Sell pressure) — standalone, không gắn với `KChartWidget`.

> **Ghi chú quan trọng:** toàn bộ chart chính của `KChartWidget` được vẽ trong một `CustomPaint` duy nhất. `KChartWidget` tạo ra `ChartPainter`, và `ChartPainter` quản lý canvas chung, dùng các renderer nội bộ để vẽ từng phần trong cùng một hộp vẽ.

### Sơ đồ đơn giản

```
KChartWidget  (state + gesture)
└─ Stack
   ├─ ColoredBox(bgColor)                     ← chỉ khi có backgroundLogo
   ├─ backgroundLogo (IgnorePointer, Center)  ← watermark giữa main rect
   ├─ CustomPaint(painter: ChartPainter)
   │   └─ ChartPainter.paint()
   │       ├─ initRect()              → mPlotWidth, mMainRect, mVolRect?, mDateRect, mSecondaryRectList[], mPriceAxisRect, mCornerRect
   │       ├─ calculateValue()        → mStartIndex/mStopIndex (theo mPlotWidth) + max/min + mTimeTicks (weight-ladder planner, CHART_AXES.md §5)
   │       ├─ initChartRenderer()     → mMainRenderer + mVolRenderer? + mSecondaryRendererList[] (đều nhận priceAxisRect) + đo lại priceAxisWidth cho frame SAU (§7.6)
   │       ├─ drawBg()                (skip nếu skipBg; phủ cả strip giá + ô góc chết)
   │       ├─ drawGrid()              (theo mTimeTicks dùng chung + _priceTicks mỗi panel) + 2 đường phân cách khung (§7.5)
   │       ├─ drawChart()
   │       │   ├─ canvas: translate(mTranslateX*scaleX) + scale(scaleX, 1)
   │       │   ├─ scaleY scope:
   │       │   │   ├─ clipRect(mMainRect band)
   │       │   │   ├─ translate(0, centerY*(1-scaleY) + offsetY)
   │       │   │   ├─ scale(1, scaleY)
   │       │   │   └─ loop indices → mMainRenderer.drawChart()
   │       │   ├─ loop indices (ngoài scaleY)
   │       │   │   ├─ mVolRenderer?.drawChart()
   │       │   │   └─ for each SecondaryRenderer.drawChart()
   │       │   └─ drawCrossLine / drawTrendLines
   │       ├─ drawVerticalText()       (main + vol + secondaries — vẽ vào mPriceAxisRect, không đè lên nội dung panel nữa)
   │       ├─ drawDate()               (clip canvas theo mPlotWidth, vẽ label ở đúng vị trí thật — không phải full mWidth)
   │       ├─ drawText(getItem(mStopIndex))    (main + vol + secondaries)
   │       ├─ drawMaxAndMin() / drawNowPrice()     (qua _applyScaleY)
   │       ├─ drawBidAsk()               (chạy NGAY SAU drawNowPrice — box Ask/Bid, chỉ khi bidPrice+askPrice cùng non-null, xem §5.8)
   │       └─ drawCrossLineText() (nếu long-press/tap — span cả mWidth, KHÔNG bị giới hạn mPlotWidth, xem CHART_AXES.md §7.5)
   └─ Positioned (right:0) + LayoutBuilder → w = BaseChartPainter.priceAxisWidth
       ─ vùng gesture scaleY + double-tap reset scaleY/offsetY (khớp đúng strip giá đang vẽ, §7.7)
```

### Flow dữ liệu

1. Chuẩn bị `List<KLineEntity>` (mỗi entity = 1 nến OHLCV + time).
2. Gọi `DataUtil.calculateAll(data, mainIndicators, secondaryIndicators)` để tính chỉ báo.
3. Truyền list vào `KChartWidget` cùng style/colors/indicators.
4. `ChartPainter` đọc data đã tính, dùng renderer để vẽ từng nến + indicator.
5. `KChartController` ở ngoài có thể gọi `zoomIn` / `zoomOut` / `reset`.

### Quy tắc quan trọng để port sang source khác

- **Widget quản lý trạng thái + gesture, painter vẽ toàn bộ.**
- **Một `CustomPaint`** cho main chart; secondary indicators KHÔNG phải widget riêng.
- **Tính min/max chỉ trên vùng dữ liệu visible** (`mStartIndex..mStopIndex`, tính theo `mPlotWidth` — KHÔNG phải `mWidth`, xem [11](#11-renderer-internals) "Price axis strip").
- **`scrollX` và `scaleX` thành phép biến đổi canvas**, không vẽ tay từng phần.
- **`scaleY` áp riêng cho main**, secondary nằm ngoài transform để không bị giãn.
- **Tick trục X/Y tính lại mỗi frame theo layer riêng** (`BaseChartPainter._updateTimeTicks()` cho X, `MainRenderer` constructor cho Y) — renderer con không tự chọn tick, chỉ vẽ danh sách đã tính sẵn. Chi tiết đầy đủ ở `CHART_AXES.md` + [9.4](#94-time-tick-planner--price-ticks-trục-xy).
- **Mọi label vẽ ngoài canvas transform** phải đi qua `_applyScaleY(rawY)`.

---

## 2. Cài đặt & Quick Start

### Dependency

```yaml
dependencies:
  k_chart_jk:
    git:
      url: <repo-url>
```

### Quick start tối thiểu

```dart
import 'package:k_chart_jk/k_chart_plus.dart';

final data = [
  KLineEntity.fromCustom(
    time: 1700000000000,
    open: 65000, close: 65500, high: 65800, low: 64900,
    vol: 12.3,
  ),
  // ...
];

DataUtil.calculateAll(
  data,
  [MAIndicator()],
  [MACDIndicator()],
);

KChartWidget(
  data,
  const KChartStyle(),
  const KChartColors(),
  isTrendLine: false,
  detailBuilder: (entity) => Text(entity.close.toString()),
  mainIndicators: [MAIndicator()],
  secondaryIndicators: [MACDIndicator()],
)
```

### Ví dụ đầy đủ

Widget tự chứa (copy-paste chạy được, chỉ cần cắm nguồn data thật vào `_fetchInitialCandles`/`_loadMoreHistory`) — bật **toàn bộ** 6 main + 9 secondary indicator, custom màu qua `CandleStyle`/`VolumeStyle`/style riêng từng indicator (xem [7.2](#72-kchartcolors)), toggle dark mode / line-vs-candlestick, zoom qua `KChartController`, và `DepthChart` đi kèm. Đây gần như nguyên bản cách `example/lib/main.dart` + `example/lib/bloc/chart_bloc.dart` trong repo demo dựng lên (repo demo tách phần data/network ra `ChartBloc` — ở đây gộp thẳng vào `State` cho gọn).

```dart
import 'package:flutter/material.dart';
import 'package:k_chart_jk/k_chart_plus.dart';

class FullChartDemo extends StatefulWidget {
  const FullChartDemo({super.key});

  @override
  State<FullChartDemo> createState() => _FullChartDemoState();
}

class _FullChartDemoState extends State<FullChartDemo> {
  final KChartController _controller = KChartController();
  bool _isDark = false;
  bool _isLine = false;
  bool _volHidden = false;
  late List<KLineEntity> _data;

  // Bật hết indicator sẵn có trong package — 6 main + 9 secondary.
  final List<MainIndicator> _mainIndicators = [
    MAIndicator(),
    BOLLIndicator(),
    EMAIndicator(),
    SuperTrendIndicator(),
    ZigZagIndicator(),
    AVLIndicator(),
  ];
  final List<SecondaryIndicator> _secondaryIndicators = [
    MACDIndicator(),
    KDJIndicator(),
    RSIIndicator(),
    WRIndicator(),
    CCIIndicator(),
    OBVIndicator(),
    TRIXIndicator(),
    MTMIndicator(),
    StochRSIIndicator(),
  ];

  @override
  void initState() {
    super.initState();
    _data = _fetchInitialCandles(); // TODO: REST/WS/mock — nguồn data thật
    // Bắt buộc gọi lại calculateAll mỗi khi _data thay đổi (thêm nến mới,
    // load more, đổi timeframe...) — indicator phụ thuộc toàn bộ historical data.
    DataUtil.calculateAll(_data, _mainIndicators, _secondaryIndicators);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Không cần tự truyền `indicatorStyle` cho từng indicator ở trên — set màu
  // tập trung ở đây, KChartWidget tự áp cho instance nào còn dùng default.
  KChartColors get _colors => KChartColors(
    bgColor: _isDark ? const Color(0xFF1C1C1E) : Colors.white,
    defaultTextColor: _isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF909196),
    gridColor: _isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEDEDED),
    candleStyle: const CandleStyle(
      upColor: Color(0xFF14AD8F),
      dnColor: Color(0xFFD5405D),
      kLineColor: Color(0xFF217AFF),
      textStyle: TextStyle(fontSize: 11),
    ),
    volumeStyle: const VolumeStyle(
      ma5Color: Color(0xFFFFC634),
      ma10Color: Color(0xff35cdac),
      textStyle: TextStyle(fontSize: 10),
    ),
    avlStyle: const AVLStyle(avlColor: Color(0xFFEA80FC)),
    bollStyle: const BOLLStyle(bollColor: Color(0xFF6200EA)),
    rsiStyle: const RSIStyle(rsiColor: Color(0xFFFF4081)),
    macdStyle: const MACDStyle(macdColor: Color(0xFF00E676)),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.zoom_in),
              onPressed: _controller.zoomIn,
            ),
            IconButton(
              icon: const Icon(Icons.zoom_out),
              onPressed: _controller.zoomOut,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _controller.reset,
            ),
            IconButton(
              icon: Icon(_isDark ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => setState(() => _isDark = !_isDark),
            ),
            IconButton(
              icon: Icon(_isLine ? Icons.candlestick_chart : Icons.show_chart),
              onPressed: () => setState(() => _isLine = !_isLine),
            ),
            IconButton(
              icon: Icon(_volHidden ? Icons.bar_chart : Icons.bar_chart_outlined),
              onPressed: () => setState(() => _volHidden = !_volHidden),
            ),
          ],
        ),
        SizedBox(
          height: 420,
          child: KChartWidget(
            _data,
            const KChartStyle(),
            _colors,
            isTrendLine: false,
            isLine: _isLine,
            volHidden: _volHidden,
            mainIndicators: _mainIndicators,
            secondaryIndicators: _secondaryIndicators,
            controller: _controller,
            fixedLength: 2,
            detailBuilder: (entity) => _InfoCard(entity: entity),
            onLoadMore: (isLeft) {
              // true = kéo tới mép TRÁI (nến cũ hơn) — false = kéo phải, thường bỏ qua.
              if (isLeft) _loadMoreHistory();
            },
          ),
        ),
      ],
    );
  }

  List<KLineEntity> _fetchInitialCandles() => []; // TODO: nguồn data thật

  void _loadMoreHistory() {
    // TODO: gọi REST lấy nến cũ hơn, prepend vào _data, rồi:
    // setState(() {
    //   _data = [...olderCandles, ..._data];
    //   DataUtil.calculateAll(_data, _mainIndicators, _secondaryIndicators);
    // });
  }
}

class _InfoCard extends StatelessWidget {
  final KLineEntity entity;
  const _InfoCard({required this.entity});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black87,
      child: Text(
        'O:${entity.open} H:${entity.high} L:${entity.low} C:${entity.close}',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}
```

**Kèm `DepthChart`** (order book — widget độc lập, không phụ thuộc `KChartWidget`, xem [10](#10-depthchart--orderbook-depth)):

```dart
DepthChart(
  bids,  // List<DepthEntity>, giá tốt→xa (desc), vol CUMULATIVE
  asks,  // List<DepthEntity>, giá tốt→xa (asc), vol CUMULATIVE
  const DepthChartColors(
    upColor: Color(0xFF14AD8F),
    dnColor: Color(0xFFD5405D),
  ),
  chartStyle: const DepthChartStyle(dotRadius: 5.0, crossWidth: 0.5),
  bottomLabelCount: 5, // số mốc giá ở trục dưới, >= 2
)
```

`DepthChartStyle` hiện KHÔNG có field `textStyle`/`fontSize` — nhãn trục và popup annotation của `DepthChart` vẫn hard-code `fontSize: 10`/`9` trong `depth_chart.dart` (chưa được tách ra như `CandleStyle.textStyle`/`VolumeStyle.textStyle` ở [7.2](#72-kchartcolors)); nói nếu muốn mình bổ sung tương tự.

---

## 3. Entry point & exports

File chính import: `package:k_chart_jk/k_chart_plus.dart`. Re-export:

| Export                              | Chứa gì                                                                              |
| ----------------------------------- | ------------------------------------------------------------------------------------ |
| `k_chart_widget.dart`               | `KChartWidget`, `TimeFormat`, `WidgetDetailBuilder`                                  |
| `styles/k_chart_style.dart`         | `KChartStyle`, `KChartColors`, `CandleStyle`, `CandleBodyStyle`                      |
| `styles/depth_chart_style.dart`     | `DepthChartStyle`, `DepthChartColors`                                                |
| `styles/candle_style/candle_style_icon.dart`    | `CandleStyleIcon` — icon nhỏ (2 nến mini) minh hoạ 1 `CandleBodyStyle`, vẽ bằng `CustomPainter`. |
| `styles/candle_style/candle_style_preview.dart` | `CandleStylePreview` — preview lớn (nến hoặc line chart) trên chuỗi giá tổng hợp cố định, dùng cho UI chọn "Kiểu K-line". |
| `depth_chart.dart`                  | `DepthChart` widget                                                                  |
| `chart_translations.dart`           | `DepthChartTranslations`                                                             |
| `utils/index.dart`                  | `DataUtil`, `dateFormat`, `NumberUtil`, format tokens                                |
| `entity/index.dart`                 | Toàn bộ entity & mixin                                                               |
| `renderer/index.dart`               | `ChartPainter`, `BaseChartPainter`, renderer base                                    |
| `renderer/k_chart_controller.dart`  | `KChartController`                                                                   |
| `extension/num_ext.dart`            | `num.toStringAsFixedNoZero(...)`                                                     |
| `indicator/indicator_template.dart` | `IndicatorTemplate`, `MainIndicator`, `SecondaryIndicator`, tất cả indicator + style |

---

## 4. Entity — data models

### 4.1 `KLineEntity`

Nến chính. Kế thừa `KEntity` (multi-mixin) → mang sẵn slot cho mọi chỉ báo.

| Field    | Kiểu      | Ý nghĩa                           |
| -------- | --------- | --------------------------------- |
| `open`   | `double`  | Giá mở cửa                        |
| `high`   | `double`  | Giá cao nhất                      |
| `low`    | `double`  | Giá thấp nhất                     |
| `close`  | `double`  | Giá đóng cửa                      |
| `vol`    | `double`  | Volume                            |
| `time`   | `int?`    | Timestamp **ms** (Unix epoch)     |
| `amount` | `double?` | Quote volume. Optional            |
| `change` | `double?` | Biến động giá tuyệt đối. Optional |
| `ratio`  | `double?` | % thay đổi. Optional              |

**Constructor:**

- `KLineEntity.fromCustom(...)` — truyền field thẳng.
- `KLineEntity.fromJson(json)` — parse từ Map. Fallback: nếu thiếu `time` lấy `id * 1000`.
- `.toJson()` — serialize ngược.

### 4.2 `KEntity` & các mixin

```dart
class KEntity with
    CandleEntity,    // open, high, low, close, superTrend
    VolumeEntity,    // vol, MA5Volume, MA10Volume        ★ trước MACDEntity
    KDJEntity,       // k, d, j
    RSIEntity,       // rsi
    WREntity,        // r (Williams %R)
    CCIEntity,       // cci
    OBVEntity,       // obv, obvSignal                    ★ trước MACDEntity
    TRIXEntity,      // trix, trixMa                      ★ trước MACDEntity
    MTMEntity,       // mtm, mtmMa                        ★ trước MACDEntity
    StochRSIEntity,  // stochRsiK, stochRsiD              ★ trước MACDEntity
    MACDEntity,      // dif, dea, macd  (on Vol+OBV+TRIX+MTM+StochRSI+...)
    ZigZagEntity,    // zigzag points
    AVLEntity {}     // avl (per-candle amount/vol, fallback HLC/3)
```

| Mixin            | Field                                                                             | Indicator dùng                 |
| ---------------- | --------------------------------------------------------------------------------- | ------------------------------ |
| `CandleEntity`   | `open/high/low/close`, `maValueList`, `emaValueList`, `sar`, `boll`, `superTrend` | MA, EMA, SAR, BOLL, SuperTrend |
| `VolumeEntity`   | `open/close/vol`, `MA5Volume`, `MA10Volume`                                       | Volume MA                      |
| `MACDEntity`     | `dea`, `dif`, `macd`                                                              | MACD                           |
| `KDJEntity`      | `k`, `d`, `j`                                                                     | KDJ                            |
| `RSIEntity`      | `rsi`                                                                             | RSI                            |
| `WREntity`       | `r` (%R)                                                                          | WR                             |
| `CCIEntity`      | `cci`                                                                             | CCI                            |
| `OBVEntity`      | `obv`, `obvSignal`                                                                | OBV                            |
| `TRIXEntity`     | `trix`, `trixMa`                                                                  | TRIX                           |
| `MTMEntity`      | `mtm`, `mtmMa`                                                                    | MTM                            |
| `StochRSIEntity` | `stochRsiK`, `stochRsiD`                                                          | StochRSI                       |
| `ZigZagEntity`   | `zigzag`                                                                          | ZigZag                         |
| `AVLEntity`      | `avl`                                                                             | AVL                            |

**Thứ tự mixin quan trọng** — `OBVEntity`/`TRIXEntity`/`MTMEntity` phải đứng trước `MACDEntity` (do `MACDEntity on ... OBVEntity, TRIXEntity, MTMEntity`).

### 4.3 `InfoWindowEntity`

```dart
class InfoWindowEntity {
  KLineEntity kLineEntity;  // nến đang được chọn
  bool isLeft;              // true: vẽ dialog bên trái
}
```

### 4.4 `DepthEntity`

```dart
class DepthEntity {
  double price;
  double vol;  // phải là cumulative volume
}
```

### 4.5 Mixin type system — generic indicator

Khi dùng `List<SecondaryIndicator<MACDEntity, dynamic>>`, indicator mới cần entity riêng → thêm entity vào `on` clause của `MACDEntity` và đặt trước `MACDEntity` trong `KEntity`:

```dart
// Quy tắc khi thêm entity mới
// 1. Tạo <Name>Entity mixin đơn giản (không có `on`)
// 2. Thêm <Name>Entity vào `on` clause của MACDEntity
// 3. Đặt <Name>Entity TRƯỚC MACDEntity trong KEntity
// 4. Dùng MACDEntity làm T trong <Name>Indicator
```

---

## 5. `KChartWidget` — API đầy đủ

File: `lib/k_chart_widget.dart`.

### 5.1 Required

| Param           | Kiểu                           | Ý nghĩa                               |
| --------------- | ------------------------------ | ------------------------------------- |
| `datas`         | `List<KLineEntity>?`           | Data nguồn. Empty/null = chart trống. |
| `chartStyle`    | `KChartStyle`                  | Kích thước, padding, line width.      |
| `chartColors`   | `KChartColors`                 | Toàn bộ màu.                          |
| `detailBuilder` | `Widget Function(KLineEntity)` | Builder cho info dialog (long-press). |
| `isTrendLine`   | `bool`                         | Bật mode vẽ trend line.               |

### 5.2 Indicators & display

| Param                   | Default                   | Ý nghĩa                                               |
| ----------------------- | ------------------------- | ----------------------------------------------------- |
| `mainIndicators`        | `[]`                      | List `MainIndicator` overlay trên main chart.         |
| `secondaryIndicators`   | `[]`                      | List `SecondaryIndicator` thành panel riêng bên dưới. |
| `volHidden`             | `false`                   | Ẩn panel volume.                                      |
| `isLine`                | `false`                   | `true` = line chart, `false` = candlestick.           |
| `hideGrid`              | `false`                   | Ẩn lưới ngang/dọc.                                    |
| `showNowPrice`          | `true`                    | Vẽ đường giá hiện tại.                                |
| `showInfoDialog`        | `true`                    | Cho phép hiện dialog detail.                          |
| `isTapShowInfoDialog`   | `false`                   | `true` = single tap hiện crosshair + dialog.          |
| `materialInfoDialog`    | `true`                    | Style dialog Material vs Cupertino.                   |
| `timeFormat`            | `TimeFormat.yearMonthDay` | Format thời gian dưới X axis.                         |
| `livePrice`             | `null`                    | Giá realtime override cho now price.                  |
| `bidPrice`/`askPrice`   | `null`                    | Best bid/best ask từ order book — vẽ thêm box Ask/Bid riêng, cạnh badge now-price. Xem §5.8. |
| `bidLabel`/`askLabel`   | `'Bid'`/`'Ask'`           | Text prefix trong box Ask/Bid — đổi cho i18n.         |
| `xFrontPadding`         | `40`                      | Padding phải sau nến cuối (px tại chart ≥375px). Giảm từ `100` theo yêu cầu trực tiếp — xem §12.11. |
| `verticalTextAlignment` | `right`                   | `left` / `right` — vị trí label giá dọc.              |
| `fixedLength`           | `2`                       | Số chữ số thập phân format giá.                       |

### 5.3 Pan / zoom / scroll

| Param              | Default             | Ý nghĩa                              |
| ------------------ | ------------------- | ------------------------------------ |
| `minScale`         | `0.5`               | Min cho `mScaleX`.                   |
| `maxScale`         | `2.2`               | Max cho `mScaleX`.                   |
| `flingTime`        | `600`               | ms — duration fling animation.       |
| `flingRatio`       | `0.5`               | Hệ số nhân vận tốc fling.            |
| `flingCurve`       | `Curves.decelerate` | Curve animation fling.               |
| `mBaseHeight`      | `360`               | Height (px) của main chart panel.    |
| `mSecondaryHeight` | `mBaseHeight * 0.2` | Height (px) của mỗi secondary panel. |
| `xOverscrollPadding` | `200`              | Overscroll TỐI ĐA (px tại chart ≥375px) — user kéo quá vị trí nghỉ mặc định (`scrollX = 0`) để tự lộ thêm khoảng trống bên phải (giống Binance/MEXC). Thả tay giữ nguyên vị trí, không tự bật về. `0` = tắt hẳn. Xem §12.10. |

### 5.4 Load more / callback

| Param                  | Kiểu                          | Ý nghĩa                                                                                                                                                                 |
| ---------------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `onLoadMore`           | `void Function(bool isLeft)?` | Trigger khi scroll gần biên **hoặc** khi data chưa lấp đầy chart (xem [12.9](#129-auto-load-khi-data-chưa-lấp-đầy-chart-không-cần-gesture)). `true` = load data cũ hơn. |
| `isLoadingMore`        | `bool`                        | Cờ khoá tránh duplicate request.                                                                                                                                        |
| `isOnDrag`             | `void Function(bool)?`        | Callback start/stop drag.                                                                                                                                               |
| `controller`           | `KChartController?`           | Điều khiển từ ngoài.                                                                                                                                                    |
| `onChartScaleChanged`  | `OnChartScaleChanged?`        | Emit sau mỗi lần kết thúc pinch/scaleY/zoom/reset.                                                                                                                      |
| `onVerticalOverscroll` | `ValueChanged<double>?`       | Fire khi pan Y vượt clamp 50%.                                                                                                                                          |

**Lưu ý:** `onLoadMore` không chỉ trigger từ gesture (pan/pinch/fling) mà còn tự bắn từ `initState`/`didUpdateWidget` nếu data hiện tại chưa đủ lấp đầy chiều rộng chart — không cần user tương tác gì (fix 1.0.1).

### 5.5 Zoom state

| Param        | Kiểu                | Ý nghĩa                                                 |
| ------------ | ------------------- | ------------------------------------------------------- |
| `chartScale` | `KChartScaleState?` | Scale đã lưu — truyền lại khi đổi timeframe để restore. |

### 5.6 Background watermark

| Param                   | Default | Ý nghĩa                                                      |
| ----------------------- | ------- | ------------------------------------------------------------ |
| `backgroundLogo`        | `null`  | Widget overlay ở giữa main chart. Có `IgnorePointer` nội bộ. |
| `backgroundLogoOpacity` | `1.0`   | 0.0 ẩn — 1.0 hiện đầy đủ.                                    |

### 5.7 `TimeFormat` constants & ép format nhãn trục thời gian

```dart
TimeFormat.yearMonthDay         // yyyy-MM-dd
TimeFormat.yearMonthDayWithHour // yyyy-MM-dd HH:mm
```

`KChartWidget.timeFormat` (`List<String>?`, mặc định `null`) — ép format này cho **MỌI** tick trục X + label crosshair, bất kể `tickWeight`, bỏ qua hẳn thuật toán thích ứng ở [9.4](#94-time-tick-planner--price-ticks-trục-xy). `null` (mặc định) = giữ hành vi thích ứng (format tự đổi theo mức zoom — "10" ở ranh giới ngày, "09:05" giữa ngày, ...).

> **Trước đây field này KHÔNG có tác dụng gì** — khai báo nhưng chưa từng được đọc ở đâu trong pipeline vẽ (bug tồn tại từ trước, phát hiện + sửa khi viết lại trục thời gian, xem Unreleased). Giờ nó được nối vào `chartStyle.dateTimeFormat` (field THẬT SỰ chạy tới `BaseChartPainter._updateTimeTicks`/`initFormats`) ngay trong `KChartWidget.build()`, ưu tiên `chartStyle.dateTimeFormat` nếu cả 2 cùng được set.

```dart
KChartWidget(
  data, style, colors,
  timeFormat: timeframe == d1
      ? const [dd, '-', mm, '-', yyyy]           // luôn "10-08-2026"
      : const [dd, '-', mm, ' ', hour24Padded, ':', nn], // luôn "10-08 14:30"
  // ...
)
```

### 5.8 Bid/Ask box (order book) — `bidPrice`/`askPrice`

File: `lib/renderer/chart_painter.dart` — `ChartPainter.drawBidAsk` (chạy ngay sau `drawNowPrice` trong `paint()`, xem sơ đồ §1).

Khi `bidPrice` VÀ `askPrice` cùng non-null, vẽ thêm 1 box nhỏ 2 ô xếp chồng — Ask (đỏ, `chartColors.livePriceStyle.dnColor`) ở trên, Bid (xanh, `chartColors.livePriceStyle.upColor`) ở dưới — đặt CẠNH badge now-price (do `drawNowPrice` vẽ, không đổi gì cả — badge vẫn luôn vẽ độc lập, kể cả khi có `bidPrice`/`askPrice`). Thiếu 1 trong 2 (`null`) thì không vẽ box này.

**Vị trí ngang — "về phía tâm plot", không cố định 1 phía:**

```dart
// Mép trái/phải badge now-price — CÙNG công thức drawNowPrice dùng (paddingX=6, paddingY=4, space=8.0,
// gộp thành static const _liveBadgePaddingX/_liveBadgePaddingY/_liveBadgeSpace dùng chung giữa 2 hàm):
flagBadgeWidth = priceTp.width + _liveBadgePaddingX * 2
flagLeft = verticalTextAlignment == right
    ? mPlotWidth - _liveBadgeSpace    // badge đẩy ra ngoài, nằm TRÊN price-axis strip (xem §12.11) —
                                        // chỉ lấn `space` px vào plot, KHÔNG trừ thêm flagBadgeWidth như trước
    : _liveBadgeSpace                  // badge sát mép trái (không có price-axis strip bên trái, không đổi)
flagRight = flagLeft + flagBadgeWidth

// Box luôn về phía TÂM PLOT so với badge — KHÔNG cố định "luôn bên trái":
left = verticalTextAlignment == right
    ? flagLeft - gap - boxWidth   // right: badge sát phải -> box qua TRÁI badge
    : flagRight + gap             // left: badge sát trái  -> box qua PHẢI badge
```

> **Vì sao không cố định "luôn bên trái badge":** ban đầu box được đặt cố định bên trái badge bất kể alignment. Với `right` (mặc định) điều đó đúng — badge sát mép phải, box lùi vào giữa plot. Nhưng với `left`, badge đã sát mép TRÁI plot (`flagLeft = space = 5.0`) — đặt thêm box về bên trái nữa cho ra toạ độ X **âm**, ngoài `clipRect(0, 0, size.width, size.height)` của `paint()`: box + text vẽ hoàn toàn ngoài canvas, vô hình. Phát hiện qua `/code-review`, sửa bằng quy tắc mirror theo alignment ở trên — port sang platform khác PHẢI giữ đúng nhánh `left`/`right` này, không được rút gọn về 1 công thức chung.
>
> **`flagLeft` (nhánh `right`) đã đổi công thức khi badge now-price bị đẩy ra ngoài axis (§5.9)** — `left`/box của Ask/Bid tự động "bám" theo vị trí mới của badge (không cần sửa gì thêm ở nhánh box), vì cả 2 công thức dùng chung `flagLeft` làm điểm neo.

**Vị trí dọc — LUÔN center theo Y của badge, không có ngoại lệ:**

```dart
centerY = _applyScaleY(getMainY(value)).clamp(minY, maxY)   // value = livePrice ?? datas.last.close — CÙNG value/công thức drawNowPrice dùng cho đường dashed
top = centerY - boxHeight / 2      // box 2 hàng, badge 1 hàng -> box vươn đều 2 phía quanh Y badge
```

> **Không kẹp `top` vào `[minY, maxY]` theo chiều cao box** (khác badge now-price, vốn tự kẹp theo cách riêng của nó). Đây là đánh đổi CỐ Ý theo yêu cầu trực tiếp "luôn luôn căn giữa so với live price trong mọi case": khi giá sát đỉnh/đáy dải hiển thị, box có thể tràn nhẹ ra ngoài `mMainRect` (vào phần padding trên/panel volume dưới) thay vì bị đẩy lệch tâm. Port phải giữ đúng: **ưu tiên căn giữa tuyệt đối hơn ở gọn trong `mMainRect`**, cho riêng box này (không áp dụng ngược lại cho badge now-price).

**Không throttle/toggle nào riêng cho việc vẽ** — mỗi lần `bidPrice`/`askPrice` đổi (`ChartPainter.shouldRepaint` so sánh field này) là 1 lần repaint toàn bộ, giống mọi field khác. App tự quyết định khi nào truyền giá trị thật vs `null` (xem ghi chú hiệu năng trong `README.md#bid-ask-badges-order-book` — pattern khuyến nghị: truyền thẳng `null` khi không hiển thị, không phải "tính rồi ẩn UI").

### 5.9 Vị trí badge now-price — đẩy ra ngoài, nằm trên price-axis strip

File: `lib/renderer/chart_painter.dart` — `ChartPainter.drawNowPrice`.

Theo yêu cầu trực tiếp ("đẩy live-price ra ngoài nằm trên axis Y luôn"), với `verticalTextAlignment: right` (mặc định), badge now-price giờ đặt CHỦ YẾU trên `mPriceAxisRect` (strip trục giá bên phải) thay vì nằm gọn trong `mPlotWidth` như trước:

```dart
// TRƯỚC: offsetX = mPlotWidth - tp.width - paddingX*2 - space   (badge nằm gọn trong mPlotWidth,
//         mép phải cách mPlotWidth đúng `space`)
// SAU:
offsetX = mPlotWidth - space   // chỉ lấn `space` (=5) px vào plot — đúng bằng bề rộng phần mũi tên của
                                 // LivePriceBadgePainter (trỏ vào chart, "chạm" đường dashed) — phần
                                 // THÂN badge còn lại (số giá) nằm hoàn toàn trên price-axis strip.
```

`verticalTextAlignment: left` không đổi (`offsetX = space`) — không có price-axis strip bên trái để "đẩy ra".

**Padding quanh chữ (trong) VÀ khoảng lấn vào plot (ngoài) đã điều chỉnh** theo các yêu cầu trực tiếp tiếp theo:
- `_liveBadgePaddingX`/`_liveBadgePaddingY` (padding TRONG, quanh chữ) chốt ở **6** / **4** (từng thử tăng lên 8/5 theo mẫu hình MEXC rồi giảm lại theo yêu cầu tiếp theo).
- `_liveBadgeSpace` (padding NGOÀI — khoảng badge lấn vào plot khi đóng `right`, hoặc khoảng cách mép khi đóng `left`) chốt ở **5** (từng thử tăng lên 8 rồi revert lại — yêu cầu trực tiếp "nằm ra ngoài cùng và cách 5px thui").
- Cả 3 hằng số dùng chung giữa `drawNowPrice` và `drawBidAsk` (`flagBadgeWidth`/`flagLeft`) — đổi 1 nơi, tự động khớp cả 2 hàm.
- **Strip trục giá bên phải cũng rộng ra tương ứng** (yêu cầu "cho axisY rộng ra tí") — xem `BaseChartPainter.updatePriceAxisWidth`: `clamp(maxLabelWidth + 20, 56, 104)` (trước: `+14, 48, 96`), vẫn làm tròn lên bội số 8 + hysteresis y hệt cũ. Xem `CHART_AXES.md` §7.6 (đã cập nhật đồng bộ).

> **Ảnh hưởng dây chuyền tới box Ask/Bid (§5.8):** `drawBidAsk`'s `flagLeft` dùng CHUNG công thức này (đã cập nhật đồng bộ) — nên khi badge dịch ra ngoài, box Ask/Bid (luôn "bám" cạnh badge) cũng dịch theo, tự động tiến gần lại `mPlotWidth`/vùng nến hơn trước. Port PHẢI giữ 2 công thức (`drawNowPrice`'s `offsetX` và `drawBidAsk`'s `flagLeft`) khớp nhau tuyệt đối — lệch 1 trong 2 sẽ làm box và badge không còn khớp cạnh nhau như thiết kế.

**Text hiển thị trong badge giữ nguyên số thập phân đầy đủ** (`NumberUtil.formatFixed(value, fixedLength)`), giống mọi nhãn giá khác — có thử LÀM TRÒN về số nguyên gần nhất theo yêu cầu trực tiếp ở 1 thời điểm, sau đó bị **revert lại** ("revert cái format giá của liveprice không cần phải làm tròn"). Không còn helper `_formatLivePrice`/file test `number_util_test.dart` liên quan — đã xoá cùng lúc revert.

---

## 6. `KChartController`

File: `lib/renderer/k_chart_controller.dart`. Là `ChangeNotifier`.

| Method                 | Effect                                                                                       |
| ---------------------- | -------------------------------------------------------------------------------------------- |
| `controller.zoomIn()`  | `mScaleX += 0.1`, clamp `[minScale, maxScale]`.                                              |
| `controller.zoomOut()` | `mScaleX -= 0.1`.                                                                            |
| `controller.reset()`   | `mScaleX = 1.0`, `mScrollX = 0.0`, `mSelectX = 0.0`. **Không reset `mScaleY` / `mOffsetY`**. |

**Lifecycle:**

```dart
final ctrl = KChartController();
@override
void dispose() { ctrl.dispose(); super.dispose(); }
```

---

## 7. `KChartStyle` & `KChartColors`

### 7.1 `KChartStyle`

| Field               | Default | Ý nghĩa                                         |
| ------------------- | ------- | ----------------------------------------------- |
| `topPadding`        | `20.0`  | Padding trên main chart.                        |
| `bottomPadding`     | `16.0`  | Chiều cao vùng date axis.                       |
| `childPadding`      | `12.0`  | Padding giữa các panel.                         |
| `space`             | `4.0`   | Khoảng cách trong label.                        |
| `pointWidth`        | `11.0`  | Khoảng cách tâm-tâm giữa 2 nến.                 |
| `candleWidth`       | `8.5`   | Bề rộng thân nến.                               |
| `candleLineWidth`   | `1.0`   | Bề rộng wick.                                   |
| `volWidth`          | `8.5`   | Bề rộng cột volume.                             |
| `crossWidth`        | `0.8`   | Bề rộng đường crosshair.                        |
| `nowPriceLineWidth` | `0.8`   | Bề rộng đường giá hiện tại.                     |
| `borderWidth`       | `0.5`   | Border cho crosshair label & now-price label.   |
| `gridRows`          | `4`     | Số dòng grid ngang.                             |
| `gridColumns`       | `6`     | Số cột grid dọc.                                |
| `dateTimeFormat`    | `null`  | Custom format thời gian (override auto-detect). |
| `volBarOpacity`     | `1.0`   | Độ trong suốt cột volume (0.0–1.0) — **nhân dồn** với alpha sẵn có của `volumeStyle.upColor`/`dnColor` (`VolRenderer`: `base.a * volBarOpacity`), không ghi đè. Set alpha thẳng trong `Color` hoặc qua field này đều dùng được, kết hợp được cả hai. |

Constructor: `const KChartStyle([List<String>? dateTimeFormat, double volBarOpacity = 1.0])`.

**Lưu ý:** chỉ **2 field** trong bảng trên thực sự truyền được từ ngoài vào — `dateTimeFormat` và `volBarOpacity` (2 tham số duy nhất của constructor). Toàn bộ field còn lại (`topPadding`, `bottomPadding`, `childPadding`, `space`, `pointWidth`, `candleWidth`, `candleLineWidth`, `volWidth`, `crossWidth`, `nowPriceLineWidth`, `borderWidth`, `gridRows`, `gridColumns`) được gán cứng ngay tại khai báo field (không có `this.` trong constructor) — muốn đổi kích thước nến/padding/lưới phải sửa trực tiếp trong `k_chart_style.dart`, không cấu hình được qua constructor.

### 7.2 `KChartColors`

#### `CandleStyle` — main chart (nến hoặc line chart)

| Field              | Default             | Ý nghĩa                                                          |
| ------------------ | -------------------- | ----------------------------------------------------------------- |
| `upColor`          | `0xFF14AD8F`         | Nến tăng (`MainRenderer`); cũng dùng lại cho chấm SAR khi trend tăng. |
| `dnColor`          | `0xFFD5405D`         | Nến giảm (`MainRenderer`); cũng dùng lại cho chấm SAR khi trend giảm. |
| `kLineColor`       | `0xFF217AFF`         | Đường line chart (`isLine = true`).                              |
| `kLineFillColors`  | gradient blue        | Gradient tô dưới đường line chart.                               |
| `textStyle`        | `fontSize: 10`       | Text main chart: trục giá/thời gian, crosshair, label indicator, max/min, now-price. |
| `bodyStyle`        | `CandleBodyStyle.solid` | Kiểu vẽ thân nến (candlestick mode) — xem ngay dưới.          |

**`CandleBodyStyle`** (`MainRenderer.drawCandle`) — 4 giá trị, giống "Candle style" của TradingView/Binance:

| Giá trị       | Thân nến tô đặc / chỉ viền                              |
| ------------- | --------------------------------------------------------- |
| `solid`       | Luôn tô đặc cả 2 chiều (mặc định, hành vi gốc).           |
| `hollowUp`    | Nến tăng (`close > open` CHÍNH nến đó) chỉ viền, nến giảm vẫn đặc. |
| `hollowDown`  | Nến giảm chỉ viền, nến tăng vẫn đặc.                      |
| `hollow`      | Cả 2 chiều đều chỉ viền.                                  |

Bấc nến (high-low) LUÔN vẽ đặc. Khi thân RỖNG, bấc chỉ vẽ 2 đoạn thò ra ngoài
thân (`high` → đỉnh thân, đáy thân → `low`) — KHÔNG vẽ đoạn cắt ngang ruột
thân, để thân thực sự rỗng (không có gạch xuyên giữa). Thân rỗng vẽ bằng
`MainRenderer._hollowBorderPaint` — Paint RIÊNG, luôn `PaintingStyle.stroke`,
chỉ mutate `.color`/nến — KHÔNG dùng chung `chartPaint` (Paint chính của
renderer, mặc định fill, dùng cho mọi draw khác kể cả `drawLine` của trend
line/now-price) để khỏi phải toggle style + reset lại mỗi nến rỗng.

**`CandleBodyStyleX.isHollow({required bool rising})`** (extension trên
enum `CandleBodyStyle`, cùng file) — nguồn sự thật DUY NHẤT cho "nến chiều
`rising` có nên vẽ rỗng theo style này", dùng chung bởi `MainRenderer.
drawCandle` VÀ 2 painter preview dưới đây. Trước đây bị chép tay lặp lại
switch y hệt ở cả 3 chỗ (đã sửa qua code review — sửa công thức 1 chỗ mà
quên chỗ khác thì preview lệch hình so với chart thật, không gì bắt được).

Preview UI (không phải core rendering): `CandleStyleIcon` (icon nhỏ) và
`CandleStylePreview` (preview lớn, nến hoặc line chart trên chuỗi giá tổng
hợp cố định) ở `lib/styles/candle_style/` — gọi `isHollow` ở trên, không tự
tính lại. Ví dụ dùng trong `example/lib/main.dart` (`_showSettingsSheet` →
"Kiểu K-line", 5 lựa chọn: 4 `CandleBodyStyle` + "Đường" ứng với
`isLine = true`).

**`shouldRepaint` phải so `chartColors.candleStyle.bodyStyle` riêng**
(`ChartPainter.shouldRepaint`, xem §11) — KHÔNG so nguyên `chartColors`
(instance mới mỗi build dù nội dung không đổi ở nhiều app, so reference sẽ
ép repaint mọi build). Thiếu dòng so sánh này (bug thật, đã xảy ra — bắt
được qua code review) thì đổi `bodyStyle` qua UI không tự vẽ lại ngay, chỉ
"ăn theo" lần repaint kế tiếp do lý do khác.

#### `VolumeStyle` — panel volume

| Field        | Default        | Ý nghĩa                                    |
| ------------ | -------------- | -------------------------------------------- |
| `upColor`    | `0xFF14AD8F`   | Cột volume khi nến tăng.                    |
| `dnColor`    | `0xFFD5405D`   | Cột volume khi nến giảm.                    |
| `ma5Color`   | vàng           | Đường + label MA5 của volume.               |
| `ma10Color`  | xanh           | Đường + label MA10 của volume.              |
| `textStyle`  | `fontSize: 10` | Text riêng panel volume (`VOL`/`MA5`/`MA10` + trục phải) — tách khỏi `CandleStyle.textStyle`. |

`volColor` (field cũ, không có code nào đọc) đã bị xoá khi tách sang `VolumeStyle` — không mang sang.

#### Field còn lại của `KChartColors`

| Field                                 | Default       | Vùng dùng                               |
| ------------------------------------- | ------------- | --------------------------------------- |
| `bgColor`                             | `0xFFFFFFFF`  | Background toàn chart.                  |
| `candleStyle`                         | `CandleStyle()` | Xem bảng trên.                        |
| `volumeStyle`                         | `VolumeStyle()` | Xem bảng trên.                        |
| `defaultTextColor`                    | xám           | Text mặc định — trục giá/thời gian + cross text (`ChartPainter`), đường tham chiếu secondary (`SecondaryRenderer`), popup axis label (`DepthChart`), và 6 indicator: SAR (chấm khi giá = trung điểm H/L), KDJ, MACD, MTM, OBV, TRIX, StochRSI (prefix label kiểu `"MACD(12,26,9) "`). |
| `livePriceStyle`                      | `LivePriceStyle()` | `upColor`/`dnColor` (nền badge + đường kẻ) + `textStyle` (chữ, `color` riêng — KHÔNG dùng chung `upColor`/`dnColor`) cho now-price (`ChartPainter.drawNowPrice`) — so `livePrice ?? datas.last.close` với `open` nến cuối để chọn `upColor`/`dnColor`; xem [livePrice](#livePrice--cập-nhật-giá-real-time). Class riêng trong `lib/styles/live_price_style.dart`; `drawNowPrice` vẽ badge qua `LivePriceBadgePainter` (convert từ `assets/Number.svg`) thay vì RRect phẳng. |
| `trendLineColor`                      | cam           | Trend line.                             |
| `selectBorderColor`                   | đen           | Border của crosshair label box.         |
| `selectFillColor`                     | trắng         | Fill của crosshair label box.           |
| `gridColor`                           | xám nhạt      | Đường grid.                             |
| `crossColor`                          | đen           | Crosshair lines.                        |
| `crossTextColor`                      | đen           | Text trong crosshair label.             |
| `maxColor` / `minColor`               | đen           | Label giá max/min trong khung hiển thị. |

#### Style riêng từng indicator (16 field)

`KChartColors` gom style của **mọi** main + secondary indicator vào 1 chỗ, để cấu hình màu toàn bộ chart mà không cần tự tạo từng instance indicator với `indicatorStyle` riêng:

| Field           | Type              | Indicator      |
| --------------- | ----------------- | -------------- |
| `maStyle`       | `MAStyle`          | MA             |
| `emaStyle`      | `MAStyle`          | EMA (field riêng với `maStyle` dù cùng type — để MA/EMA tô màu khác nhau) |
| `bollStyle`     | `BOLLStyle`        | BOLL           |
| `sarStyle`      | `SARStyle`         | SAR            |
| `zigzagStyle`   | `ZigZagStyle`      | ZigZag         |
| `superTrendStyle` | `SuperTrendStyle` | SuperTrend   |
| `avlStyle`      | `AVLStyle`         | AVL            |
| `macdStyle`     | `MACDStyle`        | MACD           |
| `kdjStyle`      | `KDJStyle`         | KDJ            |
| `rsiStyle`      | `RSIStyle`         | RSI            |
| `wrStyle`       | `WRStyle`          | WR             |
| `cciStyle`      | `CCIStyle`         | CCI            |
| `obvStyle`      | `OBVStyle`         | OBV            |
| `trixStyle`     | `TRIXStyle`        | TRIX           |
| `mtmStyle`      | `MTMStyle`         | MTM            |
| `stochRsiStyle` | `StochRSIStyle`    | StochRSI       |
| `brarStyle`     | `BRARStyle`        | BRAR           |
| `biasStyle`     | `BIASStyle`        | BIAS           |
| `psyStyle`      | `PSYStyle`         | PSY            |
| `atrStyle`      | `ATRStyle`         | ATR            |

**Cơ chế áp dụng — `applyIndicatorColorStyles()`** (`lib/indicator/indicator_template.dart`):

- Chạy 1 lần trong constructor của `ChartPainter`, nhận `mainIndicators`, `secondaryIndicators`, `chartColors`.
- Dùng Dart 3 pattern-matching `switch` theo runtime type (vd `case AVLIndicator m:`) để biết field `KChartColors` nào tương ứng.
- **Chỉ ghi đè** `indicator.indicatorStyle` khi instance đó còn dùng đúng style mặc định — phát hiện qua field tường minh `IndicatorTemplate.isDefaultStyle` (`= indicatorStyle == null` tại constructor, vì mọi indicator giờ nhận `XxxStyle?` nullable). Nếu instance tự truyền `indicatorStyle` khác mặc định (vd `AVLIndicator(indicatorStyle: AVLStyle(avlColor: Colors.red))`) thì **giữ nguyên**, không bị `KChartColors` ghi đè — instance-level luôn thắng. *(Trước đây dùng `identical(ind.indicatorStyle, const AVLStyle())` — bỏ vì không phân biệt được "không truyền" với "truyền const y hệt default", xem mục Unreleased.)*
- Kéo theo: `IndicatorTemplate.indicatorStyle` không còn `final` (mutable field), để cho phép gán lại.

```dart
KChartWidget(
  data,
  const KChartStyle(),
  const KChartColors(
    candleStyle: CandleStyle(upColor: Colors.cyan, dnColor: Colors.deepOrange),
    volumeStyle: VolumeStyle(ma5Color: Colors.amber),
    avlStyle: AVLStyle(avlColor: Colors.purple),
    rsiStyle: RSIStyle(rsiColor: Colors.pink),
  ),
  mainIndicators: [AVLIndicator(), MAIndicator()], // không cần tự truyền indicatorStyle
  secondaryIndicators: [RSIIndicator()],
  ...
)
```

**Dark mode example:**

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

---

## 8. Indicators — main & secondary

### 8.1 Hierarchy

```
IndicatorTemplate<T, K>   ← abstract
├── MainIndicator<T, K>     ← overlay trên main chart
│   ├── MAIndicator
│   ├── BOLLIndicator
│   ├── EMAIndicator
│   ├── SARIndicator
│   ├── ZigZagIndicator
│   ├── SuperTrendIndicator
│   └── AVLIndicator
└── SecondaryIndicator<T, K> ← panel riêng bên dưới
    ├── MACDIndicator
    ├── KDJIndicator
    ├── RSIIndicator
    ├── WRIndicator
    ├── CCIIndicator
    ├── OBVIndicator
    ├── TRIXIndicator
    ├── MTMIndicator
    └── StochRSIIndicator
```

### 8.2 Built-in indicators

#### MA — main

- **Style:** `MAStyle({ List<Color> maColors })`
- **calcParams:** `[5,10,30,60]`
- **Output:** `entity.maValueList[i]`

#### BOLL — main

- **Style:** `BOLLStyle({ bollColor, ubColor, lbColor, fillColor })`
- **calcParams:** `[20, 2]` — (period, std multiplier)
- **Output:** `entity.boll = Boll { up, mid, dn, bollMa }`

#### EMA — main

- **Style:** `MAStyle`
- **calcParams:** `[5, 10, 20]`
- **Output:** `entity.emaValueList[i]`

#### SAR — main

- **Style:** `SARStyle({ upColor, dnColor, radius, strokeWidth })` — chấm + label tô theo xu hướng: `sar <= (high+low)/2` (SAR nằm dưới giá) = tăng → `upColor`; ngược lại = giảm → `dnColor`.
- **Output:** `entity.sar = double?`

#### ZigZag — main

- **Style:** `ZigZagStyle({ zigzagColor, lineWidth })`
- **calcParams:** `[5]` (deviation %)
- **Output:** `entity.zigzag = double?` chỉ ở pivot

#### SuperTrend — main

- **Style:** `SuperTrendStyle({ upColor, dnColor, upFillColor, dnFillColor, lineWidth })`
- **calcParams:** `[10, 30]` — (ATR period, ATR multiplier ÷10 → factor 3.0)
- **Output:** `entity.superTrend = SuperTrend { value, isUp }` (class định nghĩa trong `super_trend_indicator.dart`, field nằm ở `CandleEntity` — KHÔNG cần entity mixin riêng vì là main indicator)
- **Vẽ:** đường band đổi màu theo `isUp` (xanh khi uptrend — band dưới giá, đỏ khi downtrend — band trên giá) + fill mờ giữa band và giá. Label `SUPER: x` cũng đổi màu theo trend.
- **Công thức:**
  ```
  ATR = RMA(TR, N)                   // TR = max(h-l, |h-prevC|, |l-prevC|)
                                     // seed = SMA(TR,N), sau đó Wilder: atr = (atr×(N-1)+tr)/N
  upperBand = (h+l)/2 + factor×ATR
  lowerBand = (h+l)/2 - factor×ATR
  trend flip khi close cắt qua band hiện tại
  ```

#### AVL — main

- **Style:** `AVLStyle({ avlColor, lineWidth })`
- **calcParams:** `[]` — không có param chu kỳ
- **Output:** `entity.avl` (mixin `AVLEntity` — theo pattern ZigZag: mixin đứng sau `MACDEntity` trong `KEntity`, indicator cast `entity as AVLEntity` vì main indicator dùng `CandleEntity` làm T)
- **Vẽ:** đường line màu tím đi **xuyên qua thân từng nến** (kiểu AVL trên app Binance) — mỗi điểm là giá khớp lệnh trung bình của chính nến đó, nên luôn nằm trong range high–low.
- **Công thức:**
  ```
  AVL = AMOUNT / VOL                   // quote volume ÷ base volume của nến
  fallback (amount null/0 hoặc vol=0):
  AVL = (HIGH + LOW + CLOSE) / 3       // typical price
  ```
- **Lưu ý:** cần API trả `amount` (quote volume) trong `KLineEntity` để có giá trị thực; thiếu thì fallback typical price — đường vẫn bám nến nhưng không phản ánh volume-weighting thực. Các biến thể từng thử và bỏ: cumulative VWAP (đường trôi xa khỏi cụm nến khi giá chạy dài, kéo giãn trục Y vì `getMaxMinValue` phải bao giá trị AVL) và rolling VWAP N nến (mượt hơn nhưng vẫn lệch khỏi nến, không giống Binance).

#### Ichimoku Kinko Hyo — main

- **Style:** `IchimokuStyle({ tenkanColor, kijunColor, chikouColor, spanAColor, spanBColor, cloudUpColor, cloudDownColor })`
- **calcParams:** `[9, 26, 52]` — (tenkanPeriod, kijunPeriod, spanBPeriod); bộ crypto thường dùng `[20, 60, 120]`. `shift` LUÔN = `calcParams[1]` (kijun period) — đổi param thì shift đổi theo, không hardcode `26`.
- **Output:** `entity.ichimoku = Ichimoku { tenkan, kijun, spanA, spanB }` (field trực tiếp trên `CandleEntity`, giống `boll`/`sar` — không cần entity mixin riêng). Không lưu `chikou` — luôn `= close`, dịch ở draw-time.
- **Công thức:**
  ```
  HH(p)/LL(p) = cao/thấp nhất trong p nến gần nhất (bao gồm nến hiện tại) — sliding-window monotonic deque O(n)
  tenkan[i] = i >= tenkanP-1 ? (HH(tenkanP)+LL(tenkanP))/2 : null
  kijun[i]  = i >= kijunP-1  ? (HH(kijunP)+LL(kijunP))/2  : null
  spanA[i]  = (tenkan[i] != null && kijun[i] != null) ? (tenkan[i]+kijun[i])/2 : null
  spanB[i]  = i >= spanBP-1 ? (HH(spanBP)+LL(spanBP))/2 : null
  ```
- **Vẽ (draw-time, không phải trong `calc()`)** — đây là điểm khác biệt lớn nhất so với mọi indicator khác trong bảng này:
  ```
  Tenkan/Kijun:    (lastX, curX)                                          — không dịch
  Senkou Span A/B: (lastX + shift×pointWidth, curX + shift×pointWidth)    — dịch TỚI TRƯỚC
  Chikou:          (lastX - shift×pointWidth, curX - shift×pointWidth), y = close  — dịch LÙI
  ```
  Mây (Kumo) tô giữa Span A/B đã dịch; nếu dấu `(spanA-spanB)` đổi giữa `lastPoint`/`curPoint` → tách polygon tại điểm giao (nội suy tuyến tính `t = lastDiff/(lastDiff-curDiff)`), tô 2 nửa 2 màu (`cloudUpColor`/`cloudDownColor`) — không tách sẽ tô sai màu cả đoạn giao nhau.
- **`futureShift`:** `IchimokuIndicator.futureShift = shift` — indicator đầu tiên trong thư viện khai báo giá trị này (`MainIndicator.futureShift` mặc định `0`, no-op cho mọi indicator khác). Kích hoạt cơ chế mở rộng trục X ở [11](#11-renderer-internals) mục "Vùng tương lai" — chart tự chừa `shift` nến trống bên phải nến cuối để mây không bị cắt cụt, tự mở rộng biên scroll/zoom tương ứng.
- **Lưu ý:** với chart `itemCount < 52` (chưa đủ nến cho Span B), các field vẫn `null` đúng vị trí warm-up thay vì sentinel `0` — không vẽ đường/mây rác kéo về 0. Crosshair/tap-selection bị clamp về nến thật đang hiển thị, KHÔNG cho chọn vào vùng tương lai trống (đơn giản hoá có chủ đích, xem mục Ichimoku ở `indicator.md` ở root repo).

#### MACD — secondary

- **Style:** `MACDStyle({ upColor, dnColor, macdColor, difColor, deaColor, macdWidth })`
- **calcParams:** `[12, 26, 9]`
- **Output:** `entity.dif`, `entity.dea`, `entity.macd = (dif-dea)*2`

#### KDJ — secondary

- **Style:** `KDJStyle({ kColor, dColor, jColor })`
- **calcParams:** `[9, 3, 3]`
- **Output:** `k`, `d`, `j` ∈ [0, 100]

#### RSI — secondary

- **Style:** `RSIStyle({ rsiColor })`
- **calcParams:** `[14]`
- **Output:** `rsi` ∈ [0, 100]

#### WR — secondary

- **Style:** `WRStyle({ wrColor })`
- **calcParams:** `[14]`
- **Output:** `r` ∈ [-100, 0]

#### CCI — secondary

- **Style:** `CCIStyle({ cciColor })`
- **calcParams:** `[14]`
- **Output:** `cci`

#### OBV — secondary

- **Style:** `OBVStyle({ obvColor, signalColor })`
- **calcParams:** `[5]` — period cho signal MA
- **Output:** `obv` (cumulative), `obvSignal` (MA của OBV)
- **Công thức:**
  ```
  obv[0] = vol[0]
  obv[i] = obv[i-1] + vol[i]   // nến tăng
  obv[i] = obv[i-1] - vol[i]   // nến giảm
  signal = SMA(obv, 5)
  ```

#### TRIX — secondary

- **Style:** `TRIXStyle({ trixColor, trixMaColor })`
- **calcParams:** `[12, 20]` — (N: chu kỳ triple EMA, M: chu kỳ MA signal)
- **Output:** `entity.trix`, `entity.trixMa` (mixin `TRIXEntity`)
- **Công thức:**
  ```
  EMA1 = EMA(CLOSE, N)
  EMA2 = EMA(EMA1, N)
  EMA3 = EMA(EMA2, N)
  TRIX   = (EMA3 - REF(EMA3,1)) / REF(EMA3,1) × 100
  MATRIX = MA(TRIX, M)
  ```
- **Lưu ý:** `trix` null ở nến đầu tiên (chưa có `prevEma3`); `trixMa` null cho tới khi đủ M giá trị TRIX. EMA seed bằng `close` của nến đầu. MA signal dùng sliding-window sum O(n).

#### MTM — secondary

- **Style:** `MTMStyle({ mtmColor, mtmMaColor })`
- **calcParams:** `[12, 6]` — (N: chu kỳ momentum, M: chu kỳ MA signal)
- **Output:** `entity.mtm`, `entity.mtmMa` (mixin `MTMEntity`)
- **Công thức:**
  ```
  MTM   = CLOSE - REF(CLOSE, N)    // biến thể tuyệt đối (classic)
  MTMMA = MA(MTM, M)
  ```
- **Lưu ý:** `mtm` null khi `i < N` (chưa đủ N nến trước); `mtmMa` null cho tới khi đủ M giá trị MTM. Giá trị MTM có scale phụ thuộc giá tuyệt đối của symbol (BTC sẽ ra hàng trăm/nghìn) — nếu cần scale % thì đổi công thức sang `(CLOSE - REF)/REF × 100` (ROC-style), chỉ 1 dòng trong `calc()`.

#### StochRSI — secondary

- **Style:** `StochRSIStyle({ kColor, dColor })`
- **calcParams:** `[14, 14, 3, 3]` — (N1: RSI length, N2: Stoch length, M1: smooth %K, M2: smooth %D) — chuẩn Binance/TradingView
- **Output:** `entity.stochRsiK`, `entity.stochRsiD` (mixin `StochRSIEntity`), dao động 0–100 (quá mua >80, quá bán <20)
- **Công thức:**
  ```
  RSI      = RSI(CLOSE, N1)          // Wilder smoothing, tính NỘI BỘ
  StochRSI = (RSI - MIN(RSI,N2)) / (MAX(RSI,N2) - MIN(RSI,N2)) × 100
  %K       = SMA(StochRSI, M1)
  %D       = SMA(%K, M2)
  ```
- **Lưu ý:**
  - RSI được tính **nội bộ trong `calc()`**, KHÔNG dùng lại `entity.rsi` — vì `RSIIndicator` có thể không được bật (calc chỉ chạy cho indicator trong list) và period có thể khác nhau.
  - Null-chain: RSI cần N1+1 nến → stoch cần đủ N2 giá trị RSI → %K cần M1 → %D cần M2. Với params mặc định, %K có từ nến ~30, %D từ nến ~32.
  - Edge case `MAX == MIN` (RSI đi ngang tuyệt đối trong N2 nến): StochRSI = 0 theo convention TradingView.
  - StochRSI nhạy hơn RSI nhiều — thường xuyên chạm 0/100 là hành vi đúng, không phải bug.
  - **Đường tham chiếu 20/80** (quá bán/quá mua, kiểu Binance): khai báo qua `referenceValues => [20, 80]`; `getMaxMinValue` ép range bao luôn `[20, 80]` để 2 vạch không bao giờ nằm ngoài panel. Cơ chế vẽ: `SecondaryRenderer.drawReferenceLines()` — nét đứt 4px-4px, màu `defaultTextColor` alpha 90, vẽ ở screen space TRƯỚC translate/scale trong `ChartPainter.drawChart()` (nên không giãn theo scaleX, nằm sau đường K/D, và vẫn hiện khi `hideGrid = true`). Indicator phụ khác muốn có vạch tham chiếu chỉ cần override `referenceValues`.

#### BRAR — secondary

- **Style:** `BRARStyle({ arColor, brColor })`
- **calcParams:** `[26]` — chu kỳ cửa sổ trượt (N)
- **Output:** `entity.ar`, `entity.br` (mixin `BRAREntity` — nối vào `on` clause của `MACDEntity`, đứng trước `MACDEntity` trong `KEntity`'s `with` chain, cùng vị trí với `StochRSIEntity`)
- **Công thức:**
  ```
  AR = Σ(HIGH - OPEN, N) / Σ(OPEN - LOW, N) × 100
  BR = Σmax(0, HIGH - REF(CLOSE,1), N) / Σmax(0, REF(CLOSE,1) - LOW, N) × 100
  ```
  Tính bằng rolling-sum O(n) (không brute-force lại tổng mỗi nến). Chia cho 0 (mẫu số = 0) → trả `0.0` thay vì để NaN/Infinity.
- **Công dụng:** đo tâm lý/động lực thị trường qua BIÊN ĐỘ nến (high/low/open) thay vì chỉ giá đóng cửa như RSI — AR đo "năng lượng" quanh giá mở cửa, BR đo ý chí mua/bán so với giá đóng cửa phiên trước. Cả 2 cùng cao (>150-200) → quá hưng phấn, dễ điều chỉnh giảm; cả 2 cùng thấp (<50) → quá bi quan, dễ hồi phục. BR cắt AR hoặc 2 đường phân kỳ mạnh báo hiệu đổi momentum. Không phải chỉ báo xu hướng — chỉ dùng lọc tín hiệu kèm indicator xu hướng khác (MA/SuperTrend...).
- **Lưu ý:** `BR` cần `prevClose` nên bắt đầu trễ hơn `AR` đúng 1 nến trong giai đoạn warm-up (AR đủ N tại `i=N-1`, BR đủ N tại `i=N`) — không phải bug, do bản chất công thức cần dữ liệu nến trước đó.

#### BIAS — secondary

- **Style:** `BIASStyle({ biasColors })` — `List<Color>`, mặc định 3 màu, `getBiasColor(i)` cùng pattern `MAStyle.getMAColor(i)`.
- **calcParams:** `[6, 12, 24]` — nhiều chu kỳ cùng lúc (không giới hạn đúng 3, thêm/bớt phần tử tự áp dụng).
- **Output:** `entity.biasValueList = List<double?>` (mixin `BIASEntity` — nối vào `on` clause của `MACDEntity`, đứng trước `MACDEntity`, cùng vị trí `BRAREntity`) — song song 1:1 với `calcParams`, dùng `double?` (không phải sentinel `0` như `MAStyle.maValueList`) vì BIAS hợp lệ đi qua 0 (giá cắt MA) rất thường xuyên.
- **Công thức:** `BIAS(n) = (close - MA(close,n)) / MA(close,n) × 100%`, tính bằng rolling-sum O(n) (không brute-force lại tổng mỗi nến, cùng kỹ thuật `MA.calc()`). Chia cho 0 (MA=0) → trả `0.0`.
- **Công dụng:** đo % lệch giá so với MA cùng chu kỳ — lệch dương/âm lớn báo hiệu giá đang chạy quá xa MA, dễ điều chỉnh về; 3 đường hội tụ gần 0 thường báo hiệu sắp biến động mạnh.

#### PSY — secondary

- **Style:** `PSYStyle({ psyColor, maPsyColor })`
- **calcParams:** `[12, 6]` — (N: chu kỳ đếm phiên tăng, M: chu kỳ MA tín hiệu)
- **Output:** `entity.psy`, `entity.psyMa` (mixin `PSYEntity` — nối vào `on` clause của `MACDEntity`, đứng trước `MACDEntity`, cùng vị trí `BIASEntity`)
- **Công thức:** `PSY = COUNT(close > REF(close,1), N) / N × 100`; `MAPSY = MA(PSY, M)` — cả 2 tính bằng rolling window (đếm tăng + rolling-sum), không brute-force lại mỗi nến.
- **Công dụng:** đo % số phiên tăng trong N phiên — phản ánh tâm lý đám đông. PSY quá cao (>75-83) → quá lạc quan, dễ điều chỉnh; quá thấp (<25-17) → quá bi quan, dễ hồi phục. MAPSY cắt PSY dùng lọc tín hiệu.
- **Lưu ý:** `PSY` cần `REF(close,1)` (giá phiên trước) nên bắt đầu tại `i=N` (không phải `i=N-1`) — cùng loại "trễ 1 nến khởi tạo" như `BR` của BRAR.

#### ATR — secondary

- **Style:** `ATRStyle({ atrColor, atrMaColor })`
- **calcParams:** `[14, 6]` — (N: chu kỳ làm mượt Wilder của ATR, M: chu kỳ MA tín hiệu MAATR)
- **Output:** `entity.atr`, `entity.atrMa` (mixin `ATREntity` — nối vào `on` clause của `MACDEntity`, đứng trước `MACDEntity`, cùng vị trí `PSYEntity`)
- **Công thức:**
  ```
  TR       = max(HIGH-LOW, |HIGH-REF(CLOSE,1)|, |LOW-REF(CLOSE,1)|)
  ATR[N-1] = SMA(TR, N)                          (seed Wilder smoothing)
  ATR[i]   = (TR[i] + (N-1) × ATR[i-1]) / N       (i >= N)
  MAATR    = MA(ATR, M)
  ```
  Wilder smoothing giống cách `RSIIndicator` làm mượt RMax/RAbs — khác rolling-sum thuần của BRAR/BIAS vì ATR cần trọng số giảm dần theo thời gian (EMA-like) thay vì trung bình cộng đơn giản trong cửa sổ trượt.
- **Công dụng:** đo độ biến động (volatility), không đo hướng. ATR cao = nến dao động rộng (biến động mạnh); ATR thấp = thị trường yên tĩnh. Không phải chỉ báo xu hướng — dùng để đặt stop-loss theo biến động thực tế hoặc điều chỉnh kích thước vị thế.
- **Lưu ý:** `TR` tại nến đầu tiên (`i=0`) không có `prevClose` nên chỉ dùng `high-low`; `ATR` bắt đầu có giá trị từ `i=N-1` (seed bằng SMA của N giá trị TR đầu, không phải Wilder smoothing ngay từ đầu) — cùng convention warm-up như RSI.

### 8.3 Custom indicator

```dart
class MyIndicator extends MainIndicator<CandleEntity, MyStyle> {
  MyIndicator() : super(
    name: 'myThing', shortName: 'MY',
    calcParams: [10], indicatorStyle: const MyStyle(),
  );

  @override
  void calc(List<KLineEntity> data) { /* populate field */ }

  @override
  (double, double) getMaxMinValue(KLineEntity e, double minV, double maxV) { ... }

  @override
  void drawChart(lastPoint, curPoint, lastX, curX, getY, canvas, colors) { ... }

  @override
  TextSpan? drawFigure(CandleEntity e, int precision, KChartColors c) { ... }
}
```

### 8.4 Pattern thêm secondary indicator mới

```
1. Tạo lib/entity/<name>_entity.dart
2. Thêm vào lib/entity/macd_entity.dart (on clause)
3. Thêm vào lib/entity/k_entity.dart (TRƯỚC MACDEntity)
4. Export trong lib/entity/index.dart
5. Thêm <Name>Style vào lib/indicator/indicator_style.dart
6. Tạo lib/indicator/secondary/<name>_indicator.dart
7. Thêm part vào indicator_template.dart
8. Thêm button + case vào example/main.dart
```

---

## 9. `DataUtil` & helpers

### 9.1 `DataUtil`

| Method                                          | Effect                                                                      |
| ----------------------------------------------- | --------------------------------------------------------------------------- |
| `calculateAll(data, mains, secondaries)`        | Gọi `calcVolumeMA` + tính tất cả indicator. Phải gọi mỗi khi data thay đổi. |
| `calculateIndicators(data, mains, secondaries)` | Chỉ tính indicator, bỏ qua volume MA.                                       |
| `calculateIndicator(data, indicator)`           | Tính 1 indicator riêng.                                                     |
| `calcVolumeMA(data)`                            | Tính `MA5Volume` & `MA10Volume`.                                            |

**Quan trọng:** Khi load thêm data cũ (left), phải merge list rồi gọi `calculateAll` LẠI trên list mới — indicator phụ thuộc vào toàn bộ historical data.

### 9.2 `NumberUtil`

| Method                                     | Ví dụ                                |
| ------------------------------------------ | ------------------------------------ |
| `NumberUtil.format(value, precision)`      | Format tự động (loại trailing zero). |
| `NumberUtil.formatFixed(value, precision)` | Fix precision (giữ trailing zero).   |

### 9.3 Date format

`dateFormat(DateTime, List<String> tokens)` — tokens trong `date_format_util.dart`:

| Token              | Output                |
| ------------------ | --------------------- |
| `yyyy` `yy`        | Năm 4/2 chữ số        |
| `mm`               | Tháng (padded)        |
| `dd` `d`           | Ngày (padded/compact) |
| `hour24Padded` `H` | Giờ 24h               |
| `nn` `n`           | Phút                  |
| `ss` `s`           | Giây                  |

**Cache label ngày (`ChartPainter.getDate`):** kết quả `dateFormat()` được cache trong `static Map<int, String> _dateStringCache` (key = timestamp) để tránh format lại mỗi frame. Cache bị clear khi `mFormats` đổi — so sánh **theo nội dung** (`_formatsEqual`, so từng phần tử), KHÔNG theo reference, vì `initFormats()` gán 1 list literal mới mỗi lần `ChartPainter` được dựng lại (mỗi build) dù nội dung format không đổi; so theo reference sẽ khiến cache bị xoá gần như mỗi frame và mất tác dụng.

### 9.4 Time-tick planner & price ticks (trục X/Y)

> **Thay thế hoàn toàn** cơ chế cũ ("Auto-detect time format & grid alignment" — chia đều `mGridColumns` cột, format chọn theo khoảng cách 2 candle đầu). Bản cũ có 1 nhược điểm cố hữu: số lượng/vị trí label KHÔNG đổi theo `barSpacing` (zoom) trong 1 phiên — chỉ đổi khi `ChartPainter` được dựng lại với data mới. Bản mới (theo `CHART_AXES.md`, spec tự chứa — đọc file đó nếu cần công thức chính xác) tính lại tick **mỗi frame** theo đúng mức zoom hiện tại. `mGridColumns`/`gridColumns` không còn quyết định gì cho trục thời gian nữa.

**Trục X — `lib/utils/time_ticks.dart`, gọi từ `BaseChartPainter._updateTimeTicks()` (trong `calculateValue()`, 1 lần/frame):**

1. **Tick weight** (`KLineEntity.tickWeight`, cache 1 lần lúc load/append, KHÔNG tính lại mỗi frame): mỗi nến được gán 1 trong 12 bậc `MINOR..YEAR` dựa trên việc timestamp (local time) có rơi đúng ranh giới lịch không (`alignmentWeight`), cộng thêm `crossingWeight` (bắt case nến không thẳng hàng ranh giới local — vd nến 4h ở GMT+7 rơi 03:00/07:00/11:00, không có `hour==0`).
2. **Threshold** (`thresholdRung`): suy TRỰC TIẾP từ hình học (`barSpacing`, `interval`) — KHÔNG đếm số nến hiển thị (đếm sẽ dao động ±1 khi pan, gây nhấp nháy).
3. **Kế hoạch** (`buildTimeTickPlan`, cache qua `TimeTickPlanner` — instance sở hữu bởi `_KChartWidgetState`, key `(identityHashCode(candles), count, barSpacing.round(), interval, format)`): lọc ứng viên qua threshold, đóng gói theo `MIN_GAP_X=64px` trên **absolute space** (`absX(i) = i*barSpacing + barSpacing/2`, KHÔNG trừ `scrollOffset`) — pan không đổi tick nào được chọn (invariant I4). Ưu tiên weight cao trước (đảm bảo ranh giới ngày thắng nến intraday), tie-break theo index. Key có `identityHashCode` để đổi symbol/timeframe (data khác) không tái dùng nhầm plan cũ; `barSpacing` làm tròn px CHỈ trong key (giá trị build thật vẫn chính xác) để pinch-zoom không rebuild toàn dataset gần như mỗi frame.
4. **Chiếu mỗi frame** (`_updateTimeTicks`): lọc lại theo pixel `x = translateXtoX(getX(index)) ∈ [0, mPlotWidth]` — KHÔNG theo margin index, xem fix "label dính cứng ở mép" trong Unreleased.
5. **Label text** — `_updateTimeTicks()` truyền `forcedFormat` cho `TimeTickPlanner`, ưu tiên theo thứ tự: `KChartStyle.dateTimeFormat` (consumer tự set) → `mFormats` (mặc định HIỆN TẠI — format CỐ ĐỊNH suy 1 lần từ khoảng cách 2 nến đầu qua `initFormats()`, xem [11](#11-renderer-internals) "Vùng tương lai" phía trên nó). `_labelFor`'s nhánh thích ứng theo `tickWeight` từng tick (`YEAR→"2026"`, `MONTH→"Aug"`, `DAY→"10"`, còn lại→`"09:05"`) CHỈ chạy khi `forcedFormat == null` — tức hiện tại KHÔNG bao giờ null (luôn có `mFormats` fallback) nên nhánh thích ứng này hiện không active, dù code vẫn còn nguyên. Ép qua `KChartWidget.timeFormat`/`KChartStyle.dateTimeFormat` vẫn hoạt động như mô tả ở [5.7](#57-timeformat-constants--ép-format-nhãn-trục-thời-gian), chỉ là thắng `mFormats` chứ không phải thắng "không có gì".

Kết quả cache vào `BaseChartPainter.mTimeTicks` (`List<({int index, double x, String label})>`) — `drawGrid()` (đường dọc, dùng chung cho main/vol/secondary) VÀ `drawDate()` (label) đều đọc TỪ ĐÂY, không renderer nào tự chọn tick riêng (invariant I3/I6).

**Trục Y — `lib/utils/price_ticks.dart`, gọi từ `MainRenderer` constructor (mỗi frame, renderer bị dựng lại mỗi lần `initChartRenderer()`):**

```dart
niceStep(range, targetTicks)   // ladder 1·2·2.5·5·10 × 10^n
decimalsFor(step)              // KHÔNG suy từ magnitude — sai với họ step 2.5
priceTicks(minPrice: ..., maxPrice: ..., height: ..., targetTicks: 6)
```

Range đưa vào `priceTicks()` là range giá **THỰC SỰ đang hiển thị** (`MainRenderer._priceAtScreenY(chartRect.top/bottom)` — nghịch đảo transform canvas `scaleY`/`offsetY` thật, không phải `minValue`/`maxValue` auto-scale gốc) — nếu dùng range gốc, zoom Y (gesture kéo dọc) sẽ khiến hầu hết tick dạt ra ngoài view (xem fix trong Unreleased). Grid ngang + độ rộng strip giá (`priceAxisWidth`, [11](#11-renderer-internals) "Price axis strip") đều ăn theo cùng `_priceTicks` này.

**Test:** `test/time_ticks_test.dart` (T1-T5: never-blank, min-gap, no-dup-label, pan-stability, append-stability), `test/price_ticks_test.dart` (T6-T7: price ticks trong range, decimals đúng cho họ 2.5) — chạy `flutter test` ở root repo.

---

## 10. `DepthChart` — orderbook depth

File: `lib/depth_chart.dart`. Widget độc lập với `KChartWidget`.

### Constructor

```dart
DepthChart(
  bids,                              // List<DepthEntity>
  asks,                              // List<DepthEntity>
  chartColors, {                     // DepthChartColors
  baseUnit = 2,
  quoteUnit = 6,
  offset = const Offset(8, 0),
  chartTranslations = const DepthChartTranslations(),
  chartStyle = const DepthChartStyle(),
  backgroundLogo,
  backgroundLogoOpacity = 1,
  bottomLabelCount = 5,              // số mốc giá ở trục dưới (>=2)
})
```

**`bottomLabelCount`:** Nội suy tuyến tính từng đoạn:

- `[bids.first.price..centerPrice]` nửa trái
- `[centerPrice..asks.last.price]` nửa phải
- `centerPrice = (bids.last.price + asks.first.price) / 2`

### `DepthChartStyle`

| Field         | Default |
| ------------- | ------- |
| `lineWidth`   | `1.0`   |
| `radius`      | `4.0`   |
| `strokeWidth` | `0.6`   |
| `space`       | `2.0`   |
| `padding`     | `6.0`   |
| `dotRadius`   | `5.0`   |
| `crossWidth`  | `0.5`   |

### `DepthChartColors`

- `upColor` / `upFillPathColor` — bid (xanh + fill mờ).
- `dnColor` / `dnFillPathColor` — ask (đỏ + fill mờ).
- `defaultTextColor`, `annotationColor`, `crossColor`, `barrierColor`, `selectBorderColor`, `selectFillColor`.

---

## 11. Renderer internals

### Layout dọc + ngang (price axis strip, CHART_AXES.md §7)

Layout giờ 2 chiều — dọc như trước (main/vol/secondary/date), NHƯNG mỗi rect chỉ rộng `mPlotWidth`, phần còn lại bên phải (`mPlotWidth..mWidth`) là 1 cột riêng dùng chung cho label giá của MỌI panel:

```
        0                                          mPlotWidth      mWidth
        ┌──────────────────────────────────────────────┬──────────────┐
        │  mTopPadding                                  │              │
        ├────────────────────────────────────────────── │              │
        │              mMainRect                        │              │
        ├────────────────────────────────────────────── │              │
        │  mVolRect   (null nếu volHidden)              │  mPriceAxisRect
        ├────────────────────────────────────────────── │  (label giá của
        │  mSecondaryRectList[0]                        │   main/vol/     │
        ├────────────────────────────────────────────── │   secondary,    │
        │  mSecondaryRectList[1]                        │   cùng 1 cột)   │
        ├──────────────────────────────────────────────┼──────────────┤
        │  mDateRect  (rộng = mPlotWidth, KHÔNG mWidth)  │  mCornerRect │
        └──────────────────────────────────────────────┴──────────────┘
```

- `mPlotWidth = max(1, mWidth - priceAxisWidth)`. `priceAxisWidth` đọc từ `priceAxisWidthCache.value` (instance `PriceAxisWidthCache`, sở hữu bởi `_KChartWidgetState`, truyền vào painter qua constructor — **không phải `static`**; đổi lại sau code review vì `static` khiến nhiều `KChartWidget` đồng thời rò rỉ layout vào nhau, xem Unreleased) — tự đo theo label rộng nhất của `MainRenderer` — clamp `[48,96]`, làm tròn bội 8, hysteresis (chỉ thu khi thấp hơn hẳn 1 bậc, chống vòng lặp phản hồi width→layout→label→width). Đo/cập nhật ở CUỐI `initChartRenderer()` (gọi `updatePriceAxisWidth()`, giờ là instance method), áp dụng cho FRAME SAU (trễ đúng 1 frame — phá vòng lặp tự tham chiếu mà không cần biết trước độ rộng label).
- `mCornerRect` (góc dưới-phải, giao strip giá × trục thời gian) — không thuộc trục nào, chỉ tô nền (`drawBg`) để 2 đường phân cách kết thúc gọn.
- 2 đường phân cách khung (`ChartPainter._drawAxisSeparators`, vẽ trong `drawGrid()`): dọc tại `x=mPlotWidth` (cao hết plot+strip giá+trục thời gian), ngang tại đỉnh `mDateRect` (rộng hết `mWidth`).
- `VolRenderer`/`SecondaryRenderer`/`MainRenderer` đều nhận thêm `priceAxisRect` (constructor) — vẽ label giá vào ĐÓ thay vì đè lên nội dung panel như trước. 13 file indicator (MACD/KDJ/RSI/...) không sửa gì — `SecondaryRenderer.drawVerticalText` dùng `canvas.translate(priceAxisRect.left, 0)` để công thức `chartRect.width - x` sẵn có của chúng (giả định local x=0) vẫn đúng dù `priceAxisRect.left != 0`.
- Crosshair (`drawCrossLineText`) là layer DUY NHẤT không bị giới hạn `mPlotWidth` — vẫn dùng `mWidth`, vì readout label của nó CỐ Ý tràn vào cả strip giá lẫn trục thời gian (CHART_AXES.md §7.5).

### Tọa độ X

```dart
getX(index)         = index * mPointWidth + mPointWidth / 2
xToTranslateX(x)    = -mTranslateX + x / scaleX
indexOfTranslateX() = binary search trên getX(i)
translateXtoX(tx)   = (tx + mTranslateX) * scaleX
```

`mStartIndex`/`mStopIndex` (viewport thô, xem bảng 3-phạm-vi bên dưới) tính qua `xToTranslateX(0)`/`xToTranslateX(mPlotWidth)` — **`mPlotWidth`, không phải `mWidth`** (dùng `mWidth` sẽ tính dư index vào phần bị strip giá che khuất, làm lệch auto-scale giá).

**Tick trục X thật sự hiển thị** (`mTimeTicks`, `List<({int index, double x, String label})>`) tính trong `calculateValue()` qua `BaseChartPainter._updateTimeTicks()` — thuật toán weight-ladder đầy đủ ở [9.4](#94-time-tick-planner--price-ticks-trục-xy) + `CHART_AXES.md` §5. `drawGrid()`/`drawDate()` chỉ đọc từ đây, không tự chọn tick.

### Tọa độ Y

```dart
// BaseChartRenderer
scaleY = chartRect.height / (maxValue - minValue)
getY(v) = (maxValue - v) * scaleY + chartRect.top

// Screen Y thực sự (sau canvas transform scaleY + offsetY):
double _applyScaleY(double rawY) {
  final centerY = (mMainRect.top + mMainRect.bottom) / 2;
  return (centerY + (rawY - centerY) * scaleY + offsetY)
      .clamp(mMainRect.top, mMainRect.bottom);
}
```

`_applyScaleY` dùng cho label vẽ ngoài canvas transform (nowPrice, maxMin, crosshair). `MainRenderer` có bản NGHỊCH ĐẢO riêng, `_priceAtScreenY(yScreen)` — suy giá TẠI 1 toạ độ Y màn hình, dùng để tính range giá đang thực sự hiển thị rồi sinh tick nice-number theo đó (xem [9.4](#94-time-tick-planner--price-ticks-trục-xy)). 2 hàm này là nghịch đảo của nhau về mặt toán học (cùng công thức `centerY + (v-centerY)*scaleY + offsetY`, chỉ khác `centerY` là `(mMainRect.top+bottom)/2` hay `scaleCenterY` truyền vào — thực chất là 1).

### Vùng tương lai (future zone) — indicator dịch trục (Ichimoku)

Thêm khi implement Ichimoku ([8.2](#82-built-in-indicators)) — cơ chế dùng chung, không hardcode riêng cho 1 indicator. Bất kỳ `MainIndicator` nào override `futureShift` (mặc định `0`) đều tự động được renderer chừa chỗ:

```dart
mFutureSlots = max(futureShift trên toàn bộ mainIndicators đang bật)   // 0 nếu không indicator nào cần
mDataLen     = (mItemCount + mFutureSlots) * mPointWidth               // thay vì chỉ mItemCount * mPointWidth
// → getMinTranslateX()/maxScrollX tự mở rộng, indexOfTranslateX() tự dò được vào vùng tương lai
```

**3 phạm vi index — dùng lẫn nhau là nguồn bug chính** (đã xảy ra thật khi thêm Ichimoku lần này, xem Unreleased §1, fix xong):

| Phạm vi | Có thể vượt `itemCount-1`? | Dùng cho |
|---|---|---|
| `mStartIndex`/`mStopIndex` (viewport thô) | Có | Chỉ dùng nội bộ để tính 2 phạm vi dưới, KHÔNG index thẳng vào `datas!` |
| `mVisibleStartIndex`/`mVisibleStopIndex` (= viewport ∩ dữ liệu thật) | Không | Label max/min giá + index của nó, autoscale trục Y main/volume/secondary, nến hiển thị label chỉ số góc trên, clamp crosshair |
| `mRealStartIndex`/`mRealStopIndex` (= vùng hiển thị, nới rộng `mFutureSlots` mỗi phía) | Không | CHỈ 2 việc: vòng lặp vẽ của main renderer (cần nến nguồn cho đường bị dịch), và đóng góp Y-range của riêng indicator có `futureShift > 0` |

Volume/secondary renderer **không** cần vùng "real" mở rộng — dùng `mVisibleStartIndex`/`mVisibleStopIndex` là đủ, dùng nhầm vùng rộng hơn chỉ tốn thêm draw call vô ích cho nến off-screen (bị clip nên không sai hình, nhưng lãng phí).

`timeAt(index)` — ngoại suy timestamp tuyến tính cho vùng tương lai (`lastTime + k × interval`, `interval` = khoảng cách 2 nến thật cuối cùng) — đủ cho thị trường 24/7, không xử lý lịch phiên nghỉ.

### Padding phải tỷ lệ

```dart
static const double referenceChartWidth = 375.0;

static double effectiveRightPaddingPx(double xFrontPadding, double chartWidth) {
  if (chartWidth <= 0) return xFrontPadding;
  final ratio = chartWidth / referenceChartWidth;
  return xFrontPadding * (ratio < 1.0 ? ratio : 1.0);
}

double getMinTranslateX() {
  // mPlotWidth, không phải mWidth — nến cuối phải cách MÉP PLOT (không phải
  // mép strip giá) đúng khoảng padding này.
  final paddingData = effectiveRightPaddingPx(xFrontPadding, mPlotWidth) / scaleX;
  var x = -mDataLen + mPlotWidth / scaleX - mPointWidth / 2 - paddingData;
  return x >= 0 ? 0.0 : x;
}
```

| `mPlotWidth` (xFrontPadding=40, default hiện tại) | Padding màn hình |
| --------------------------------- | ---------------- |
| ≥ 375px                           | 40px             |
| 250px                              | ~27px            |
| 187px                              | ~20px            |

> Trước khi có strip giá, hàm này dùng thẳng `mWidth` (= `mPlotWidth` lúc đó vì chưa có strip). `effectiveRightPaddingPx` vẫn còn dùng nguyên cho mục đích này; nó KHÔNG còn quyết định bề rộng vùng gesture scaleY nữa — xem [12.3](#123-scale).

### `KChartScaleState`

```dart
class KChartScaleState {
  final double scaleX;   // zoom ngang
  final double scaleY;   // zoom dọc main
  final double scrollX;  // offset scroll (0 = nến mới nhất)

  const KChartScaleState({
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.scrollX = 0.0,
  });

  KChartScaleState clampedTo({required double minScale, required double maxScale});
  KChartScaleState copyWith({double? scaleX, double? scaleY, double? scrollX});
}
```

### Luồng vẽ mỗi frame

```
paint()
├── (§7.8) return sớm nếu size.width/height <= 0 — không vẽ garbage vào Rect âm
├── initRect()           → mPlotWidth (theo priceAxisWidth cache TỪ FRAME TRƯỚC), mMainRect/mVolRect/mSecondaryRectList/mDateRect (rộng = mPlotWidth), mPriceAxisRect, mCornerRect
├── calculateValue()     → mStartIndex/mStopIndex (theo mPlotWidth), max/min, mTimeTicks (weight-ladder planner)
├── initChartRenderer()  → dựng renderer (nhận priceAxisRect) rồi ĐO LẠI label rộng nhất → BaseChartPainter.updatePriceAxisWidth() cho FRAME SAU
├── drawBg()              (phủ cả strip giá + ô góc chết, không riêng mPlotWidth)
├── drawGrid()             (theo mTimeTicks + _priceTicks mỗi panel) + 2 đường phân cách khung
├── drawChart()
│   ├── canvas transform (scaleX, translateX)
│   ├── canvas transform (scaleY, offsetY) → clip mMainRect
│   │   ├── MainRenderer.drawChart()
│   │   └── VolRenderer.drawChart()    ← ngoài scaleY scope
│   └── SecondaryRenderer.drawChart()  ← ngoài scaleY scope
├── drawVerticalText()    (vẽ vào mPriceAxisRect, không đè lên nội dung panel)
├── drawDate()             (clip canvas theo mPlotWidth — label trượt/cắt tự nhiên như nến, không kẹp)
├── drawText()          ← dùng getItem(mStopIndex) không phải datas!.last
├── drawMaxAndMin()        (flip trái/phải theo mPlotWidth/2, không phải mWidth/2)
└── drawNowPrice()      ← dùng livePrice nếu có, fallback datas!.last.close
```

### shouldRepaint — logic kiểm soát khi nào vẽ lại

`ChartPainter` được tạo mới mỗi lần `build()` nhưng `paint()` chỉ chạy khi `shouldRepaint` trả `true`.

**`BaseChartPainter.shouldRepaint`** so sánh:

```
datas, scaleX, scaleY, scrollX, isLongPress, selectX, isOnTap, offsetY, volHidden, isLine, mainIndicators, secondaryIndicators
```

**`ChartPainter.shouldRepaint`** (override) bổ sung:

```
livePrice     ← bắt buộc vì livePrice nằm trong ChartPainter, không phải BaseChartPainter
isTrendLine
selectY
lines         ← so sánh THEO GIÁ TRỊ (_trendLinesEqual), KHÔNG theo reference
chartColors.candleStyle.bodyStyle   ← so field CỤ THỂ, KHÔNG so nguyên chartColors
                                       (instance mới mỗi build ở nhiều app dù nội
                                       dung không đổi — so reference sẽ ép repaint
                                       mọi build, phản tác dụng)
```

**Quy tắc:** nếu thêm field mới vào `ChartPainter`/`BaseChartPainter` mà ảnh hưởng visual → phải thêm vào `shouldRepaint`, nếu không chart sẽ không cập nhật (đã xảy ra thật với `isLine`, `isTrendLine`/`selectY`/`lines`, và `chartColors.candleStyle.bodyStyle` — xem changelog). Field nào nằm TRONG `chartColors` (hay bất kỳ object phức hợp nào được dựng mới mỗi build) mà cần theo dõi → so field CỤ THỂ đó (theo giá trị), không so nguyên object cha theo reference.

**Bẫy `!=` trên field bị mutate in-place:** `lines` (`List<TrendLine>`) bị `KChartWidget` sửa in-place (`lines.add(...)`, `lines.removeLast()`) rồi truyền cùng reference vào `ChartPainter` mỗi build → `oldDelegate.lines` và `lines` LUÔN là cùng 1 object, so sánh `!=` không bao giờ đúng dù nội dung đã đổi. Cách sửa đúng — áp dụng cùng nguyên tắc với `datas`/`livePrice`:

1. Widget truyền **snapshot mới** mỗi build: `lines: List<TrendLine>.of(lines)`.
2. `shouldRepaint` so sánh **theo giá trị** từng phần tử (`p1`, `p2`, `maxHeight`, `scale`), vì `TrendLine` không override `==`.

### livePrice — cập nhật giá real-time

`livePrice: double?` là prop riêng biệt với `datas`. Dùng để cập nhật đường giá hiện tại (`drawNowPrice`) theo WebSocket tick mà **không cần tạo hoặc thay thế list `datas`**.

```dart
// chart_painter.dart — drawNowPrice()
final double value = livePrice ?? datas!.last.close;
// → màu đường so theo value vs datas!.last.open
```

**Pattern đúng:**

```dart
// ✓ datas chỉ thay đổi khi nến đóng; livePrice thay đổi mỗi tick
KChartWidget(
  datas: _closedCandles,
  livePrice: _currentPrice,
  ...
)
```

**Anti-pattern — sửa candle in-place:**

```dart
// ❌ datas cùng reference → shouldRepaint trả false → chart không update
_datas.last.close = newPrice;
setState(() {});

// ✓ nếu muốn update datas: tạo list mới
setState(() => _datas = [..._datas.sublist(0, _datas.length - 1), updatedCandle]);
```

**Throttle khi tick tần suất cao (>10/giây):**

```dart
// Chỉ setState tối đa 60fps; cập nhật _currentPrice mọi lúc
_currentPrice = newPrice;
if (_lastRender == null || now - _lastRender! > 16) {
  setState(() {});
  _lastRender = now;
}
```

---

## 12. Gesture model

### 12.1 Single tap

- Trong main rect: toggle crosshair.
- `isTrendLine: true`: tap = record điểm cho trend line.

### 12.2 Long press

- Hiện crosshair + drag để di chuyển.
- Phát `InfoWindowEntity` qua stream → `detailBuilder` render dialog.

### 12.3 Scale

`onScaleStart` chốt 2 cờ:

- `_isScaleYGesture`: 1 ngón + chạm trong vùng phải rộng `BaseChartPainter.priceAxisWidth` (**không còn** `effectiveRightPaddingPx`/`xFrontPadding` — đó là padding sau nến cuối, không liên quan tới strip giá; đổi khi thêm price axis strip, xem Unreleased) → scaleY.
- `_gestureInMain`: `painter.isInMainRect(localFocalPoint)`. Nếu **false** (vol/secondary/date), chỉ scroll X, forward dy cho outer scroll.

> **Bẫy:** từ khi có strip giá riêng, `mMainRect` không còn phủ hết chiều rộng — chạm strip giá TRONG hàng main cũng khiến `isInMainRect` trả `false`. `onScaleUpdate` phải loại trừ rõ `_isScaleYGesture` khỏi điều kiện `!_gestureInMain` (đã fix), nếu không gesture scaleY hợp lệ trên strip bị nhánh "outside main" nuốt mất, biến thành forward-outer-scroll sai.

`onScaleUpdate` — 4 nhánh khi `_gestureInMain == true` **hoặc** `_isScaleYGesture == true`:

| Điều kiện                         | Hành vi                                                            |
| --------------------------------- | ------------------------------------------------------------------ |
| `_dragStartedInTapMode` && 1 ngón | Di chuyển crosshair.                                               |
| `_isScaleYGesture` && 1 ngón      | `mScaleY -= delta * 0.005`, clamp `[0.3, 5.0]`.                    |
| `details.scale != 1.0` (≥2 ngón)  | `mScaleX = lastScale * scale`, clamp.                              |
| 1 ngón drag tự do                 | `mScrollX += dx / mScaleX`, clamp `[ChartPainter.minScrollX, ChartPainter.maxScrollX]` (không còn `[0, maxScrollX]` — xem §12.10). Pan Y chỉ active khi `mScaleY != 1.0`. |

**Gesture gate vol/secondary:**

```
Finger chạm vol/secondary + 1 ngón:
  dx → scrollX nến (như main)
  dy → forward onVerticalOverscroll (KHÔNG pan chart Y)
Pinch ≥2 ngón: scaleX bình thường
```

### 12.4 Clamp `mOffsetY`

```dart
double _clampOffsetY(double v) {
  final maxOffset = mBaseHeight * mScaleY / 2;
  return v.clamp(-maxOffset, maxOffset);
}
```

### 12.5 Overscroll handoff

```dart
// Trong KChartWidget — detect overscroll
if (mScaleY != 1.0) {
  final newOffsetY = mOffsetY + dy;
  final clampedOffsetY = _clampOffsetY(newOffsetY);
  mOffsetY = clampedOffsetY;
  final overscroll = newOffsetY - clampedOffsetY;
  if (overscroll != 0) widget.onVerticalOverscroll?.call(overscroll);
}
```

**Quy ước dấu:** `delta > 0` = finger drag DOWN (chart ở biên +max); `delta < 0` = finger drag UP.

### 12.6 Double-tap (vùng phải scaleY)

Double-tap trong cùng vùng `priceAxisWidth` ở trên → reset `mScaleY = 1.0`, `mOffsetY = 0.0`.

### 12.7 Fling

Sau drag end, animation Tween chạy với `flingTime` ms, `flingCurve`, `flingRatio` × velocity.

### 12.8 Auto-compensate scroll khi append nến mới

```dart
void _compensateScrollOnDataChange(KChartWidget oldWidget) {
  final diff = newData.length - oldData.length;
  if (diff <= 0) return;
  final appended = oldData.first.time == newData.first.time
      && oldData.last.time != newData.last.time;
  if (!appended) return;
  if (mScrollX <= 0.0) return;  // rightmost → auto-follow
  mScrollX += diff * widget.chartStyle.pointWidth;
}
```

### 12.9 Auto-load khi data chưa lấp đầy chart (không cần gesture)

Các trigger `onLoadMore` khác (13.7 fling, `onScaleUpdate`/`onScaleEnd`) chỉ chạy khi user thực hiện gesture. Nếu data ban đầu (hoặc sau khi load thêm vẫn) chưa đủ lấp đầy chiều rộng chart — `ChartPainter.maxScrollX <= 0` — và user chưa tương tác gì, `onLoadMore` sẽ **không bao giờ** được gọi, chart đứng im thiếu data (fix trong 1.0.1).

```dart
int? _narrowLoadRequestedForLength;

@override
void initState() {
  super.initState();
  ...
  _maybeLoadMoreForNarrowData();
}

@override
void didUpdateWidget(KChartWidget oldWidget) {
  super.didUpdateWidget(oldWidget);
  ...
  _maybeLoadMoreForNarrowData();
}

void _maybeLoadMoreForNarrowData() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    if (widget.isLoadingMore || widget.onLoadMore == null) return;
    final data = widget.datas;
    if (data == null || data.isEmpty) return;
    if (ChartPainter.maxScrollX > 0) return;
    if (_narrowLoadRequestedForLength == data.length) return;
    _narrowLoadRequestedForLength = data.length;
    widget.onLoadMore!(true);
  });
}
```

Điểm quan trọng:

- **`addPostFrameCallback`**: `ChartPainter.maxScrollX` chỉ đúng **sau** khi `paint()` chạy xong với data hiện tại (`base_chart_painter.dart:247`), nên phải đợi hết frame mới đọc được giá trị mới nhất.
- **`_narrowLoadRequestedForLength` (dedupe guard)**: `didUpdateWidget` fire trên **mọi** rebuild của parent, kể cả những rebuild không liên quan tới `datas` (đổi theme, đổi style...). Nếu không có guard này, mỗi rebuild trong lúc `isLoadingMore` chưa kịp được parent set `true` (thường bất đồng bộ, sau khi await API) sẽ gọi lại `onLoadMore(true)` → spam nhiều request trùng. Guard chỉ cho phép request lại khi `data.length` thực sự thay đổi so với lần request gần nhất.
- **Giới hạn đã biết**: `ChartPainter.maxScrollX` là field `static`, dùng chung cho **mọi instance** `KChartWidget` trong app. Nếu có nhiều chart cùng render trong 1 frame (multi-chart view), giá trị đọc được trong `addPostFrameCallback` có thể là của chart khác paint sau cùng trong frame đó, không phải của chính widget này. Không ảnh hưởng nếu app chỉ hiển thị 1 chart tại 1 thời điểm.

### 12.10 Overscroll bên phải — `xOverscrollPadding` (giống Binance/MEXC)

File: `lib/renderer/base_chart_painter.dart` (`minScrollX`, `calculateValue`), `lib/k_chart_widget.dart` (mọi nơi clamp `mScrollX`).

Từ trước, `scrollX` luôn bị chặn cứng ở `[0, maxScrollX]` — `0` là vị trí nghỉ mặc định (nến cuối cách mép plot đúng `xFrontPadding`), không cho kéo QUÁ vị trí đó. Giờ có thêm `BaseChartPainter.minScrollX` (static, cùng vòng đời `maxScrollX` — set lại mỗi `calculateValue()`):

```dart
minScrollX = min(0.0, -(effectiveRightPaddingPx(xOverscrollPadding, mPlotWidth) / scaleX));
```

- Dùng lại NGUYÊN `effectiveRightPaddingPx` (đã có sẵn cho `xFrontPadding`, §5.2) — overscroll co giãn theo bề rộng chart hẹp giống hệt cách `xFrontPadding` co giãn.
- `xOverscrollPadding = 0` (mặc định ở `BaseChartPainter`/`ChartPainter` khi dựng trực tiếp, không qua `KChartWidget`) → `minScrollX = 0` → **không đổi hành vi cũ**.
- `KChartWidget.xOverscrollPadding` mặc định `200` (từng là `150`, tăng thêm theo yêu cầu trực tiếp) — luôn bật ở tầng widget.
- `min(0.0, ...)`: chốt cứng tại NGUỒN, không phụ thuộc `xOverscrollPadding` không âm. Lý do: nếu `xOverscrollPadding` bị truyền ÂM (dùng sai, không có validate) VÀ `maxScrollX <= 0` (chart không có gì để scroll — data ít, vừa hết màn hình), biểu thức phía trong CÓ THỂ ra số DƯƠNG, làm `minScrollX > maxScrollX` — mọi `.clamp(minScrollX, maxScrollX)` trong `k_chart_widget.dart` (2 chỗ `onScaleUpdate`, 1 chỗ khôi phục `chartScale`, 1 chỗ fling animation) ném `ArgumentError` (`min > max`), crash cả widget. Phát hiện + reproduce qua `/code-review`, sửa bằng `min(0.0, ...)` ngay tại nguồn thay vì sửa từng chỗ gọi `.clamp`.

**Mọi nơi trong `k_chart_widget.dart` từng clamp `mScrollX` vào `[0, maxScrollX]` đổi thành `[minScrollX, maxScrollX]`:** 2 nhánh `onScaleUpdate` (§12.3), khôi phục `chartScale` (`_restoreChartScaleFromWidget`, §13.8 — cả 2 pha, xem `architecture.md` §6.13 cho chi tiết cơ chế 2 pha), và điều kiện dừng fling animation (§12.7 — `mScrollX <= 0` → `mScrollX <= minScrollX`).

**Không có snap-back/elastic:** kéo quá vị trí nghỉ, thả tay ra → **giữ nguyên** vị trí đã kéo (kể cả fling văng quá mức cho phép — dừng cứng ngay tại `minScrollX`, không bật lại). Muốn về lại vị trí nghỉ thì user tự kéo ngược. Đây là quyết định thiết kế xác nhận trực tiếp — khác hẳn overscroll kiểu iOS (rubber-band tự bật về).

**An toàn index khi `scrollX` âm** (vùng `translateX` trước đây chưa từng đạt tới): đã audit `indexOfTranslateX` (binary search tự bão hoà trong `[0, mItemCount+mFutureSlots-1]`, không thể trả về ngoài dải) và mọi chỗ dùng `mStartIndex`/`mStopIndex` sau đó (đều có `min`/`max` clamp lại) — không có rủi ro out-of-bounds. Port sang platform khác PHẢI đảm bảo tương đương: index/binary-search tự bão hoà, không throw khi `translateX` vượt xa biên đã biết trước đây.

### 12.11 Giảm khoảng trống nghỉ mặc định — `xFrontPadding` 100 → 40

Theo yêu cầu trực tiếp ("chart có 1 khoảng cách... muốn nhỏ lại gần với axis Y"): `KChartWidget.xFrontPadding` mặc định giảm từ `100` xuống `40` — vị trí nghỉ mặc định lúc mới mở chart (chưa scroll gì) có nến cuối nằm GẦN trục giá hơn nhiều so với trước.

An toàn để giảm mà không cần đổi gì khác, vì 2 lý do:
1. Badge now-price (§5.9) giờ đặt CHỦ YẾU trên price-axis strip, chỉ lấn `~8px` vào plot — không còn phụ thuộc `xFrontPadding` lớn để tránh đè nến cuối như thiết kế cũ (badge cũ từng nằm gọn trong plot, cần nhiều khoảng trống hơn).
2. `xOverscrollPadding` (§12.10, mặc định `200`, luôn bật) đã tách riêng "khoảng trống user CÓ THỂ tự kéo ra thêm" khỏi "khoảng trống mặc định lúc nghỉ" — muốn lộ thêm khoảng trống thì user tự kéo, không cần `xFrontPadding` lớn sẵn.

Không đổi công thức `effectiveRightPaddingPx`/`getMinTranslateX` (mục "Padding phải tỷ lệ" ở §11) — chỉ đổi GIÁ TRỊ mặc định truyền vào.

---

## 13. Recipes — công thức thường dùng

### 13.1 Live tick

```dart
void onTick(double newClose) {
  final last = data.last;
  final updated = KLineEntity.fromCustom(
    time: last.time!,
    open: last.open,
    close: newClose,
    high: max(last.high, newClose),
    low: min(last.low, newClose),
    vol: last.vol + 0.1,
    amount: 0,
  );
  final next = [...data.sublist(0, data.length - 1), updated];
  DataUtil.calculateAll(next, mains, secondaries);
  setState(() => data = next);
}
```

### 13.2 Load more khi scroll trái

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

### 13.3 Dark theme

```dart
KChartColors(
  bgColor: Color(0xFF1C1C1E),
  defaultTextColor: Color(0xFF8E8E93),
  gridColor: Color.fromARGB(255, 187, 187, 187),
  selectFillColor: Color(0xFF2C2C2E),
  selectBorderColor: Color(0xFF636366),
  crossColor: Color(0xFFEBEBF5),
  crossTextColor: Color(0xFFEBEBF5),
  maxColor: Color(0xFFEBEBF5),
  minColor: Color(0xFFEBEBF5),
)
```

### 13.4 Toggle nhiều secondary

```dart
List<SecondaryIndicator> get _secondary => [
  if (showMACD) MACDIndicator(),
  if (showKDJ) KDJIndicator(),
  if (showRSI) RSIIndicator(),
];
```

### 13.5 Custom date format

```dart
KChartWidget(
  data, style, colors,
  detailBuilder: ...,
  isTrendLine: false,
  timeFormat: const [dd, '/', mm, ' ', hour24Padded, ':', nn],
)
```

### 13.6 Watermark logo

```dart
KChartWidget(
  ...,
  backgroundLogo: SvgPicture.asset('assets/logo.svg', width: 80, height: 80),
  backgroundLogoOpacity: 0.15,
)
```

### 13.7 External zoom buttons

```dart
final ctrl = KChartController();
KChartWidget(..., controller: ctrl)
IconButton(onPressed: ctrl.zoomIn, icon: Icon(Icons.zoom_in))
IconButton(onPressed: ctrl.zoomOut, icon: Icon(Icons.zoom_out))
IconButton(onPressed: ctrl.reset, icon: Icon(Icons.refresh))
```

### 13.8 Lưu/khôi phục zoom state khi đổi timeframe

```dart
KChartScaleState? _savedScale;

KChartWidget(
  _data, chartStyle, chartColors,
  chartScale: _savedScale,
  onChartScaleChanged: (s) => setState(() => _savedScale = s),
  ...
)
// Khi đổi timeframe: truyền _savedScale vào instance mới → widget tự restore.
```

### 13.10 Real-time WebSocket price ticker

```dart
// State:
double? _livePrice;
List<KLineEntity> _datas = [];

// WebSocket onMessage:
void _onTick(double price) {
  _livePrice = price;
  setState(() {});  // chỉ update livePrice, không đụng _datas
}

// Khi nến đóng (push nến mới từ server):
void _onCandleClose(KLineEntity newCandle) {
  final next = [..._datas, newCandle];
  DataUtil.calculateAll(next, mains, secondaries);
  setState(() {
    _datas = next;
    _livePrice = null;  // reset để drawNowPrice tự fallback về close của nến cuối
  });
}

// Build:
KChartWidget(
  _datas,
  chartStyle, chartColors,
  livePrice: _livePrice,
  datas: _datas,
  ...
)
```

> `livePrice` thay đổi → `shouldRepaint` trả `true` → chỉ `drawNowPrice()` là thực sự cần vẽ lại.  
> `datas` reference thay đổi → full repaint (tính lại min/max, grid, toàn bộ nến).

### 13.9 Overscroll handoff sang outer scrollview

```dart
void _onChartVerticalOverscroll(double delta) {
  if (!_outerScrollController.hasClients) return;
  final pos = _outerScrollController.position;
  // Đảo dấu: chart pan dùng mOffsetY += dy (content theo finger).
  // Scroll Flutter ngược lại: pixels TĂNG = reveal content dưới.
  final target = (pos.pixels - delta).clamp(
    pos.minScrollExtent,
    pos.maxScrollExtent,
  );
  if (target != pos.pixels) {
    _outerScrollController.jumpTo(target);
  }
}

// Build:
SingleChildScrollView(
  controller: _outerScrollController,
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

## 14. Troubleshooting & pitfalls

### "Indicator không hiện"

- Đã gọi `DataUtil.calculateAll(data, mains, secondaries)` chưa? Phải gọi lại MỖI khi list data thay đổi.
- Đủ data cho period chưa? VD MA30 cần ≥30 nến.

### "Sai data sau load more"

- Phải merge `[...older, ...current]` ROI `calculateAll` lại trên list merged.

### "Time hiển thị sai"

- `time` phải là **milliseconds** Unix epoch. Nếu API trả seconds, nhân 1000.

### "Crosshair label dính vào cạnh"

- Tăng `xFrontPadding` (mặc định `40`px tại chart ≥375px — giảm từ `100` theo yêu cầu trực tiếp, xem §12.11).

### "Chart hẹp vẫn chừa khoảng trống lớn bên phải"

- Giảm `xFrontPadding` hoặc chỉnh `referenceChartWidth` trong `base_chart_painter.dart`.

### "Stream has already been listened to"

- `mInfoWindowStream` phải là `StreamController.broadcast()`.

### "Pan dọc không hoạt động"

- Pan dọc CHỈ active sau khi user đã scaleY (`mScaleY != 1.0`). Drag dọc vùng phải (`effectiveRightPaddingPx`) để zoom dọc trước.

### "Outer scroll ăn gesture chart"

- Khi nhúng trong `SingleChildScrollView`, track pointer events và toggle physics → `NeverScrollableScrollPhysics` khi finger trên chart.

### "Live price không cập nhật"

- Không sửa `datas` in-place (`_datas.last.close = x`) — cùng reference, `shouldRepaint` trả `false`.
- Dùng `livePrice` prop thay thế, hoặc tạo list mới: `_datas = [..._datas.dropLast(), updated]`.
- Nếu thêm field visual mới vào `ChartPainter`: bắt buộc thêm vào `shouldRepaint`, nếu không chart không vẽ lại khi field đó thay đổi.

### "Live tick lag"

- `DataUtil.calculateAll` chạy O(n × số indicator). Với n > 1000 nến cân nhắc tính incremental.
- Tick tần suất cao (>10/giây): throttle `setState` về 60fps thay vì gọi mỗi message.

### "Mixin order error"

- Giữ đúng thứ tự mixin trong `k_entity.dart`. `OBVEntity` PHẢI trước `MACDEntity`.

### "onLoadMore không được gọi khi zoom out nhỏ"

- Điều kiện đã mở rộng: `maxScrollX <= 0 || mScrollX >= maxScrollX * 0.8`. Post-frame callback trong `onScaleEnd` xử lý trường hợp pinch zoom out.

### "Volume panel không tách ra dưới chart"

- `BaseDimension._mVolumeHeight = 0` theo design hiện tại; volume overlay vào main rect.

### "ZigZagIndicator chỉ vẽ vài điểm"

- Bình thường — chỉ pivot mới có value. Tăng/giảm `calcParams[0]` (deviation %) để có nhiều/ít pivot.

---

---

## 15. Phân tích cơ chế Y Grid & Anchor Zoom (MEXC / TradingView)

> Tổng hợp từ phân tích kỹ thuật `anchor_zoom.md` và `scroll_vertical_y.md`. Đây là tham khảo thiết kế — k_chart_jk hiện dùng mô hình `mScaleY + mOffsetY` (canvas transform), không phải `visibleMinPrice / visibleMaxPrice` làm state chính.
>
> **Cập nhật:** phần **16.2 Dynamic Y Grid** bên dưới giờ **đã implement**, chỉ khác cách tiếp cận — không lưu `visibleMinPrice`/`visibleMaxPrice` làm state, mà mỗi frame `MainRenderer` NGHỊCH ĐẢO transform `mScaleY`/`offsetY` hiện có để suy ra range đang hiển thị (`_priceAtScreenY`), rồi sinh nice-number step từ range đó (`lib/utils/price_ticks.dart`, xem [9.4](#94-time-tick-planner--price-ticks-trục-xy)) — cùng kết quả cuối (grid tự thích ứng, không nhảy), khác cơ chế lưu trữ. 16.1 (Vertical Scroll bằng `visibleMinPrice`/`visibleMaxPrice`) và 16.3 (Anchor Zoom tường minh) vẫn CHỈ là tham khảo, chưa áp dụng — `mScaleY`/`offsetY` hiện tại không anchor chính xác tại điểm chạm khi zoom Y (chỉ có `zoomAt` cho trục X làm việc này — xem `CHART_AXES.md` §4).

### 15.1 Vertical Scroll — di chuyển khoảng giá

TradingView **không** dùng `translateY`. Thay vào đó nó quản lý hai biến:

```dart
double visibleMinPrice;
double visibleMaxPrice;
```

Khi người dùng kéo dọc:

```dart
void onVerticalDrag(double dy) {
  final deltaPrice = dy / scaleY;   // pixel → price unit
  visibleMinPrice += deltaPrice;
  visibleMaxPrice += deltaPrice;
  repaint();
}
```

`scaleY` luôn được tính lại từ price range:

```dart
double scaleY = chartHeight / (visibleMaxPrice - visibleMinPrice);
```

**Công thức render:**

```dart
// price → screen Y
screenY = chartHeight - (price - visibleMinPrice) * scaleY;

// screen Y → price (inverse)
price = visibleMinPrice + (chartHeight - y) / scaleY;
```

**So sánh với translateY đơn giản:**

|              | `translateY += dy` | TradingView approach |
| ------------ | ------------------ | -------------------- |
| Cài đặt      | Đơn giản           | Phức tạp hơn         |
| Price range  | Không rõ           | Tường minh           |
| Anchor zoom  | Khó                | Chính xác            |
| Grid đồng bộ | Dễ lệch            | Luôn đúng            |
| Auto scale   | Khó                | Dễ triển khai        |

---

### 15.2 Dynamic Y Grid

MEXC / TradingView **không** dùng grid cố định. Mục tiêu: giữ khoảng cách giữa 2 đường grid vào khoảng **50–100 px**.

**Thuật toán chọn gridStep:**

```dart
// 1. rawStep từ số line mong muốn
final targetLines = chartHeight / 80;         // ≈ số đường grid
final rawStep     = priceRange / targetLines;

// 2. Normalize về giá đẹp (1, 2, 5, 10, 20, 50, 100, ...)
double normalizeStep(double raw) {
  final exponent = pow(10, log10(raw).floor()).toDouble();
  final fraction = raw / exponent;
  if (fraction <= 1) return exponent;
  if (fraction <= 2) return 2 * exponent;
  if (fraction <= 5) return 5 * exponent;
  return 10 * exponent;
}
```

**Tính gridLine đầu tiên và render:**

```dart
final gridStep  = normalizeStep(rawStep);
final firstGrid = (visibleMin / gridStep).floor() * gridStep;

double p = firstGrid;
while (p <= visibleMax) {
  drawLine(yOfPrice(p));
  drawLabel(p);
  p += gridStep;
}
```

**Tại sao grid không nhảy:** `firstGrid` dịch chuyển liên tục theo `visibleMin`. Line đầu chỉ biến mất khi vượt hẳn qua `visibleMin`, line mới xuất hiện từ dưới — tạo cảm giác trượt mượt.

---

### 15.3 Anchor Zoom

Mục tiêu: giá tại vị trí ngón tay / con trỏ **không thay đổi** sau khi zoom.

**Thuật toán hoàn chỉnh:**

```dart
void zoomAtPoint(double mouseY, double factor) {
  // 1. Lưu giá tại điểm chạm
  final anchorPrice = visibleMinPrice + (chartHeight - mouseY) / scaleY;

  // 2. Thay đổi scale
  scaleY *= factor;

  // 3. Tính lại visible range sao cho anchorPrice vẫn tại mouseY
  visibleMinPrice = anchorPrice - (chartHeight - mouseY) / scaleY;
  visibleMaxPrice = visibleMinPrice + chartHeight / scaleY;
}
```

**Pinch zoom 2 ngón:** lấy trung điểm làm `mouseY`:

```dart
final anchorY = (finger1Y + finger2Y) / 2;
zoomAtPoint(anchorY, newScale / oldScale);
```

**Ví dụ số:**

|                      | Trước  | Sau (scaleY: 8→12) |
| -------------------- | ------ | ------------------ |
| `visibleMin`         | 100    | 122.91             |
| `visibleMax`         | 200    | 189.58             |
| Giá tại `mouseY=250` | 168.75 | 168.75 ✓           |

---

_Cập nhật: 2026-08-10 — viết lại toàn bộ trục X/Y theo `CHART_AXES.md` (weight-ladder time-tick planner, nice-number price ticks, price axis strip riêng §7), fix label trục thời gian dính mép, fix tick giá không thích ứng gesture zoom Y, fix retry-widen data gap ở example app. Cập nhật section 1 (Unreleased), 2, 6.7, 10.4 (viết lại hoàn toàn), 12, 13.3/13.6, 16._
_Cập nhật: 2026-07-02 — fix 3 bug shouldRepaint/getDate-cache phát hiện qua code review (isLine, isTrendLine/selectY/lines, date-string cache identity), cập nhật section 12 & 10.3._
_Cập nhật: 2026-06-30 — thêm shouldRepaint logic, livePrice real-time pattern, recipe 14.10, pitfalls, section 16 (Y Grid & Anchor Zoom)_
