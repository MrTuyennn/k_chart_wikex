# architecture.md — Đặc tả cross-platform (Flutter → React Native / Android Kotlin / iOS Swift)

> **Mục đích tài liệu này**: đây KHÔNG phải tài liệu API Flutter (xem `chart_jk_arch.md`/`indicator.md` cho việc đó). Đây là đặc tả **trung lập nền tảng** (platform-agnostic) mô tả đúng cấu trúc, sự kiện (event/gesture), và công thức toán học của `k_chart_jk`, đủ chi tiết để một kỹ sư viết lại chart này bằng React Native (Skia/Canvas), Android (Kotlin + Canvas/Compose), hoặc iOS (Swift + Core Graphics/SwiftUI Canvas) và cho ra **hành vi giống hệt** bản Flutter gốc: cùng input data + cùng thao tác người dùng ⇒ cùng số liệu hiển thị, cùng layout, cùng transform.
>
> Nguồn sự thật (ground truth) khi có mâu thuẫn: source code Flutter trong `lib/`. Tài liệu này được trích xuất trực tiếp từ `calc()`/`paint()`/gesture handler thật, không phải từ lý thuyết sách vở.
>
> Quy ước đọc tài liệu: mọi khối `MUST MATCH` đánh dấu hành vi mà nếu port sai thì output sẽ **khác về số/pixel** so với Flutter, kể cả khi trông "hợp lý" hơn bản gốc — bao gồm cả vài chỗ có vẻ như bất đối xứng/quirk trong code gốc mà nếu "sửa cho gọn" khi port sẽ làm hai nền tảng lệch nhau.

---

## Mục lục

1. [Bản đồ thành phần & trách nhiệm](#1-bản-đồ-thành-phần--trách-nhiệm)
2. [Mô hình dữ liệu (data model)](#2-mô-hình-dữ-liệu-data-model)
3. [Hệ toạ độ & phép biến đổi](#3-hệ-toạ-độ--phép-biến-đổi) — xem riêng [§3.4 bảng scaleX vs scaleY](#34-bảng-tổng-hợp--chỗ-nào-áp-scalex-chỗ-nào-áp-scaley) và [§3.5 vùng tương lai cho indicator dịch trục (Ichimoku)](#35-vùng-tương-lai-future-zone--mở-rộng-trục-x-cho-indicator-cần-dịch)
4. [Layout — chia vùng vẽ](#4-layout--chia-vùng-vẽ)
5. [Vòng đời render mỗi frame](#5-vòng-đời-render-mỗi-frame)
6. [Gesture & Event model](#6-gesture--event-model) — xem riêng [§6.5 cơ chế tích luỹ scaleX/scaleY/scrollX (dead-zone khi pinch)](#65-cơ-chế-tích-luỹ-chính-xác-của-scalexscaleyscrollx--vì-sao-pinch-có-dead-zone-nhưng-kéo-tay-thì-không) và [§6.6 kéo/pan khi `scaleY` đã ≠ 1](#66-kéo-di-chuyển-chart-khi-scaley-đã--1-pan-sau-khi-zoom-dọc--️-trọng-tâm-hay-port-thiếu)
7. [Bề mặt API công khai (props / callbacks)](#7-bề-mặt-api-công-khai-props--callbacks)
8. [Định dạng số (number formatting)](#8-định-dạng-số-number-formatting)
9. [Catalogue công thức indicator (20 indicator)](#9-catalogue-công-thức-indicator-20-indicator)
10. [Style / màu sắc — hằng số mặc định](#10-style--màu-sắc--hằng-số-mặc-định)
11. [DepthChart — widget độc lập](#11-depthchart--widget-độc-lập)
12. [Checklist parity khi port](#12-checklist-parity-khi-port)

---

## 1. Bản đồ thành phần & trách nhiệm

Kiến trúc gốc (Flutter) tách làm 3 lớp: **Container** (state + gesture), **Renderer** (thuần vẽ, không giữ state UI), **Indicator** (chiến lược tính toán + vẽ chồng lên renderer). Khi port, giữ đúng 3 lớp này — đừng gộp gesture-state vào trong hàm vẽ.

| Lớp | Flutter | Vai trò trung lập | Gợi ý RN | Gợi ý Android/Kotlin | Gợi ý iOS/Swift |
|---|---|---|---|---|---|
| Container | `KChartWidget` (StatefulWidget + `GestureDetector`) | Sở hữu state gesture: `scaleX, scrollX, scaleY, offsetY, selectX, selectY, isLongPress, isOnTap, isDrag`. Nhận raw pointer event, cập nhật state, yêu cầu vẽ lại. | Component + `react-native-gesture-handler`/Skia `useCanvasRef` | `View`/`@Composable` giữ state qua `remember`/ViewModel, `invalidate()` | `UIView` subclass hoặc SwiftUI `Canvas` + `UIGestureRecognizer`, `setNeedsDisplay()` |
| Renderer | `ChartPainter` (`CustomPainter`) kế thừa `BaseChartPainter` | Hàm thuần: `(data, state) → draw calls`. Không giữ state UI lâu dài (chỉ cache tính toán trong 1 frame). | `onDraw` của Skia Canvas | `Canvas.draw*` trong `onDraw`/Compose `Canvas` | `draw(_ rect:)` trong `CALayer`/`UIView`, hoặc `Canvas` của SwiftUI |
| Sub-renderer | `MainRenderer`, `VolRenderer`, `SecondaryRenderer` | Mỗi sub-renderer sở hữu 1 dải giá trị riêng `(minValue, maxValue)` → hàm map `getY(value)` riêng, vẽ đúng 1 vùng (rect) độc lập. | class/function riêng theo panel | class riêng theo panel | class riêng theo panel |
| Indicator | `IndicatorTemplate` → `MainIndicator`/`SecondaryIndicator` (20 subclass) | Đối tượng chiến lược: `calc(candles)` (điền field vào từng candle), `getMaxMinValue()`, `drawChart()`, `drawFigure()` (label text), `drawVerticalText()` (secondary — label trục Y + optional reference lines). | class/strategy object | class/strategy object | class/strategy/protocol |
| Controller | `KChartController` (`ChangeNotifier`) | Đối tượng điều khiển từ ngoài: `reset()`, `zoomIn()`, `zoomOut()` — phát sự kiện, container tự áp dụng vào state. | hook/store | ViewModel + `LiveData`/`StateFlow` | `ObservableObject` |
| Scale state | `KChartScaleState` (value object) | `{scaleX, scaleY, scrollX}` — plain, immutable, dùng để lưu/khôi phục zoom khi đổi timeframe. | plain object | `data class` | `struct` |
| Depth chart | `DepthChart`/`DepthChartPainter` | Widget **hoàn toàn độc lập** — không share state với chart chính, không phụ thuộc `KChartWidget`. | component riêng | view riêng | view riêng |

**Nguyên tắc quan trọng nhất khi port** (trích từ codebase, áp dụng nguyên văn):

- Toàn bộ main chart được vẽ trong **một bề mặt canvas duy nhất** theo thứ tự lớp cố định (xem §5) — các indicator phụ (secondary) không phải là "widget riêng" chồng lên nhau, mà là các đoạn vẽ tuần tự trong cùng 1 lần `paint()`.
- **Chỉ tính min/max trên vùng dữ liệu ĐANG THỰC SỰ HIỂN THỊ** (`visibleStartIndex..visibleStopIndex` — hẹp, đã clamp về nến thật VÀ trong viewport; xem §3.5 nếu có indicator dùng vùng tương lai), KHÔNG PHẢI dải thô `startIndex..stopIndex` (có thể trỏ ra ngoài mảng data) và càng không phải toàn bộ dataset — nếu không, auto-scale trục Y sẽ sai mỗi lần scroll.
- **`scrollX`/`scaleX` phải là phép biến đổi hệ toạ độ (translate + scale) áp cho toàn bộ canvas vẽ nến**, không phải tính tay từng toạ độ x nhân với scale riêng lẻ — nếu nền tảng đích không có ma trận transform, phải tự áp dụng công thức tương đương `screenX = (dataX + translateX) * scaleX` cho MỌI điểm vẽ trong vùng đó (kể cả bề rộng nét vẽ cần "counter-scale" ngược lại, xem §3.1).
- **`scaleY` chỉ áp cho vùng main chart** (nến + main indicator); panel volume và secondary KHÔNG bao giờ bị scaleY/offsetY — đây là điểm dễ port sai nhất.
- Mọi label/text/line vẽ **ngoài** vùng đã transform (now-price, max/min label, crosshair price label) phải tự áp lại công thức transform tương đương bằng tay (`applyScaleY`, xem §3.2).

---

## 2. Mô hình dữ liệu (data model)

### 2.1 Candle gốc (bắt buộc — input)

| Field | Kiểu | Ghi chú |
|---|---|---|
| `open` | number | |
| `high` | number | |
| `low` | number | |
| `close` | number | |
| `vol` | number | volume (base) |
| `time` | integer (ms) | Unix epoch **millisecond** |
| `amount` | number? | quote volume — optional, cần cho AVL (fallback nếu thiếu) |
| `change` | number? | optional, không dùng trong tính toán indicator |
| `ratio` | number? | optional, không dùng trong tính toán indicator |

### 2.2 Field tính toán gắn thêm vào mỗi candle (output của indicator — nullable cho tới khi "warm up")

Đây là phần **quan trọng nhất để port đúng**: toàn bộ indicator hoạt động theo mô hình **batch recompute trên toàn bộ mảng candle**, không phải streaming/incremental per-tick. Mỗi khi mảng dữ liệu thay đổi (thêm nến mới, load thêm lịch sử, đổi timeframe) phải **chạy lại `calc()` trên toàn bộ mảng từ đầu** — vì nhiều indicator (RSI/EMA/MACD/SuperTrend...) là chuỗi đệ quy phụ thuộc toàn bộ lịch sử từ index 0; chỉ tính lại 1-2 nến cuối sẽ cho kết quả SAI (trôi dần, không khớp bản tính full).

| Nhóm field | Field | Indicator |
|---|---|---|
| Main | `maValueList: number[]` (song song `calcParams`, sentinel `0` khi chưa đủ dữ liệu — **không phải `null`**) | MA |
| Main | `emaValueList: number[]` | EMA |
| Main | `sar: number` (không null từ nến đầu) | SAR |
| Main | `boll: {up, mid, dn, bollMa}` (null cho tới khi đủ chu kỳ) | BOLL |
| Main | `superTrend: {value, isUp}` (`value` null cho tới khi đủ chu kỳ ATR) | SuperTrend |
| Main | `zigzag: number?` | ZigZag |
| Main | `avl: number` (không null từ nến đầu) | AVL |
| Main | `ichimoku: {tenkan, kijun, spanA, spanB}: number?` (mỗi field null riêng cho tới đủ chu kỳ — `spanA` cần CẢ `tenkan` lẫn `kijun` sẵn sàng) | Ichimoku — xem lưu ý dịch trục ở §3.5, không lưu `chikou` (luôn = `close`, dịch ở draw-time) |
| Volume | `MA5Volume`, `MA10Volume: number?` | (không phải indicator riêng — luôn tính kèm volume) |
| Secondary | `dif, dea, macd: number?` | MACD |
| Secondary | `k, d, j: number?` (nến đầu tiên seed cố định `50`) | KDJ |
| Secondary | `rsi: number?` | RSI |
| Secondary | `r: number?` (Williams %R) | WR |
| Secondary | `cci: number?` | CCI |
| Secondary | `obv: number` (không null từ nến đầu), `obvSignal: number?` | OBV |
| Secondary | `trix: number?`, `trixMa: number?` | TRIX |
| Secondary | `mtm: number?`, `mtmMa: number?` | MTM |
| Secondary | `stochRsiK: number?`, `stochRsiD: number?` | StochRSI |
| Secondary | `ar: number?`, `br: number?` | BRAR |
| Secondary | `biasValueList: (number?)[]` (song song `calcParams`, `null` — khác MA, vì BIAS hợp lệ đi qua 0 rất thường xuyên) | BIAS |
| Secondary | `psy: number?`, `psyMa: number?` | PSY |

> Chi tiết công thức từng field: xem §9.

### 2.3 Selection / info-window payload

Khi crosshair/tap/long-press chọn 1 nến, phát ra:

```
InfoWindow { candle, isLeft: boolean }
```

`isLeft` quyết định popup chi tiết vẽ bên trái hay phải màn hình — dựa vào việc điểm được chọn nằm ở nửa trái hay phải màn hình hiện tại (nếu nến được chọn nằm bên trái nửa màn hình, popup vẽ bên phải màn hình để không đè lên nến, và ngược lại — quy tắc chính xác nằm ở `drawCrossLineText`: nếu `screenX(index) < width/2` → popup vẽ bên trái màn hình (`isLeft=false`), ngược lại vẽ bên phải (`isLeft=true`). Đây là quy ước ngược trực giác — kiểm tra kỹ khi port.

### 2.4 DepthEntity (order book — dùng cho DepthChart, §11)

```
DepthEntity { price: number, vol: number }   // vol PHẢI là cumulative volume, không phải vol tại mức giá đó
```

---

## 3. Hệ toạ độ & phép biến đổi

Đây là phần quyết định **pixel có khớp Flutter hay không**. Toàn bộ công thức dưới lấy nguyên văn từ `base_chart_painter.dart`/`chart_painter.dart`/`main_renderer.dart`.

### 3.1 Trục X (ngang) — index nến ↔ toạ độ màn hình

Hằng số:

```
pointWidth = 11.0        // khoảng cách cố định giữa 2 tâm nến (logical px), KHÔNG đổi theo scaleX
dataLen    = itemCount * pointWidth
```

Hàm lõi:

```
getX(i)              = i * pointWidth + pointWidth / 2      // toạ độ TÂM nến i, trong "data space" (chưa scale/translate)
translateX            = scrollX + getMinTranslateX()          // == mTranslateX
xToTranslateX(screenX) = -translateX + screenX / scaleX
indexOfTranslateX(tx)   = binary search trên getX(i) tìm i gần nhất
translateXtoX(tx)       = (tx + translateX) * scaleX           // nghịch đảo — data space → screen space
```

> **⚠️ `chartWidth` trong toàn bộ mục này (và §6.5/§12) nghĩa là `mPlotWidth`, KHÔNG PHẢI bề rộng canvas đầy đủ.** Từ khi có strip trục giá riêng bên phải (§4, §7 CHART_AXES.md), canvas thật rộng `mWidth = mPlotWidth + priceAxisWidth` — nhưng mọi công thức scroll/index/padding dưới đây (và cả điểm neo pinch ở §6.5) vẫn tính theo `mPlotWidth` (phần plot thật sự chứa nến), không tính cả strip giá. Dùng nhầm `mWidth` đầy đủ ở bất kỳ công thức nào bên dưới sẽ làm dải index hiển thị tính lố vào phần bị strip giá che khuất — đúng lớp lỗi đã gặp thực tế (nến/volume/secondary đè lên strip giá trước khi biến mất khi scroll, xem cảnh báo MUST MATCH cuối mục này).

**Padding phải co giãn theo bề rộng màn hình** (để tránh khoảng trống cố định quá lớn trên màn hình hẹp):

```
referenceChartWidth = 375.0   // px tham chiếu

effectiveRightPaddingPx(xFrontPadding, chartWidth):    // chartWidth = mPlotWidth, xem cảnh báo trên
    if chartWidth <= 0: return xFrontPadding
    ratio = chartWidth / referenceChartWidth
    return xFrontPadding * min(ratio, 1.0)
```

Ví dụ với `xFrontPadding = 100`: chartWidth (mPlotWidth) ≥ 375px → giữ nguyên 100px; 250px → ~67px; 187px → ~50px.

**Biên scroll tối đa** (bao nhiêu data-space còn lại phía trái sau khi trừ padding phải):

```
getMinTranslateX():
    paddingData = effectiveRightPaddingPx(xFrontPadding, chartWidth) / scaleX
    x = -dataLen + chartWidth/scaleX - pointWidth/2 - paddingData
    return min(x, 0)          // không bao giờ dương

maxScrollX = abs(getMinTranslateX())   // giá trị này PHẢI lộ ra global/shared state — dùng để quyết định
                                          // có nên bắn onLoadMore hay không (xem §6)
```

**Vùng hiển thị** (chỉ số nến đầu/cuối đang thấy trên màn hình):

```
startIndex = indexOfTranslateX(xToTranslateX(0))
stopIndex  = indexOfTranslateX(xToTranslateX(chartWidth))   // chartWidth = mPlotWidth
```

`startIndex`/`stopIndex` ở đây là dải THÔ — có thể trỏ ra ngoài `[0, itemCount-1]` khi có indicator dùng vùng tương lai (Ichimoku, xem §3.5). Renderer thật tách tiếp thành 2 dải hẹp/rộng hơn từ đây — **không dùng thẳng `startIndex`/`stopIndex` để vẽ hay tính auto-scale**, xem bảng "3 phạm vi index" ở §3.5.

**MUST MATCH — cách áp transform khi vẽ nến**: toàn bộ vùng vẽ nến (main + volume + secondary, theo trục X) được áp **một phép biến đổi affine duy nhất** trước khi vẽ từng nến ở toạ độ `getX(i)` (data space):

```
canvas.clipRect(0, 0, mPlotWidth, dateRect.top)   // BẮT BUỘC, áp TRƯỚC translate/scale bên dưới (screen space,
                                                    // không co giãn theo scaleX) — chặn nến/volume/secondary/
                                                    // crosshair/trend-line vẽ TRÀN vào strip trục giá. Thiếu clip
                                                    // này: nến ở gần mép phải vẫn được vẽ đủ (vòng lặp chỉ loại
                                                    // theo INDEX, không theo pixel) tới khi index bị loại hẳn khỏi
                                                    // dải hiển thị — thấy rõ nhất khi zoom vào (candleWidth lớn,
                                                    // thân nến cuối thừa hẳn ra ngoài mPlotWidth, đè lên label giá,
                                                    // trước khi "biến mất"). Bug thật đã gặp, xem CHANGELOG 08-12.
canvas.translate(translateX * scaleX, 0)
canvas.scale(scaleX, 1.0)
// sau đó vẽ nến tại (getX(i), giá) — KHÔNG tự nhân scaleX vào từng x thủ công
```

Nếu nền tảng đích không có ma trận transform composable (hiếm, nhưng ví dụ Canvas API cấp thấp), công thức tương đương cho từng điểm là:

```
screenX = (dataX + translateX) * scaleX
```

**Counter-scale cho các phần tử cần giữ kích thước cố định trên màn hình** (chấm crosshair, oval trend-line, độ dày nét line-chart) — vì cả vùng đã bị `scale(scaleX, 1.0)`, các phần tử muốn giữ nguyên kích thước px bất kể zoom phải chia ngược cho `scaleX`:

```
// đường kính chấm crosshair / trend-line oval
if scaleX >= 1: width_screen = 4.0 / scaleX,  height_screen = 4.0 * scaleX   // (ellipse méo theo hướng zoom)
else:           width_screen = 4.0,           height_screen = 4.0 / scaleX

// độ dày nét line-chart (isLine mode)
strokeWidth = clamp(1.0 / scaleX, 0.1, 1.0)
```

### 3.2 Trục Y (dọc) — main chart

**Map tuyến tính cơ bản** (không đổi theo zoom dọc — dùng chung mọi sub-renderer):

```
scaleY_local = rectHeight / (maxValue - minValue)     // nếu maxValue==minValue: maxValue*=1.5; minValue/=2 (guard)
getY(v) = (maxValue - v) * scaleY_local + rectTop
```

`MainRenderer` có thêm padding trong 5px trên/dưới bên trong `mMainRect` trước khi áp công thức trên (content rect = mainRect co lại 5px mỗi cạnh trên/dưới).

**MUST MATCH — zoom/pan dọc CHỈ áp cho vùng main chart, qua canvas transform, KHÔNG bake vào `getY`:**

```
centerY = (mMainRect.top + mMainRect.bottom) / 2
canvas.clipRect(mMainRect band, mở rộng theo X)   // giới hạn vùng ảnh hưởng scaleY
canvas.translate(0, centerY * (1 - scaleY) + offsetY)
canvas.scale(1.0, scaleY)
// → chỉ MainRenderer.drawChart() (nến + main indicators) chạy TRONG block transform này
// VolRenderer và SecondaryRenderer.drawChart() chạy NGOÀI block này — không bao giờ bị scaleY/offsetY
```

Với mọi label/line vẽ **ngoài** block transform ở trên (now-price line + badge, max/min label, giá trên crosshair), phải tự áp lại transform tương đương bằng tay:

```
applyScaleY(rawY):
    centerY = (mMainRect.top + mMainRect.bottom) / 2
    return clamp(centerY + (rawY - centerY) * scaleY + offsetY, mMainRect.top, mMainRect.bottom)
```

**Ràng buộc `scaleY`/`offsetY`:**

```
scaleY  ∈ [0.3, 5.0]
maxOffsetY = mainChartBaseHeight * scaleY / 2
offsetY = clamp(offsetY, -maxOffsetY, maxOffsetY)
```

Ý nghĩa: tại `|offsetY| = maxOffsetY`, đúng một nửa chiều cao nội dung bị đẩy ra khỏi khung nhìn — không bao giờ cho phép pan quá mức đó (phần vượt phải "trả lại" cho outer scroll, xem §6.6/§6.7).

**Vol panel — map Y KHÁC công thức chuẩn** (giả định giá trị luôn ≥ 0, cột volume neo đáy panel):

```
getY(v) = (maxValue - v) * (chartRect.height / maxValue) + chartRect.top
```

Lưu ý mẫu số dùng `maxValue` (không phải `maxValue - minValue` như công thức chuẩn) — cố tình bỏ qua `minValue`.

**Secondary panel** — dùng đúng công thức chuẩn `(maxValue - minValue)` như §3.2 phần đầu (KDJ, RSI, MACD, v.v. đều dùng chung).

### 3.3 Grid dọc/label trục X — weight-ladder, KHÔNG chia cột đều

> **Thay thế hoàn toàn cơ chế `gridColumns` cũ** (chia N cột đều theo pixel, N suy từ khoảng cách data) — đã bị bỏ hẳn (field tương ứng giờ là dead code, đã xoá). Mục này tóm tắt lại đủ để port đúng; công thức đầy đủ (pseudocode + test case + edge case) nằm ở `CHART_AXES.md` §5, đọc trực tiếp file đó nếu cần chính xác 100%.

Vị trí lưới dọc và nhãn trục X (giờ/ngày/tháng...) **không** còn suy từ số cột chia đều pixel. Thay vào đó:

1. **Mỗi nến được gán 1 `tickWeight`** (số nguyên, tính 1 LẦN lúc load, cache lại — không tính lại mỗi frame) dựa trên việc nến đó có rơi đúng ranh giới lịch (theo **local time** của thiết bị) hay không — 12 bậc, từ thấp lên cao: nến thường (`MINOR`) → đầu phút thứ N (`1/5/15/30`) → đầu giờ thứ N (`1/3/6/12`) → đầu ngày (`DAY`) → đầu tháng (`MONTH`) → đầu năm (`YEAR`). Nến càng "tròn lịch" (đầu năm > đầu tháng > đầu ngày > ...) thì `tickWeight` càng cao.
2. **Mỗi frame, chọn 1 THRESHOLD-bậc từ hình học thuần** — dựa trên `barSpacing` (px giữa 2 tâm nến hiện tại = `pointWidth * scaleX`) và `intervalMs` (độ dài 1 nến), **KHÔNG đếm số nến đang hiển thị** (tránh nhấp nháy khi barSpacing thay đổi liên tục lúc pinch):
   ```
   MIN_GAP_X = 64.0        // khoảng cách tối thiểu (px) giữa 2 tick liền kề, không bao giờ chồng nhãn
   SURPLUS   = 4.0         // biên an toàn — threshold chọn "dư" một chút để invariant I4 (xem dưới) luôn đúng
   requiredGapMs = MIN_GAP_X * intervalMs / (barSpacing * SURPLUS)
   threshold = bậc THẤP NHẤT trong 12 bậc mà khoảng cách lịch của nó (vd 1 tháng ≈ 30 ngày × 86400000ms) >= requiredGapMs
   ```
3. **Lọc + đóng gói ứng viên** (mọi nến có `tickWeight >= threshold`) theo `MIN_GAP_X` trên **absolute space** (toạ độ `getX(i)` trong data space, KHÔNG trừ `scrollOffset`) — đây là invariant **I4: pan (thay `scrollX`, giữ nguyên `scaleX`) KHÔNG được đổi tick nào được chọn**, chỉ đổi tick nào đang lọt vào viewport. Nếu tính theo screen-space (đã trừ scroll) thì tick sẽ "nhảy" nhẹ mỗi khi pan — sai.
4. **Lọc lại lần cuối theo pixel thật** `x ∈ [0, mPlotWidth]` (không phải `[0, mWidth]` — xem cảnh báo `chartWidth` ở §3.1) — chỉ tick còn lọt trong dải này mới thực sự vẽ.
5. Nếu bước 2-4 không cho ra tick nào (data quá thưa, hoặc mọi tick candidate đều bị lọc hết) — luôn có **fallback "never blank" (T1)**: lấy nến ở giữa viewport làm tick duy nhất, không bao giờ để trục trắng hoàn toàn.

Kết quả (`List<TimeTick> {index, x, label}`) được **cache tĩnh** theo key `(barSpacing làm tròn px, identity dataset, intervalMs, format)` — chỉ tính lại khi zoom/data/format đổi, KHÔNG tính lại mỗi frame lúc pan (pan chỉ đổi `translateX`, không đổi tick nào được chọn, nhờ invariant I4).

**Format nhãn** (chữ hiển thị trên mỗi tick) — 2 chế độ:
- **Adaptive** (mặc định): chữ đổi theo chính `tickWeight` của tick đó — `YEAR→"2026"`, `MONTH→"Aug"`, `DAY→"10"`, còn lại→`"09:05"` (giờ:phút). Escalate dần theo mức "tròn lịch".
- **Forced** (khi container truyền `timeFormat`/`chartStyle.dateTimeFormat`): MỌI tick dùng CHUNG 1 format cố định, bỏ qua `tickWeight` hoàn toàn.

`gridRows` (lưới ngang) vẫn cố định `4` (không phụ thuộc data) — không đổi so với trước.

### 3.4 Bảng tổng hợp — chỗ nào áp `scaleX`, chỗ nào áp `scaleY`

Đây là phần **hay port sai nhất**, vì `scaleX` và `scaleY` không đối xứng: `scaleX` ảnh hưởng gần như mọi thứ (kể cả panel volume/secondary), còn `scaleY` **chỉ** ảnh hưởng đúng 1 vùng (main chart). Ba cơ chế áp dụng khác nhau, không được nhầm lẫn khi port:

- **(a) Canvas transform** — `scaleX`/`scaleY` nằm trong ma trận biến đổi của canvas tại thời điểm vẽ; mọi toạ độ vẽ bên trong scope này tự động bị kéo giãn, không cần tính tay.
- **(b) Tính tay (manual math)** — phần tử được vẽ ở **ngoài** mọi canvas transform (raw screen space), nhưng code tự áp công thức tương đương (`translateXtoX`, `_applyScaleY`, hoặc reverse-transform cho label trục) để vị trí vẫn đúng theo `scaleX`/`scaleY` hiện tại.
- **(c) Screen space thuần** — không bị `scaleX` lẫn `scaleY` ảnh hưởng, dù bằng cách nào.

**Ngữ cảnh save/restore quyết định ai bị `scaleY` ảnh hưởng** — xem khối lồng nhau trong `drawChart()` (đã nêu ở §5, nhắc lại đúng phần liên quan):

```
canvas.save()                                    // ── mở scope A: scaleX + translateX ──
  canvas.translate(translateX*scaleX, 0); canvas.scale(scaleX, 1)

  canvas.save()                                  // ── mở scope B (LỒNG trong A): + scaleY + offsetY ──
    canvas.translate(0, centerY*(1-scaleY)+offsetY); canvas.scale(1, scaleY)
    → MainRenderer.drawChart()                   // candle + main indicator: nằm trong CẢ A và B
  canvas.restore()                                // ── đóng scope B: từ đây scaleY KHÔNG còn active ──

  → VolRenderer.drawChart()                       // chỉ còn trong A (scaleX) — KHÔNG có scaleY
  → SecondaryRenderer.drawChart()                 // chỉ còn trong A (scaleX) — KHÔNG có scaleY
  → drawCrossLine()                               // chỉ còn trong A (scaleX) — KHÔNG có scaleY ⚠️
  → drawTrendLines()                              // chỉ còn trong A (scaleX) — KHÔNG có scaleY ⚠️
canvas.restore()                                  // ── đóng scope A ──

→ drawVerticalText() / drawDate() / drawText() / drawMaxAndMin() / drawNowPrice() / drawCrossLineText()
  // TẤT CẢ chạy SAU khi scope A đã đóng → hoàn toàn screen space, KHÔNG canvas transform nào cả
  // (những cái cần đúng theo zoom phải tự tính tay — xem cột "Cơ chế" trong bảng dưới)
```

Bảng đầy đủ theo từng vùng/phần tử vẽ:

| Vùng / phần tử vẽ | `scaleX`? | `scaleY`? | Cơ chế |
|---|---|---|---|
| Thân nến + bấc nến (candle body/wick) | ✅ | ✅ | (a) canvas transform — trong scope B |
| Line chart (`isLine` mode) | ✅ | ✅ | (a) canvas transform — trong scope B; riêng **độ dày nét** counter-scale ngược `1/scaleX` để không bị dày/mỏng theo zoom ngang |
| Main indicator: MA/EMA/BOLL/SAR/ZigZag/SuperTrend/AVL | ✅ | ✅ | (a) canvas transform — vẽ bên trong `MainRenderer.drawChart`, cùng scope B |
| Cột volume + đường MA5/MA10 volume | ✅ | ❌ | (a) chỉ scope A — đã ra khỏi scope B trước khi vẽ |
| Secondary indicator: MACD/KDJ/RSI/WR/CCI/OBV/TRIX/MTM/StochRSI/BRAR/BIAS/PSY | ✅ | ❌ | (a) chỉ scope A |
| Đường tham chiếu ngang nét đứt (vd 20/80 của StochRSI) | ❌ | ❌ | (c) vẽ TRƯỚC cả scope A — screen space thuần, không giãn theo zoom nào |
| Grid (lưới ngang/dọc mọi panel) | ❌ | ❌ | (c) vẽ ngoài mọi transform |
| **⚠️ Crosshair — 2 đường dashed + chấm tròn** (`drawCrossLine`) | ✅, span ngang clip cứng ở `x=plotWidth` (KHÔNG tràn vào priceAxisRect — xem §3.1/§4) | ❌ *(dùng Y thô, KHÔNG đúng theo zoom)* | (a) chỉ scope A — xem cảnh báo dưới |
| **⚠️ Crosshair — badge giá + badge ngày** (`drawCrossLineText`) | (b) vị trí X tính tay qua `translateXtoX`, điều kiện trái/phải + clamp 2 mép dùng `plotWidth` (KHÔNG PHẢI `width`, đúng theo `scaleX`) | ❌ *(dùng Y thô)* | (b)/(c) hỗn hợp — xem cảnh báo dưới |
| **⚠️ Trend-line** (đoạn thẳng xu hướng do user vẽ tay) | ✅, clip cứng `x=plotWidth` cùng crosshair | ❌ *(dùng scale/max/contentTop CHỤP LẠI từ lần `getY()` gần nhất — tức Y thô)* | (a) chỉ scope A — xem cảnh báo dưới |
| Label trục Y (giá) — main/vol/secondary (`drawVerticalText`) | ❌ | ✅ **đúng theo zoom** | (b) reverse-transform tính tay qua `scaleY`/`offsetY`/`centerY` để suy ra đúng giá trị nhãn ứng với mỗi dòng lưới; vẽ vào `priceAxisRect` (§4) |
| Label trục X (ngày/giờ, `drawDate`) | (b) vị trí cột tính tay qua `xToTranslateX`/`indexOfTranslateX` (đúng theo `scaleX`); clip cứng vào `[0, plotWidth] × dateRect` | ❌ | (b) |
| Label indicator góc trên (`drawText`) | ❌ | ❌ | (c) vị trí cố định mỗi frame, không phụ thuộc zoom nào |
| Label max/min giá (`drawMaxAndMin`) | (b) qua `translateXtoX`, so với `plotWidth/2` để quyết định trái/phải — **đúng theo zoom** | (b) qua `_applyScaleY` — **đúng theo zoom** | (b) |
| Now-price (đường kẻ + badge giá hiện tại, `drawNowPrice`) | (b) — `offsetX` (khi `VerticalTextAlignment.right`, mặc định) tính từ `plotWidth` (KHÔNG PHẢI `width`) — badge dừng đúng mép strip giá, không tràn vào | (b) qua `_applyScaleY` — **đúng theo zoom** | (b) |

> **⚠️ MUST MATCH — Crosshair và Trend-line KHÔNG theo `scaleY`/`offsetY`, dù bản thân nến/main-indicator CÓ bị zoom dọc.** Đây là hệ quả trực tiếp của việc `drawCrossLine`/`drawCrossLineText`/`drawTrendLines` gọi `getMainY(...)`/`getY(...)` — hàm map Y **cơ bản** (`(maxValue - v) * scaleY_nộibộ + rectTop`, không liên quan gì tới tham số zoom `scaleY`/`offsetY` của widget) — mà KHÔNG bọc qua `_applyScaleY` như `drawNowPrice`/`drawMaxAndMin` đã làm đúng. Hệ quả quan sát được: nếu user pinch/kéo để zoom dọc main chart (`scaleY != 1` hoặc `offsetY != 0`) rồi long-press để bật crosshair, đường kẻ ngang + chấm + badge giá của crosshair sẽ **lệch khỏi vị trí thực của nến trên màn hình** (hiển thị như thể `scaleY=1, offsetY=0`), trong khi bản thân nến/MA/BOLL/SAR... vẫn hiển thị đúng vị trí đã zoom. Tương tự cho các đoạn trend-line lịch sử (dùng lại `trendLineMax/trendLineScale/trendLineContentRec` — 3 biến toàn cục được `MainRenderer.getY()` "chụp" lại mỗi lần gọi, cũng là giá trị **chưa** áp zoom).
>
> Khi port, có 2 lựa chọn — **phải chọn có chủ đích, không để lệch ngẫu nhiên**:
> 1. **Giữ nguyên hành vi này** (khuyến nghị nếu mục tiêu là parity 100% với bản Flutter hiện tại) — implement `drawCrossLine`/`drawCrossLineText`/`drawTrendLines` dùng đúng hàm Y cơ bản (không `_applyScaleY`), để 2 nền tảng lệch giống nhau khi zoom dọc + bật crosshair.
> 2. **Chủ động sửa** (nếu port muốn "đúng" hơn bản gốc) — bọc `_applyScaleY` cho cả 3 hàm này giống `drawNowPrice`. Nếu chọn hướng này, **phải note lại là đã cố ý lệch so với Flutter gốc** để tránh nhầm là "port sai".

### 3.5 Vùng tương lai (future zone) — mở rộng trục X cho indicator cần dịch

Thêm khi implement **Ichimoku** (§9.1) — indicator ĐẦU TIÊN cần vẽ ra ngoài phạm vi index `0..n-1` của mảng nến (Senkou Span A/B dịch **tới trước** `shift` nến, Chikou dịch **lùi** `shift` nến). Cơ chế này là phần mở rộng **dùng chung cho mọi main indicator**, không phải hardcode riêng cho Ichimoku — bất kỳ indicator tương lai nào cần dịch trục chỉ cần khai báo `futureShift`.

**Nguyên tắc cốt lõi — dịch bằng pixel-offset ở draw-time, KHÔNG lưu mảng đã dịch sẵn:**

```
getX(i) = i * pointWidth + pointWidth/2          // công thức thuần, tuyến tính theo i
getX(i) + shift*pointWidth == getX(i + shift)    // → dịch = cộng thẳng shift*pointWidth vào toạ độ X đã tính
```

Nhờ tính tuyến tính này, **giá trị Span A/B/Chikou chỉ cần tính & lưu tại index TỰ NHIÊN (không dịch) của nến, giống mọi indicator khác** (`ichimoku: {tenkan, kijun, spanA, spanB}` — không có field `chikou` riêng, vì nó luôn `= close`). Việc "dịch tới trước/lùi sau" chỉ là phép cộng/trừ `shift * pointWidth` vào toạ độ X **ngay tại draw-time**, bên trong hàm vẽ của riêng indicator đó:
- Tenkan/Kijun: vẽ tại `(lastX, curX)` — không dịch.
- Senkou Span A/B: vẽ tại `(lastX + shiftPx, curX + shiftPx)`.
- Chikou: vẽ tại `(lastX - shiftPx, curX - shiftPx)`, dùng thẳng `close` — không cần warm-up riêng (tự bị cắt cụt ở 2 đầu vì không có nến ngoài `0..n-1` để cấp dữ liệu).

Cách này **khác** với việc lưu sẵn mảng đã dịch kiểu `spanA[n+shift]` — không cần kéo dài mảng `KLineEntity`/field, không cần đổi kiểu dữ liệu entity. Phần thực sự phải đụng tới renderer dùng chung chỉ có 2 việc: (a) chừa đủ chỗ trên trục X/scroll để phần dịch-phải không bị cắt cụt, (b) đảm bảo binary-search/index không bao giờ dò ra ngoài mảng dữ liệu thật khi tính min/max hay vẽ.

**Cơ chế khai báo — mỗi `MainIndicator` tự báo cần bao nhiêu slot tương lai:**

```
MainIndicator.futureShift: int   // mặc định 0 — indicator không cần dịch trục thì không phải làm gì thêm
IchimokuIndicator.futureShift = shift = calcParams[1]   // = kijun period, KHÔNG hardcode 26 (đổi param → shift đổi theo)

mFutureSlots = max(futureShift trên toàn bộ mainIndicators đang bật)   // 0 nếu không indicator nào cần dịch
mDataLen     = (itemCount + mFutureSlots) * pointWidth                 // thay vì chỉ itemCount * pointWidth
```

`mDataLen` lớn hơn kéo theo `maxScrollX`/biên scroll (§3.1) tự động mở rộng — user pan/zoom được tới hết vùng tương lai, không cần logic riêng. Biên trên của binary-search index (`indexOfTranslateX`, §3.1) cũng đổi từ `itemCount-1` thành `itemCount + mFutureSlots - 1` để viewport có thể trỏ vào vùng tương lai.

> **⚠️ MUST MATCH — bẫy dễ port sai nhất: 3 loại "phạm vi index" KHÔNG được dùng lẫn cho nhau.** Khi `mFutureSlots > 0`, chỉ số nến đầu/cuối của viewport (`startIndex`/`stopIndex`, xem §3.1) có thể trỏ ra ngoài mảng dữ liệu thật (`> itemCount-1`). Từ đó nảy sinh **3 phạm vi khác nhau**, dùng sai chỗ nào cũng ra bug (đã xảy ra trong bản Flutter gốc lúc mới thêm Ichimoku, phải fix lại):
>
> 1. **Viewport thô** (`startIndex..stopIndex`) — có thể vượt `itemCount-1`, KHÔNG được dùng để index thẳng vào mảng nến (crash/RangeError).
> 2. **Vùng hiển thị thật** (`visibleStartIndex..visibleStopIndex` = giao giữa viewport thô và `0..itemCount-1`) — PHẢI dùng cho: high/low của nến để định vị label max/min trên chart, autoscale trục Y của main/volume/secondary panel, và nến dùng để hiển thị label chỉ số ở góc trên (kiểu "candle bên phải đang xem"). Dùng nhầm phạm vi RỘNG HƠN ở đây khiến các label/autoscale này bị ảnh hưởng bởi nến **không hề hiển thị trên màn hình** — ví dụ label giá cao/thấp nhất bị đặt sai vị trí (thậm chí lệch ra ngoài canvas, vô hình), hoặc trục Y bị co giãn theo 1 nến off-screen.
> 3. **Vùng "real" mở rộng** (`realStartIndex..realStopIndex` = vùng hiển thị thật, nới rộng thêm `mFutureSlots` MỖI PHÍA) — CHỈ dùng cho: (a) vòng lặp vẽ của main renderer (cần đủ nến nguồn thật để đường bị dịch có gì để vẽ vào vùng đang hiển thị — Span A/B cần nến ở BÊN TRÁI viewport, Chikou cần nến ở BÊN PHẢI viewport), (b) tính đóng góp vào Y-range của riêng các indicator có `futureShift > 0` (không đụng tới high/low nến/volume/secondary — những thứ đó không bị dịch nên nến ngoài viewport không liên quan tới chúng). Vòng lặp vẽ của **volume/secondary renderer thì KHÔNG cần** vùng mở rộng này (chúng không có khái niệm dịch trục) — dùng nhầm vùng "real" ở đây chỉ tốn thêm draw call vô ích cho nến ngoài màn hình (bị clip nên không sai về hình ảnh, nhưng lãng phí, tăng theo `2 × mFutureSlots` mỗi frame).

**Ngoại suy timestamp cho label trục X trong vùng tương lai** (không có nến thật → không có timestamp thật):

```
timeAt(index):
    if index < itemCount: return candle[index].time
    interval = candle[itemCount-1].time - candle[itemCount-2].time   // khoảng cách 2 nến thật cuối cùng
    return candle[itemCount-1].time + (index - itemCount + 1) * interval
```

Ngoại suy tuyến tính đơn giản — đúng cho thị trường 24/7 (crypto). Với thị trường có lịch phiên (chứng khoán: giờ nghỉ, cuối tuần), phải ngoại suy theo lịch phiên thay vì cộng thẳng `interval`, và cẩn thận nếu 2 nến thật cuối cùng vô tình cách nhau bất thường (gap cuối tuần trên chart daily) — `interval` tính từ đúng cặp đó sẽ kéo theo mọi label tương lai bị sai khoảng cách.

**Crosshair/tap-selection**: cố ý clamp vào **vùng hiển thị thật** (không phải vùng "real" mở rộng, càng không phải vùng tương lai trống) — user không chọn được vào 1 nến đang không hiển thị trên màn hình, dù về mặt kỹ thuật index đó có tồn tại trong mảng dữ liệu. Đây là lựa chọn phạm vi có chủ đích (đơn giản hoá — spec lý thuyết đầy đủ hơn có thể cho chọn vào vùng tương lai và hiện "giá để trống, timestamp vẫn hiện", nhưng bản port hiện tại không làm phần này).

---

## 4. Layout — chia vùng vẽ

**Chia đôi theo chiều NGANG trước tiên** (CHART_AXES.md §7) — canvas thật (`width`) tách thành khối **plot** bên trái (nến/volume/secondary/lưới/trục thời gian) và **strip trục giá** riêng bên phải (label giá của MỌI panel, không panel nào vẽ đè label giá lên nội dung của mình nữa như bản cũ):

```
plotWidth      = max(1.0, width - priceAxisWidth)
priceAxisWidth = xem công thức riêng bên dưới — TRỄ ĐÚNG 1 FRAME so với label thật (xem cảnh báo)
```

Rồi mới xếp DỌC từ trên xuống **bên trong khối plot** (mọi rect trong khối này rộng `plotWidth`, KHÔNG PHẢI full `width` — khác bản trước khi có strip giá riêng):

```
┌───────────────────────────────────────┬──────────────┐
│ topPadding = chartStyle.topPadding(20)  │              │
│            + 12 × (số main indicator)   │              │  ← mỗi main indicator có 1 dòng label cao 12px
├───────────────────────────────────────┤  priceAxisRect │
│              mainRect                    │  (label giá  │  candles + main indicators
├───────────────────────────────────────┤   MỌI panel,   │  (padding 10px cố định nếu vol hiện)
│  volRect  (nếu volHidden=false)         │   cao = từ    │  cao = secondaryPanelHeight (mặc định = baseHeight×0.2)
├───────────────────────────────────────┤  mainRect.top  │
│  secondaryRect[0]                        │   → dateTop) │  cao = secondaryPanelHeight, mỗi panel + childPadding(12) trên
│  secondaryRect[1]                        │              │
│  ...                                     │              │
├───────────────────────────────────────┼──────────────┤
│  dateRect  (cao = bottomPadding = 16)   │  cornerRect   │  trục thời gian; cornerRect = ô chết, chỉ tô nền
└───────────────────────────────────────┴──────────────┘
                width = plotWidth                 priceAxisWidth
```

Công thức chiều cao chính xác:

```
labelHeight        = 12          // 1 dòng label / main indicator
totalLabelHeight   = 12 * mainIndicators.count
secondaryPanelH    = secondaryHeightParam  ?? (baseHeight * 0.2)   // baseHeight = tham số chiều cao main do caller truyền
volumeHeight       = volHidden ? 0 : secondaryPanelH               // LƯU Ý: vol dùng CHUNG chiều cao với 1 panel secondary
totalSecondaryH    = secondaryPanelH * secondaryIndicators.count
totalDisplayHeight = baseHeight + volumeHeight + totalSecondaryH + totalLabelHeight

topPadding  = 20 + totalLabelHeight
mainHeight  = totalDisplayHeight - volumeHeight - totalSecondaryH - (volHidden ? 0 : 10)   // trừ thêm 10px cố định nếu có vol
mainRect    = rect(0, topPadding, plotWidth, topPadding + mainHeight)                       // rộng plotWidth, KHÔNG full width

volRect (nếu hiện) = rect(0, mainRect.bottom + 12 + 10, plotWidth, mainRect.bottom + 10 + volumeHeight)
                     // 12 = childPadding, 10 = hằng số cố định mPaddingMainChild (KHÔNG lấy từ style, luôn = 10)

secondaryTop = (volRect ?? mainRect).bottom
secondaryRect[i] = rect(0, secondaryTop + i*secondaryPanelH + 12, plotWidth, secondaryTop + i*secondaryPanelH + secondaryPanelH)

dateTop  = (secondaryRect.last ?? volRect ?? mainRect).bottom
dateRect = rect(0, dateTop, plotWidth, dateTop + 16)             // rộng plotWidth

priceAxisRect = rect(plotWidth, mainRect.top, width, dateTop)    // cột phải, cao = main+vol+secondary (KHÔNG gồm dateRect)
cornerRect    = rect(plotWidth, dateTop, width, dateTop + 16)    // ô chết góc dưới-phải — giao strip giá × trục thời gian
```

**Bề rộng strip trục giá** (`priceAxisWidth`) — tự đo theo label rộng nhất đang hiển thị, clamp + làm tròn bội 8 + **hysteresis**:

```
raw      = clamp(maxLabelWidth + 14, 48, 96)
required = ceil(raw / 8) * 8
if required > priceAxisWidth OR required <= priceAxisWidth - 8:
    priceAxisWidth = required
// nếu không rơi vào 1 trong 2 điều kiện trên (đang trong "vùng chết" giữa
// hiện tại và hiện tại-8), GIỮ NGUYÊN — đây chính là hysteresis: PHÌNH áp
// ngay lập tức (label bị cắt còn tệ hơn 1 frame rộng dư), THU chỉ áp khi
// thấp hơn hẳn 1 bậc 8px trọn vẹn — chống vòng lặp phản hồi width→plotWidth
// →dải index hiển thị→range giá→label→width lặp vô hạn (nếu không có
// hysteresis, 1 label dao động đúng ranh giới clamp có thể khiến width nảy
// qua lại mỗi frame).
```

> **⚠️ `priceAxisWidth` tính TRỄ ĐÚNG 1 FRAME** — `updatePriceAxisWidth(maxLabelWidth)` chạy SAU khi đã layout+đo label ở frame hiện tại, nhưng kết quả chỉ áp dụng từ frame KẾ TIẾP (frame hiện tại vẫn dùng giá trị `priceAxisWidth` cũ đã có sẵn từ trước khi tính `mPlotWidth`). Đây là lựa chọn có chủ đích để cắt đứt vòng lặp phản hồi ở trên mà không cần biết trước label rộng bao nhiêu — port cần giữ đúng độ trễ 1 frame này (không được "sửa" thành đồng bộ trong cùng 1 frame, sẽ có nguy cơ dao động vô hạn nếu 1 giá trị label dao động đúng ranh giới bậc 8px).
>
> Seed mặc định lúc chưa có frame nào chạy: `priceAxisWidth = 64.0`.

**MUST MATCH — clip ngang khối plot vào đúng `plotWidth`**: mọi nội dung vẽ trong khối plot (nến, volume, secondary, crosshair, trend-line — xem §3.1 "MUST MATCH") phải bị chặn cứng ở `x = plotWidth`, không được tràn sang `priceAxisRect`. Vòng lặp vẽ chỉ loại nến theo INDEX (`stopIndex`, §3.1) — nến ở gần biên vẫn được vẽ ĐỦ THÂN dù thân đó vượt qua `plotWidth` (rõ nhất khi zoom vào, `candleWidth` lớn) nếu không có clip cứng theo pixel đi kèm.

Hằng số mặc định (đều override được qua style object phía container, trừ `mPaddingMainChild = 10` — hardcode, không expose):

| Hằng số | Giá trị mặc định |
|---|---|
| `topPadding` | 20.0 |
| `bottomPadding` | 16.0 |
| `childPadding` | 12.0 |
| `pointWidth` | 11.0 |
| `candleWidth` | 8.5 |
| `candleLineWidth` (bấc nến) | 1.0 |
| `volWidth` | 8.5 |
| `gridRows` | 4 (cố định) |
| `gridColumns` | **đã bỏ** — vị trí lưới dọc giờ theo weight-ladder, xem §3.3 |
| `priceAxisWidth` | tự đo + hysteresis, xem công thức trên (seed `64.0`) |

### Vẽ nến (candlestick body/wick)

```
r     = candleWidth / 2
lineR = candleLineWidth / 2
if open >= close:   // nến giảm theo quy ước "open>=close = up color" — xem lưu ý dưới
    if (open - close) < candleLineWidth: open = close + candleLineWidth   // đảm bảo thân nến luôn dày tối thiểu = bấc
    color = upColor
    body = rect(x-r, y(close), x+r, y(open))
elif close > open:
    if (close - open) < candleLineWidth: open = close - candleLineWidth
    color = dnColor
    body = rect(x-r, y(open), x+r, y(close))
wick = rect(x-lineR, y(high), x+lineR, y(low))   // luôn vẽ, cùng màu với thân
```

> **Lưu ý ngược trực giác**: điều kiện đầu tiên là `open >= close` → `upColor` (không phải "close > open"). Với dữ liệu bình thường open==close hiếm khi xảy ra chính xác nên ảnh hưởng không đáng kể, nhưng khi port phải giữ đúng thứ tự so sánh này để nến doji (open==close) tô đúng màu `upColor` (nhánh đầu tiên trong `if/elif`).

### Line chart mode (`isLine = true`)

Vẽ 1 đường cong mượt nối `close[i-1]→close[i]` bằng cubic bezier với 2 control point đều nằm tại `x = (lastX+curX)/2` (một điểm control point ở y của giá trước, một ở y của giá sau) — tạo hiệu ứng "S-curve" mượt giữa 2 điểm. Vùng dưới đường được tô gradient (đậm ở trên, trong suốt ở dưới) từ đúng 2 màu cấu hình.

---

## 5. Vòng đời render mỗi frame

Pseudocode `paint()` đầy đủ, đúng thứ tự (thứ tự vẽ ảnh hưởng layer/z-order — không tự ý đổi):

```
paint(canvas, size):
    if size.width <= 0 or size.height <= 0: return   // layout pass đầu/animation collapse có thể giao size 0 — bỏ qua hẳn frame
    clipRect(0,0,width,height)                        // clip TOÀN canvas — KHÔNG loại trừ priceAxisRect, chỉ chặn tràn ra ngoài widget
    initRect(size)                     // §4 — tính lại mọi rect (plotWidth, mainRect, priceAxisRect... đổi mỗi frame vì size có thể đổi)
    calculateValue()                   // tính lại maxScrollX, translateX, startIndex/stopIndex (rồi tách visible/real, §3.5),
                                        // min/max mỗi panel, VÀ danh sách tick trục thời gian (mTimeTicks, §3.3)
    initChartRenderer()                // tạo MainRenderer/VolRenderer/SecondaryRenderer mới, đọc min/max vừa tính;
                                        // MainRenderer cũng tự tính lại priceTicks (nice-number, §3.2) + gọi
                                        // updatePriceAxisWidth() cho frame KẾ TIẾP (§4)

    drawBg(canvas)                     // vẽ nền — PHỦ CẢ priceAxisRect (không riêng khối plot), tránh strip trông như lỗ trống
    drawGrid(canvas):                  // lưới ngang/dọc mọi panel (dùng lại đúng mTimeTicks.x + priceTicks) — bỏ qua nếu hideGrid=true
        if !hideGrid: vẽ lưới
        drawAxisSeparators(canvas)     // LUÔN vẽ, KHÔNG phụ thuộc hideGrid — 2 đường viền khung: dọc tại x=plotWidth
                                        // (ranh giới plot|priceAxis), ngang tại y=dateRect.top (ranh giới {plot,priceAxis}|{date,corner})

    if data không rỗng:
        drawChart(canvas):
            for mỗi secondary panel: drawReferenceLines()   // vẽ TRƯỚC transform, ở screen space (vd 20/80 StochRSI)
            canvas.save()
            canvas.clipRect(0, 0, plotWidth, dateRect.top)  // MUST MATCH §3.1/§4 — chặn TRÀN vào priceAxisRect,
                                                              // áp TRƯỚC translate/scale X nên nằm screen space
            canvas.translate(translateX*scaleX, 0); canvas.scale(scaleX, 1)   // transform X — áp cho TOÀN BỘ phần dưới
            canvas.save()
            canvas.clipRect(mainRect band mở rộng X)
            canvas.translate(0, centerY*(1-scaleY)+offsetY); canvas.scale(1, scaleY)   // transform Y — CHỈ áp main
            for i in realStartIndex..realStopIndex: MainRenderer.drawChart(candle[i-1], candle[i])   // §3.5 — dải RỘNG (đủ nến nguồn cho đường bị dịch)
            canvas.restore()            // kết thúc scope scaleY — vol/secondary KHÔNG bị ảnh hưởng
            for i in visibleStartIndex..visibleStopIndex:    // §3.5 — dải HẸP (đúng viewport ∩ dữ liệu thật)
                VolRenderer.drawChart(candle[i-1], candle[i])
                for mỗi SecondaryRenderer: .drawChart(candle[i-1], candle[i])
            if long-press hoặc (tap-to-show && isOnTap): drawCrossLine(canvas)
            if trend-line mode: drawTrendLines(canvas)
            canvas.restore()             // kết thúc scope scaleX/translateX (VÀ clip plotWidth vừa thêm)

        drawVerticalText(canvas)        // label trục Y (main/vol/secondary) — vẽ vào priceAxisRect, KHÔNG bị scaleX ảnh hưởng
        drawDate(canvas)                // label trục X (thời gian) — clip cứng vào [0, plotWidth] × dateRect, canvas tự
                                          // cắt phần label trượt qua mép khi pan (không có logic ẩn/hiện riêng)
        drawText(canvas, candle[visibleStopIndex])  // label indicator ở góc trên — LUÔN dùng candle bên PHẢI đang hiển thị
                                              // THẬT (visibleStopIndex, không phải realStopIndex — có thể trỏ vùng tương lai
                                              // — cũng không phải candle cuối mảng) — cập nhật theo vị trí scroll
        drawMaxAndMin(canvas)            // nhãn giá cao/thấp nhất trong vùng hiển thị — qua applyScaleY
        drawNowPrice(canvas)             // đường + badge giá hiện tại — qua applyScaleY, offsetX theo plotWidth (không phải width)

        if long-press hoặc (tap-to-show && isOnTap):
            drawCrossLineText(canvas)    // popup chi tiết + phát InfoWindow selection event; bubble giá/ngày theo plotWidth
```

**Kiểm soát khi nào vẽ lại (dirty-check)**: chỉ render lại khi ít nhất 1 trong các field sau đổi giá trị (so sánh theo **giá trị**, không phải reference, đặc biệt với mảng `data`/`trendLines` có thể bị mutate in-place):

```
data, scaleX, scrollX, scaleY, offsetY, isLongPress, selectX, isOnTap,
volHidden, isLine, mainIndicators, secondaryIndicators,
livePrice, isTrendLineMode, selectY, trendLines(so theo giá trị từng điểm)
```

> Bẫy thường gặp: nếu container giữ 1 reference `data` array và sửa field bên trong nó (vd cập nhật giá nến cuối theo tick), rồi truyền cùng reference vào renderer → dirty-check theo reference sẽ luôn thấy "không đổi" → **không vẽ lại**. Luôn tạo mảng/object mới khi dữ liệu thay đổi (immutable update), hoặc dùng `livePrice` riêng biệt cho việc cập nhật giá real-time mà không cần thay `data` (xem §7).

---

## 6. Gesture & Event model

Đây là phần nhiều rủi ro nhất khi port — nếu state machine sai, cảm giác vuốt/zoom sẽ khác Flutter dù công thức render đúng 100%.

### 6.1 State sở hữu bởi Container

```
scaleX: number        // zoom ngang, clamp [minScale, maxScale] (props, mặc định 0.2–2.2)
scrollX: number        // px trong "data space" tính từ mép phải, clamp [0, maxScrollX]
scaleY: number        // zoom dọc main, clamp [0.3, 5.0]
offsetY: number        // pan dọc main, clamp theo §3.2
selectX, selectY: number   // vị trí crosshair
isLongPress, isOnTap: boolean
isDrag, isScale: boolean
```

> **Giá trị khởi động thực tế**: nếu KHÔNG truyền `chartScale` (prop scale-state để khôi phục — xem §6.11/§12), container khởi động với `scaleX = 1.0` (KHÔNG PHẢI `0.8`) — `scrollX = 0.0`, `scaleY = 1.0`, `offsetY = 0.0`. Con số `0.8` chỉ là giá trị mặc định của CHÍNH class scale-state khi ai đó tự dựng nó không truyền tham số (dùng khi muốn chủ động yêu cầu "mở chart hơi zoom-out" qua `chartScale`), **không tự động áp dụng** cho lần mở chart đầu tiên nếu prop đó bị bỏ qua. Port cần phân biệt rõ 2 giá trị mặc định này — dùng nhầm `0.8` làm scale khởi động sẽ khiến chart mở ra zoom khác Flutter dù mọi công thức sau đó đều đúng.

### 6.2 Tap

- **Tap trong vùng main chart** (không phải trend-line mode): **toggle** crosshair — tap lần 1 bật (`isOnTap=true`, cập nhật `selectX`), tap lần 2 tắt (`isOnTap=false`, phát selection=null).
- **Trend-line mode**: tap ghi nhận điểm đầu/cuối của đoạn thẳng (2 tap liên tiếp = 1 đoạn).

### 6.3 Long-press

- `onLongPressStart`: bật `isLongPress=true`, cập nhật `selectX`/`selectY` theo vị trí nhấn.
- `onLongPressMoveUpdate`: cập nhật `selectX`/`selectY` theo vị trí ngón tay (crosshair "bám" ngón tay).
- `onLongPressEnd`: tắt `isLongPress`, phát selection=null (ẩn popup).

### 6.4 Scale gesture — state machine đầy đủ

**Lúc bắt đầu gesture** (`onScaleStart`), chốt 2 cờ **một lần duy nhất**, giữ nguyên suốt gesture:

```
isScaleYGesture = (số ngón == 1)
               AND (điểm chạm.x nằm trong strip trục giá thật đang vẽ, bề rộng = priceAxisWidth, §4 — KHÔNG PHẢI effectiveRightPaddingPx, 2 khái niệm khác nhau: cái sau là padding SAU nến cuối cùng cho scroll bound §3.1, không liên quan diện tích strip hiển thị)
               AND (điểm chạm.y <= mainRect.bottom)   // ⚠️ thêm sau — KHÔNG kích hoạt nếu chạm rơi vào strip đối diện panel volume/secondary
gestureInMain    = (điểm chạm nằm trong mainRect)     // top = mainRect.top (SAU dải label topPadding, không tính dải đó)
```

> **Vì sao cần điều kiện `y <= mainRect.bottom`**: `scaleY` chỉ scale MAIN chart (xem scope B ở bảng §3.4 — `VolRenderer`/`SecondaryRenderer` nằm ngoài scope này, không hề bị ảnh hưởng bởi `scaleY`). Nếu thiếu điều kiện này, kéo dọc ở ĐOẠN strip giá đối diện panel volume/RSI/MACD... vẫn kích hoạt `scaleY` của main chart — trải nghiệm sai (chạm vào 1 chỗ không liên quan gì tới main chart lại làm nó zoom). Thiếu điều kiện Y này là bug thật đã gặp trong bản Flutter gốc, mới fix — port nhớ có nó ngay từ đầu.

**Trong lúc gesture cập nhật** (`onScaleUpdate`), rẽ nhánh theo đúng thứ tự ưu tiên sau (nhánh trên match trước thì bỏ qua nhánh dưới):

| # | Điều kiện | Hành vi |
|---|---|---|
| 0 | `!gestureInMain` VÀ số ngón < 2 | `scrollX += dx/scaleX`, clamp `[0, maxScrollX]`. `dy` KHÔNG pan chart — forward nguyên `dy` qua callback `onVerticalOverscroll` (§6.6) để parent tự quyết cuộn ngoài. Vẫn kiểm tra trigger `onLoadMore` (xem bảng §6.7). |
| 1 | `dragStartedInTapMode` VÀ số ngón==1 VÀ không phải scaleY-gesture | Di chuyển crosshair: `selectX = điểm chạm hiện tại.x` (không scroll, không zoom). |
| 2 | `isScaleYGesture` VÀ số ngón==1 | `scaleY -= (dy hiện tại - dy lúc trước) * 0.005`, clamp `[0.3, 5.0]`. Re-clamp `offsetY` ngay sau (bound phụ thuộc `scaleY`). |
| 3 | `pinchScale != 1.0` (≥2 ngón) | `scaleX = scaleXLúcGestureStart * pinchScale`, clamp `[minScale, maxScale]`. |
| 4 | (mặc định — 1 ngón kéo tự do) | `scrollX += dx/scaleX`, clamp `[0, maxScrollX]`. NẾU `scaleY != 1.0`: `offsetY = clamp(offsetY + dy)`; phần dôi ra ngoài clamp forward qua `onVerticalOverscroll` (§6.6). Kiểm tra trigger `onLoadMore`. **Chi tiết đầy đủ nhánh này — xem §6.5.** |

`dragStartedInTapMode` = giá trị của `isOnTap` **tại thời điểm** `onScaleStart` (chốt lúc bắt đầu, không đổi giữa chừng).

**Lúc kết thúc gesture** (`onScaleEnd`):

```
if scaleX hoặc scaleY thay đổi so với lúc bắt đầu gesture: phát onChartScaleChanged({scaleX, scaleY, scrollX})
if không phải đang kéo crosshair (!dragStartedInTapMode): khởi động fling animation (§6.8) theo velocity.x
if scaleX thay đổi: sau 1 frame, nếu maxScrollX <= 0 (đã zoom out hết cỡ, thấy toàn bộ data) → trigger onLoadMore(true)
```

### 6.5 Cơ chế tích luỹ chính xác của `scaleX`/`scaleY`/`scrollX` — vì sao pinch có "dead-zone" nhưng kéo tay thì không

Đây là phần **kỹ thuật nhất** của toàn bộ gesture model — nếu port sai phần này, các con số cuối cùng có thể clamp đúng chỗ nhưng **cảm giác kéo/pinch sẽ khác Flutter** (đặc biệt khi chạm biên `minScale`/`maxScale` rồi đổi hướng giữa chừng). Có **3 kiểu tích luỹ khác nhau** trong cùng 1 chart, không được lẫn lộn.

#### (A) `scaleX` khi pinch (nhánh 3, §6.4) — "recompute từ mốc đầu gesture", CÓ dead-zone khi đảo hướng

```
onGestureStart (≥2 ngón chạm):
    scaleXAtGestureStart = scaleX          // chốt NGAY 1 LẦN, giữ nguyên suốt gesture, KHÔNG cập nhật lại giữa chừng

onGestureUpdate (mỗi frame):
    cumulativeRatio = tỉ lệ khoảng cách 2 ngón HIỆN TẠI / khoảng cách 2 ngón LÚC BẮT ĐẦU GESTURE (không phải so với frame trước)
    scaleX = clamp(scaleXAtGestureStart * cumulativeRatio, minScale, maxScale)   // LUÔN tính lại từ mốc đầu, KHÔNG dùng scaleX(frame trước) làm gốc
```

Điểm mấu chốt: `cumulativeRatio` là tỉ lệ **luỹ kế kể từ lúc gesture bắt đầu**, không phải delta giữa 2 frame liên tiếp. Ở Flutter, giá trị này chính là `ScaleUpdateDetails.scale` do framework tự tính (framework tự nhớ khoảng cách 2 ngón lúc `onScaleStart` và luôn so với hiện tại). Vì `scaleX` được **tính lại từ đầu mỗi frame** (không cộng dồn từ giá trị frame trước), khi user pinch vượt quá `maxScale` rồi kéo ngược lại, `scaleX` **không nhúc nhích ngay** — nó đứng yên ở `maxScale` cho tới khi `cumulativeRatio` giảm xuống dưới đúng ngưỡng làm `scaleXAtGestureStart * cumulativeRatio` quay lại dưới `maxScale`. Nói cách khác: **user phải "undo" đúng phần đã pinch quá đà trước khi chart bắt đầu zoom out lại** — đây là **dead-zone khi đảo hướng**, xảy ra tự nhiên và **PHẢI giữ nguyên** khi port (đây không phải bug, mà là hệ quả tất yếu của cách dùng đúng API pinch kiểu "cumulative-since-gesture-start" mà Flutter/iOS/RN đều cung cấp).

*Ví dụ số*: `minScale=0.2, maxScale=2.2`. User bắt đầu pinch từ `scaleX=1.0`. Zoom vào rất nhanh khiến `cumulativeRatio` đạt `3.5` (tức muốn `scaleX=3.5`, bị clamp hiển thị `2.2`). User bắt đầu thu ngón tay lại (pinch ra): `cumulativeRatio` giảm dần `3.5 → 3.0 → 2.5 → 2.2` — suốt quãng này `scaleX` vẫn đứng yên `2.2` (vì `1.0×ratio` vẫn `≥ 2.2`). Chỉ khi `cumulativeRatio` tụt xuống **dưới** `2.2` thì `scaleX` mới bắt đầu giảm tiếp — đúng là "dead-zone", nhưng đúng như Flutter gốc.

#### (B) `scaleY` khi kéo trong dải phải (nhánh 2, §6.4) và `scrollX` khi kéo tự do (nhánh 4, §6.4) — "cộng dồn tại chỗ", KHÔNG có dead-zone

```
onGestureUpdate (mỗi frame):
    frameDelta = vị trí ngón tay HIỆN TẠI - vị trí ngón tay Ở FRAME TRƯỚC (không phải so với lúc bắt đầu gesture)
    state = clamp(state_hiện_tại + f(frameDelta), min, max)     // CỘNG DỒN trực tiếp vào giá trị đã có (có thể đã bị clamp), KHÔNG tính lại từ mốc đầu gesture
```

Cụ thể: `scaleY -= frameDeltaY * 0.005` (nhánh 2) và `scrollX += frameDeltaX/scaleX` (nhánh 4) đều dùng **delta từng frame** (Flutter: `details.focalPointDelta`, hoặc tự tính bằng `vị trí hiện tại - vị trí đã lưu ở frame trước rồi cập nhật lại mốc lưu sau mỗi frame`), CỘNG THẲNG vào giá trị state hiện có rồi mới clamp. Vì vậy **không có dead-zone**: nếu user kéo vượt biên (chạm `scaleY=5.0` hoặc `scrollX=maxScrollX`) rồi đảo hướng ngay lập tức, state bắt đầu đổi NGAY frame tiếp theo — không cần "undo" gì cả. Ví dụ: `scaleY` đang bị clamp ở `5.0`, user đổi hướng kéo (frameDelta đổi dấu) → `scaleY = clamp(5.0 + f(frameDelta_mới))` cho kết quả nhỏ hơn `5.0` ngay lập tức.

> **Vì sao khác nhau**: nhánh (A) dùng nguyên giá trị "cumulative-since-gesture-start" mà các API pinch native (iOS `UIPinchGestureRecognizer.scale`, RN gesture-handler `scale`, Flutter `ScaleUpdateDetails.scale`) tự cung cấp — cách dùng ĐÚNG theo thiết kế của các API này là `base × cumulative`, không phải cộng dồn từng frame. Nhánh (B) lại dùng đúng kiểu "delta từng frame" (giống hầu hết pan/scroll API trên mọi nền tảng). Đây KHÔNG phải sự tuỳ tiện của code gốc — là 2 pattern tích luỹ khác nhau, áp cho 2 loại gesture khác nhau, và **kết quả hành vi (có/không dead-zone) khác nhau thật sự, quan sát được bằng mắt**.

#### (C) `scaleX` khi điều khiển qua `KChartController.zoomIn()/zoomOut()` — CỘNG/TRỪ MỘT BƯỚC CỐ ĐỊNH (kiểu thứ 3, không giống cả A lẫn B)

```
zoomIn():  scaleX = clamp(scaleX + 0.1, minScale, maxScale)
zoomOut(): scaleX = clamp(scaleX - 0.1, minScale, maxScale)
```

Đây là **cộng/trừ một hằng số cố định `0.1` mỗi lần gọi** (không phải nhân theo tỉ lệ như pinch, cũng không phải theo pixel kéo tay) — mỗi lần bấm nút zoom-in/zoom-out chỉ đổi đúng `0.1` đơn vị `scaleX`, bất kể `scaleX` hiện tại là bao nhiêu. Việc này cũng KHÔNG có dead-zone (cùng kiểu "cộng dồn tại chỗ" như nhánh B), vì áp trực tiếp lên giá trị `scaleX` hiện có.

`KChartController` còn có `reset()` — **⚠️ CHỈ reset trục X, KHÔNG đụng tới trục Y**:

```
reset(): scaleX = 1.0
         scrollX = 0.0
         selectX = 0.0
         // scaleY, offsetY GIỮ NGUYÊN — reset() KHÔNG chạm vào
```

Đối chiếu với double-tap (§6.10) — **CHỈ reset trục Y, KHÔNG đụng tới trục X**: `scaleY = 1.0, offsetY = 0.0`, giữ nguyên `scaleX`/`scrollX`. Vậy chart có **2 cơ chế "reset" hoàn toàn độc lập, mỗi cái phụ trách đúng 1 trục**:

| Reset | Trục bị reset | Trục KHÔNG đổi | Cách kích hoạt |
|---|---|---|---|
| `KChartController.reset()` | `scaleX=1.0`, `scrollX=0.0`, `selectX=0.0` | `scaleY`, `offsetY` | Gọi từ code (nút bấm ngoài UI) |
| Double-tap vùng phải (§6.10) | `scaleY=1.0`, `offsetY=0.0` | `scaleX`, `scrollX` | Gesture double-tap trong dải phải |

Không có cách nào có sẵn để reset CẢ 2 trục cùng lúc bằng 1 hành động — muốn "reset toàn bộ" phải gọi cả `controller.reset()` VÀ tự set `scaleY=1.0/offsetY=0.0` (hoặc giả lập double-tap) riêng.

> **⚠️ Lưu ý khi port — `reset()`/`zoomIn()`/`zoomOut()` KHÔNG dừng animation quán tính đang chạy.** Khác với gesture chạm tay (`onScaleStart` luôn gọi `_stopAnimation()` trước khi xử lý gesture mới), 3 action của controller **không hề gọi hàm dừng fling animation**. Hệ quả: nếu gọi `controller.reset()`/`zoomIn()`/`zoomOut()` đúng lúc `scrollX` đang chạy animation quán tính (§6.9) sau 1 cú kéo trước đó, animation vẫn tiếp tục tick và tiếp tục ghi đè `scrollX` ở frame kế tiếp — có thể "đè" luôn giá trị `scrollX=0.0` mà `reset()` vừa set (vì animation set lại `scrollX = giá trị nội suy hiện tại` mỗi frame, độc lập với action vừa gọi). Khi port, cân nhắc có chủ động dừng animation trước khi áp action từ controller hay không — nếu muốn parity 100% với hành vi hiện tại (kể cả tác dụng phụ này), **KHÔNG** thêm bước dừng animation; nếu muốn UX chắc chắn hơn (không có khả năng bị animation ghi đè), phải note lại đây là điểm cố ý khác Flutter gốc.

#### Bảng đối chiếu nhanh — port đúng platform-native API nào cho từng loại

| State | Kiểu tích luỹ | Có dead-zone? | API cần dùng đúng cách |
|---|---|---|---|
| `scaleX` qua pinch | (A) cumulative-since-gesture-start × mốc đầu | ✅ Có | iOS `UIPinchGestureRecognizer.scale` (đã cumulative sẵn — ĐỪNG reset `.scale=1` mỗi callback); RN gesture-handler `nativeEvent.scale` (đã cumulative sẵn) |
| `scaleX` qua pinch, trên **Android** | (A) — nhưng `ScaleGestureDetector.getScaleFactor()` của Android trả về **incremental theo từng callback**, KHÔNG cumulative | ✅ Có (nếu port đúng) | ⚠️ Phải tự cộng dồn: giữ 1 biến `cumulativeRatio` riêng, reset `=1.0` lúc gesture bắt đầu, MỖI callback nhân dồn `cumulativeRatio *= detector.getScaleFactor()`, rồi tính `scaleX = clamp(scaleXAtGestureStart * cumulativeRatio)` — KHÔNG dùng trực tiếp `scaleX = clamp(scaleX * getScaleFactor())` (cách này rơi vào pattern (B), sẽ MẤT dead-zone, lệch behavior so với Flutter) |
| `scaleY` qua kéo 1 ngón (dải phải) | (B) delta-từng-frame cộng dồn tại chỗ | ❌ Không | Pan/drag gesture bất kỳ (Android `onScroll`/`onTouchEvent` MOVE delta, iOS `UIPanGestureRecognizer.translation(in:)` — nhớ reset translation về 0 sau mỗi callback nếu dùng kiểu cumulative-since-start của pan recognizer, để lấy đúng delta-từng-frame) |
| `scrollX` qua kéo 1 ngón | (B) delta-từng-frame cộng dồn tại chỗ | ❌ Không | tương tự `scaleY` ở trên |
| `scaleX` qua `KChartController` | (C) cộng/trừ bước cố định `±0.1` | ❌ Không | không liên quan gesture — chỉ là phép cộng thường trên state |

> **Lưu ý riêng cho Android**: `UIPanGestureRecognizer`/pan tương đương và `ScaleGestureDetector` là 2 API tách biệt trên Android; `ScaleGestureDetector` mặc định cung cấp incremental factor — đây là nền tảng DUY NHẤT trong 4 nền tảng (Flutter/iOS/RN/Android) mà kiểu dữ liệu gesture mặc định KHÔNG khớp sẵn với pattern (A) mà Flutter dùng. Nếu bỏ qua điểm này, bản port Android sẽ zoom "mượt" hơn Flutter khi đảo hướng pinch sau khi chạm `minScale`/`maxScale` — tức là RESPONSIVE hơn bản gốc chứ không phải bug rõ ràng, nên rất dễ bị bỏ qua trong review nếu không test riêng case này.

#### Điểm neo (anchor point) khi pinch `scaleX` — KHÔNG neo theo vị trí 2 ngón tay

Một chi tiết dễ bị hiểu lầm: nhìn qua tưởng pinch sẽ zoom quanh điểm giữa 2 ngón tay (`focalPoint`) như phần lớn UI khác — nhưng code nhánh 3 (§6.4) **chỉ đọc `details.scale`, hoàn toàn không đọc `details.focalPoint`/`focalPointDelta`**, và cũng không hề cập nhật `scrollX` trong nhánh này. Suy ra trực tiếp từ công thức translate ở §3.1 (`translateX = scrollX + getMinTranslateX(scaleX)`, trong đó `getMinTranslateX` phụ thuộc `scaleX`): vì `scrollX` đứng yên trong suốt gesture pinch, điểm trên màn hình **thực sự đứng yên khi `scaleX` đổi** luôn là:

```
screenX_neo_cố_định = chartWidth - effectiveRightPaddingPx(xFrontPadding, chartWidth)
```

— tức là **mép phải chart** (ngay biên padding, gần vị trí nến mới nhất), **BẤT KỂ 2 ngón tay đang đặt ở đâu trên màn hình** và bất kể đang scroll xem phần nào của lịch sử. Nếu user đang cuộn xem nến cũ ở giữa/trái màn hình rồi pinch-zoom tại đó, các nến dưới ngón tay sẽ **trôi đi** trong lúc zoom (không đứng yên dưới tay) — khác hẳn kiểu "zoom quanh điểm chạm" quen thuộc ở nhiều chart khác (kể cả TradingView). Khi port, **KHÔNG được "sửa" thành zoom-quanh-focal-point** dù đó là hành vi trực giác hơn — làm vậy sẽ lệch hẳn so với Flutter gốc. Muốn parity đúng: giữ `scrollX` (hoặc biến tương đương) **hoàn toàn không đổi** trong suốt gesture pinch, chỉ đổi `scaleX`.

#### Điểm neo khi kéo dọc chỉnh `scaleY` (nhánh 2, §6.4) — luôn là tâm dọc `mainRect`, không phải vị trí ngón tay

Tương tự, chỉnh `scaleY` bằng kéo 1 ngón trong dải phải KHÔNG neo theo vị trí bắt đầu kéo — công thức canvas transform (§3.2) luôn neo tại `centerY = (mainRect.top + mainRect.bottom)/2` (tâm dọc cố định của vùng main chart), bất kể ngón tay chạm ở đâu trong dải phải (trên cao hay dưới thấp). `offsetY` chỉ dịch thêm SAU điểm neo cố định này, không phải dịch quanh vị trí chạm.

### 6.6 Kéo/di chuyển chart khi `scaleY` đã ≠ 1 (pan sau khi zoom dọc) — ⚠️ trọng tâm hay port thiếu

Đây là hành vi xảy ra khi user **đã** pinch/zoom dọc main chart (`scaleY != 1.0`, xem nhánh 2 ở bảng §6.4), sau đó **thả tay ra và chạm lại để kéo (pan) bình thường** ở bất kỳ đâu trong main chart — KHÔNG phải chạm lại vào dải bên phải (đó là gesture zoom, không phải pan). Đây chính là nhánh **4 (mặc định)** của bảng §6.4, nói kỹ lại ở đây vì nó dễ port thiếu nhất.

**Điều kiện tiên quyết để offsetY được cập nhật:**

```
gesture rơi vào nhánh 4 (§6.4) khi và chỉ khi TẤT CẢ đúng:
  - gestureInMain == true       (bắt đầu chạm BÊN TRONG mainRect)
  - isScaleYGesture == false    (KHÔNG bắt đầu trong strip trục giá — xem công thức đầy đủ ở §6.4, không phải effectiveRightPaddingPx)
  - dragStartedInTapMode == false  (không phải đang kéo để di chuyển crosshair)
  - số ngón < 2 HOẶC pinchScale == 1.0   (không phải đang pinch)
```

**Bên trong nhánh 4, có 2 phần ĐỘC LẬP xảy ra cùng lúc trên 1 cú kéo** (cả 2 đều dùng pattern (B) delta-từng-frame ở §6.5, KHÔNG dead-zone):

```
// (1) Trục X — LUÔN LUÔN cập nhật, không phụ thuộc scaleY
scrollX = clamp(scrollX + dx/scaleX, 0, maxScrollX)

// (2) Trục Y — CHỈ cập nhật NẾU scaleY != 1.0 tại thời điểm đó
if scaleY != 1.0:
    maxOffset      = mainChartBaseHeight * scaleY / 2      // biên phụ thuộc scaleY HIỆN TẠI (càng zoom sâu, biên pan càng rộng)
    newOffsetY     = offsetY + dy                           // dy = delta Y THÔ theo px màn hình — KHÔNG chia cho scaleY
    clampedOffsetY = clamp(newOffsetY, -maxOffset, maxOffset)
    offsetY        = clampedOffsetY
    overscroll     = newOffsetY - clampedOffsetY            // phần vượt biên, xem §6.7
    if overscroll != 0: onVerticalOverscroll(overscroll)
// nếu scaleY == 1.0: KHÔNG làm gì cả ở phần (2) — kéo dọc lúc này hoàn toàn vô tác dụng
```

**Những điểm phải giữ đúng khi port:**

1. **Cổng điều kiện là chính scaleY, đọc tại thời điểm đó** — không phải "đã từng zoom" mà là "hiện tại có đang zoom hay không". Nếu user zoom dọc rồi double-tap reset về `scaleY=1.0` (§6.10), thao tác kéo dọc ngay sau đó lập tức trở lại **vô tác dụng** trên trục Y (dù trước đó đang hoạt động).
2. **Trục X luôn phản hồi bất kể trục Y có phản hồi hay không** — một cú kéo chéo khi `scaleY != 1` sẽ di chuyển chart theo **cả 2 trục cùng lúc** (chéo), không phải chỉ 1 trục tại 1 thời điểm. Nếu port tách gesture ngang/dọc thành 2 recognizer loại trừ nhau (`exclusive`), hành vi sẽ SAI so với Flutter (Flutter cho phép cả 2 cập nhật trong CÙNG MỘT lần callback `onScaleUpdate`).
3. **`dy` KHÔNG chia cho `scaleY`** trước khi cộng vào `offsetY` — khác với `scrollX` phải chia cho `scaleX`. Lý do: `offsetY` được cộng vào **sau** khi `scaleY` đã áp trong công thức canvas transform (`translate(...+offsetY)` xảy ra sau `scale(1,scaleY)` khi compose ma trận — xem §3.2), nên `offsetY` sống ở "không gian màn hình" đã scale sẵn: 1px kéo tay = đúng 1px di chuyển trên màn hình, bất kể đang zoom dọc bao nhiêu. Trong khi đó `scrollX` sống ở "data space" (chưa scale), nên phải chia cho `scaleX` để quy đổi ngược — cả 2 cách khác nhau nhưng cùng đạt hiệu ứng UX giống nhau: điểm chạm luôn "bám" đúng theo ngón tay 1:1 trên màn hình dù đang zoom trục nào.
4. **`scaleY` không đổi trong lúc pan này** — pan chỉ di chuyển vị trí xem (`offsetY`) trong phạm vi đã zoom, KHÔNG zoom thêm/bớt. Chỉ gesture ở dải bên phải (nhánh 2, §6.4) mới đổi `scaleY`.
5. **KHÔNG có fling/quán tính cho trục dọc.** Ở `onScaleEnd`, animation quán tính (§6.9) CHỈ chạy cho `scrollX`, dùng `velocity.x` — không có bất kỳ animation tương đương nào cho `offsetY`. Khi thả tay, `offsetY` dừng đứng ngay tại vị trí lúc đó; chỉ `scrollX` tiếp tục "trôi" theo trớn. Đây là bất đối xứng phải giữ nguyên khi port (đừng vô tình thêm momentum cho trục Y vì "trông hợp lý hơn" — sẽ lệch so với Flutter).
6. **Ngoài `mainRect` (chạm vào vùng volume/secondary/date), pan dọc `offsetY` KHÔNG BAO GIỜ xảy ra — bất kể `scaleY` là bao nhiêu.** Đây là nhánh 0 ở bảng §6.4 (`!gestureInMain`): `dy` LUÔN LUÔN bị forward nguyên vẹn qua `onVerticalOverscroll` (xem §6.7), không bao giờ cộng vào `offsetY` của main chart — dù lúc đó `scaleY != 1`. Vùng cho phép pan dọc main chart chỉ giới hạn đúng bên trong `mainRect`, không mở rộng ra vol/secondary/date dù về mặt thị giác chúng nằm "ngay dưới" main chart.
7. **`offsetY` KHÔNG nằm trong scale-state được lưu/khôi phục** (`{scaleX, scaleY, scrollX}` — xem §6.11 và định nghĩa scale-state ở §1/§12) — nghĩa là khi container bị tạo lại hoặc đổi timeframe rồi khôi phục `scaleY` cũ, `offsetY` LUÔN bắt đầu lại từ `0` (canh giữa), dù trước đó user đã pan lệch tâm bao nhiêu. Chỉ MỨC ZOOM (`scaleY`) được nhớ lại, vị trí PAN (`offsetY`) thì không.
8. Double-tap (§6.10) reset **đồng thời cả 2**: `scaleY=1.0` **và** `offsetY=0.0` — không có gesture có sẵn nào reset riêng lẻ 1 trong 2.

### 6.7 Overscroll handoff (bàn giao cuộn dọc cho parent)

Khi pan dọc vượt quá biên clamp của `offsetY` (đã hiện đúng 50% nội dung ở mép, xem công thức đầy đủ ở §6.6 mục (2)), phần **dôi ra** được báo cho parent qua 1 callback riêng, KHÔNG tự chart cuộn tiếp:

```
newOffsetY = offsetY + dy
clamped    = clamp(newOffsetY, -maxOffset, maxOffset)
overscroll = newOffsetY - clamped         // phần vượt biên
offsetY    = clamped
if overscroll != 0: callback(overscroll)   // parent tự quyết định có forward sang outer ScrollView hay không
```

Quy ước dấu: `overscroll > 0` = ngón tay đang kéo XUỐNG khi đã ở biên trên cùng; `overscroll < 0` = kéo LÊN khi đã ở biên dưới cùng.

> Callback này còn được gọi ở nhánh 0 (§6.4, ngoài `mainRect`) theo cách KHÁC: ở đó **toàn bộ** `dy` được forward (không có khái niệm "phần dôi ra" vì không có pan nào xảy ra trước đó để so sánh) — trong khi ở nhánh 4 (trong `mainRect`, §6.6) chỉ phần VƯỢT biên clamp mới được forward, phần còn lại đã được main chart "tiêu thụ" để pan `offsetY`.

### 6.8 `onLoadMore` — TẤT CẢ 4 điểm trigger (không được thiếu điểm nào)

| # | Khi nào | Điều kiện chính xác |
|---|---|---|
| a | Trong lúc kéo/pinch (mọi nhánh update ở §6.4) | `scrollX >= maxScrollX * 0.8` HOẶC `maxScrollX <= 0` — gọi `onLoadMore(true)` (nếu chưa `isLoadingMore`) |
| b | Fling animation chạm biên phải | `scrollX == maxScrollX` khi animation dừng → `onLoadMore(false)` |
| c | Sau khi pinch zoom-out kết thúc | 1 frame sau `onScaleEnd`, nếu `maxScrollX <= 0` (đã thấy hết data) → `onLoadMore(true)` |
| d | **Không cần gesture** — auto-check mỗi khi mount/data đổi | Sau mỗi lần layout: nếu `maxScrollX <= 0` VÀ chưa từng request cho đúng `data.length` hiện tại (dedupe key = độ dài mảng data) → `onLoadMore(true)` |

> Trigger (d) hay bị bỏ sót khi port — không có nó, chart hiển thị ít data hơn màn hình (mới mount, hoặc data ít) sẽ **đứng im vĩnh viễn** vì không gesture nào xảy ra để trigger (a)/(b)/(c). Dedupe theo độ dài mảng (không phải theo timestamp) để tránh spam request khi component re-render vì lý do không liên quan (đổi theme, đổi style...) trong lúc đang chờ request trước hoàn thành.

Tham số `bool` truyền vào `onLoadMore`: `true` = nên cuộn tới mép TRÁI (load nến CŨ hơn, phổ biến nhất — lazy-load lịch sử); `false` = đã cuộn hết mép PHẢI (thường bỏ qua, hiếm khi cần load nến MỚI hơn qua cách này — nến mới thường tới qua stream/tick riêng).

### 6.9 Fling (quán tính sau khi thả tay — CHỈ trục X, xem mục 5 ở §6.6)

```
targetScrollX = scrollX + velocityX * flingRatio   // flingRatio mặc định 0.5
animate scrollX: begin=scrollX hiện tại → end=targetScrollX, duration=flingTime(mặc định 600ms), easing=flingCurve(mặc định "decelerate")
mỗi frame animation: clamp scrollX vào [0, maxScrollX]; nếu chạm biên → dừng animation ngay + trigger tương ứng (§6.8.b khi chạm phải, không trigger gì khi chạm trái=0)
```

### 6.10 Double-tap (vùng bên phải — implement bằng 1 `GestureDetector` RIÊNG, tách khỏi gesture chính)

```
onDoubleTap trong dải priceAxisWidth (§4) bên phải, từ y=0 tới mainRect.bottom:
    scaleY = 1.0
    offsetY = 0.0
    phát onChartScaleChanged
```

**Cách implement khác hẳn nhánh 2 ở §6.4** — đây KHÔNG phải cùng 1 gesture handler. Toàn bộ chart nằm trong 1 `GestureDetector` lớn xử lý tap/long-press/scale (nhánh 0–4 ở §6.4). Riêng double-tap-reset được tách ra thành **một `GestureDetector` con khác, phủ đè lên 1 vùng nhỏ ở góc phải** (dùng `Positioned` bên trên `GestureDetector` lớn trong `Stack`), CHỈ lắng nghe `onDoubleTap`, không xử lý gì khác. Lý do tách riêng: `GestureDetector` lớn không có callback double-tap độc lập theo toạ độ (nó dùng `onScaleStart`/`onTapUp`), nên double-tap-reset phải là 1 widget riêng đứng trên cùng để nhận sự kiện trước.

**Kích thước & vị trí vùng double-tap** — tính từ chính đoạn code này:

```
width  = priceAxisWidth (§4)   // bề rộng strip trục giá THẬT đang vẽ — KHÔNG PHẢI effectiveRightPaddingPx (đó là
                                 // padding sau nến cuối cho scroll bound §3.1, 2 khái niệm khác nhau, dễ nhầm)
top    = 0                                                              // TỪ ĐỈNH CÙNG của toàn bộ Stack — bao gồm cả vùng label main indicator (topPadding)
bottom = volumeHeight + totalSecondaryHeight + bottomPadding(16)        // tính từ ĐÁY Stack lên
       ⇒ tương đương: vùng double-tap kết thúc đúng tại mMainRect.bottom
       ⇒ vùng double-tap = TOÀN BỘ cột bên phải, từ y=0 đến y=mMainRect.bottom
         (tức PHỦ LUÔN dải topPadding phía trên nến — nơi hiển thị label "MA5:.. MA10:..", KHÔNG chỉ riêng mainRect)
```

> **Khớp CHÍNH XÁC với vùng "kéo 1 ngón để CHỈNH `scaleY`"** (nhánh 2, §6.4) — cả bề rộng (`priceAxisWidth`) lẫn phạm vi dọc (`y ∈ [0, mainRect.bottom]`, tức bao gồm cả dải `topPadding` phía trên nến) đều giống hệt nhau giữa 2 gesture. Đây là điểm CỐ TÌNH đồng bộ (không phải trùng hợp) — 2 cách kích hoạt cùng 1 mục đích ("tương tác với trục Y của main chart") nên phải cùng vùng nhận chạm, tránh trải nghiệm "double-tap reset được nhưng kéo tay không tác dụng" (hoặc ngược lại) ở cùng 1 điểm trên màn hình.
>
> **Lịch sử — trước đây 2 vùng này LỆCH NHAU** (nhánh kéo-tay chỉ tính từ `mainRect.top` trở xuống qua `_gestureInMain = isInMainRect(...)`, không tính dải `topPadding`; double-tap thì tính từ `y=0`) — có 1 `TODO` trong code xác nhận đây là thiếu sót chưa xử lý (`// TODO: bottom offset giới hạn vùng scaleY chỉ trong main chart`). Đã fix bằng cách thêm điều kiện `y <= mainRect.bottom` trực tiếp vào `isScaleYGesture` (§6.4) — không dùng `_gestureInMain`/`isInMainRect` cho nhánh này nữa, nên tự động khớp `top=0` với vùng double-tap mà không cần chỉnh gì thêm ở phía double-tap.
>
> **Widget-tree note riêng (không ảnh hưởng hành vi, chỉ ảnh hưởng hiệu năng khi port sang framework có re-render tương tự Flutter)**: `LayoutBuilder` chỉ bọc `Positioned` (không bọc `GestureDetector` lớn ở ngoài) — cố ý, để tránh phần còn lại của cây widget (đặc biệt info-dialog dùng stream/subscription single-listener) bị rebuild oan mỗi khi kích thước đổi.

### 6.11 Bù trừ scroll khi data thay đổi (append vs prepend)

Khi mảng data đổi độ dài giữa 2 lần render, phải phân biệt và xử lý khác nhau để **giữ nguyên vùng nến user đang xem**:

```
diff = newData.length - oldData.length
if diff <= 0: bỏ qua (không xử lý shrink/replace)

appended = (oldData[0].time == newData[0].time) AND (oldData.last.time != newData.last.time)
if !appended: bỏ qua (prepend lịch sử — getMinTranslateX() tự tính lại đúng, không cần bù)

if scrollX <= 0: bỏ qua (đang ở mép phải nhất → auto-follow nến mới, giữ nguyên 0)
else: scrollX += diff * pointWidth   // bù đúng số nến mới thêm × bề rộng 1 nến, để vùng đang xem không bị "trôi"
```

### 6.12 `livePrice` — cập nhật giá real-time KHÔNG cần đổi `data`

Truyền một giá trị số riêng biệt (không phải phần tử trong mảng `data`) để cập nhật đường/badge giá hiện tại theo tick socket, mà không cần tạo/thay list `data` mỗi tick (tránh recompute toàn bộ indicator mỗi tick):

```
nowPriceValue = livePrice ?? data.last.close
priceColor    = nowPriceValue >= data.last.open ? upColor : dnColor
```

`data` chỉ nên đổi khi nến **đóng** (candle close), `livePrice` đổi mỗi tick. Nếu tick tần suất cao (>10/s), nên throttle việc trigger vẽ lại xuống ~60fps (cập nhật biến giữ giá trị mọi lúc, nhưng chỉ yêu cầu vẽ lại tối đa mỗi ~16ms).

### 6.13 Khôi phục scale-state qua prop `chartScale` — cơ chế 2 pha + chặn vòng lặp callback

Đây là phần "scale" ít được để ý nhất nhưng dễ gây bug khó chịu nhất khi port: **khi nào** container áp giá trị `chartScale` (prop truyền từ ngoài, vd khi đổi timeframe muốn giữ nguyên zoom) vào state nội bộ, và **làm sao tránh vòng lặp** container→callback→parent→prop→container.

**Khi nào việc khôi phục chạy** — CHỈ 2 thời điểm, không phải mỗi lần rebuild:

```
1. Lúc container khởi tạo lần đầu (initState)
2. Khi prop chartScale ĐỔI GIÁ TRỊ so với lần trước (so sánh BẰNG GIÁ TRỊ {scaleX, scaleY, scrollX}, KHÔNG phải bằng reference)
```

**⚠️ Điều kiện so sánh PHẢI là value-equality, không phải reference-equality.** `KChartScaleState` override `==`/`hashCode` theo đúng 3 field `{scaleX, scaleY, scrollX}`. Đây là chi tiết SỐNG CÒN khi port sang framework hay tự tạo object mới mỗi lần render (React/RN re-render tạo prop mới mỗi lần trừ khi `useMemo`; Jetpack Compose recomposition cũng vậy trừ khi `remember`/`derivedStateOf`): nếu port so sánh theo REFERENCE thay vì giá trị, container sẽ tưởng `chartScale` "đổi" ở MỌI lần cha re-render (dù số liệu bên trong y hệt lần trước) → liên tục ép state nội bộ trở lại giá trị cũ → **user không thể tự tay kéo/zoom được nữa** vì mỗi rebuild lại bị snap-back. Ngược lại nếu port dùng đúng value-equality, việc cha re-render với `chartScale` cùng giá trị (dù khác instance) sẽ KHÔNG kích hoạt khôi phục lại — gesture đang dang dở của user không bị "cướp".

**Cơ chế khôi phục — CHẠY 2 PHA, không phải 1 lần duy nhất:**

```
PHA 1 (đồng bộ, ngay lập tức):
    saved = chartScale.clampedTo(minScale, maxScale)      // clamp scaleX theo props hiện tại
    suppressScaleCallback = true                           // ⚠️ chặn callback trong lúc restore — xem bên dưới
    scaleX  = saved.scaleX
    scaleY  = clamp(saved.scaleY, 0.3, 5.0)
    scrollX = clamp(saved.scrollX, 0, maxScrollX_HIỆN_TẠI) // ⚠️ maxScrollX lúc này CÓ THỂ CHƯA ĐÚNG
                                                             //    (chưa layout xong / data mới chưa paint lần nào
                                                             //     → maxScrollX có thể vẫn = 0 hoặc giá trị CŨ từ chart khác)
                                                             //    → nếu maxScrollX_HIỆN_TẠI <= 0, dùng 0 làm biên trên tạm thời
    offsetY = clamp(offsetY_hiện_có, -maxOffset(scaleY_mới), maxOffset(scaleY_mới))
              // KHÔNG có gì để gán từ `saved` — offsetY không nằm trong KChartScaleState (xem §6.6 mục 7)
              // chỉ RE-CLAMP giá trị offsetY đang có (thường là 0.0 nếu container mới tạo) theo scaleY mới
    lastScaleXAtGestureStart = scaleX                      // đồng bộ mốc pinch (§6.5-A) theo giá trị vừa restore
    suppressScaleCallback = false

PHA 2 (bất đồng bộ, SAU 1 frame layout — CHỈ chạy khi restore xảy ra lúc mount/data đổi, không chạy mọi lần):
    đợi tới sau khi layout + ít nhất 1 lần paint đã chạy xong (lúc này maxScrollX mới phản ánh ĐÚNG data/kích thước hiện tại)
    nếu chartScale prop vẫn CÒN Y HỆT lúc bắt đầu đợi (chưa bị đổi tiếp trong lúc chờ):
        reClampedScrollX = clamp(saved.scrollX, 0, maxScrollX_ĐÚNG)
        nếu reClampedScrollX != scrollX hiện tại: cập nhật scrollX = reClampedScrollX, yêu cầu vẽ lại
```

**Vì sao cần 2 pha**: `maxScrollX` (biên scroll tối đa) phụ thuộc `dataLen` VÀ `chartWidth` (§3.1) — cả 2 đều chỉ biết CHÍNH XÁC sau khi layout xong ít nhất 1 lần (đo được kích thước thật + chạy `calculateValue()` trên data thật). Tại thời điểm `initState`/lúc `chartScale` vừa đổi, `maxScrollX` có thể vẫn mang giá trị CŨ (từ frame trước, hoặc `0` nếu chart vừa mount lần đầu) — clamp `scrollX` ngay lúc đó CÓ THỂ SAI (bó hẹp `scrollX` về `0` một cách giả tạo dù giá trị muốn khôi phục lớn hơn). Pha 2 sửa lại đúng giá trị sau khi layout đã ổn định. Hệ quả quan sát được nếu port bỏ qua pha 2: **có thể thấy 1 frame chớp nháy** — chart hiện đúng vị trí scroll cũ (từ pha 1, bị bó về gần 0) rồi "giật" sang đúng vị trí đã lưu ngay frame sau (pha 2). Đây là **artifact chấp nhận được** của cách Flutter defer việc đọc layout info; điều BẮT BUỘC phải giữ đúng khi port không phải là chớp nháy 1 frame đó, mà là **nguyên tắc**: không được clamp/khôi phục `scrollX` cuối cùng cho tới khi biết chắc `maxScrollX` đã đúng (tức sau khi có kích thước viewport thật + data thật) — nếu port có cách đọc layout đồng bộ hơn Flutter (biết ngay `maxScrollX` đúng mà không cần đợi 1 frame), có thể gộp 2 pha thành 1 mà vẫn đúng kết quả cuối, KHÔNG bắt buộc phải giả lập đúng độ trễ 1-frame của Flutter.

**Vì sao cần cờ `suppressScaleCallback`**: nếu không có cờ này, việc PHA 1 gán `scaleX`/`scaleY`/`scrollX` từ prop `chartScale` sẽ (nếu code không cẩn thận) có thể vô tình kích hoạt lại callback `onChartScaleChanged` — tạo vòng lặp phản hồi: `chartScale` (prop) → container tự gán state → phát `onChartScaleChanged` → parent nhận callback → parent cập nhật lại `chartScale` (state của chính parent) → truyền lại `chartScale` prop mới → container lại "thấy đổi" → khôi phục lại → phát callback... Cờ `suppressScaleCallback` đảm bảo: **khôi phục từ prop (đường prop → state) KHÔNG BAO GIỜ tự động phát lại thành callback (đường state → prop)** — 2 chiều này phải tách biệt hoàn toàn. Khi port sang kiến trúc khác (Redux/MobX/StateFlow/Combine...), đây chính là nguyên tắc **"one-way data flow, không echo ngược"**: field/state được set TỪ prop bên ngoài không được kích hoạt lại đúng callback đại diện cho "user vừa tự gesture đổi state" — 2 nguồn cập nhật (từ ngoài vào vs từ gesture ra) phải có cờ/flag phân biệt rõ, nếu không sẽ có nguy cơ vòng lặp vô hạn hoặc chớp giật giữa 2 lần cập nhật cạnh tranh nhau.

---

## 7. Bề mặt API công khai (props / callbacks)

| Tên | Kiểu | Ý nghĩa |
|---|---|---|
| `data` | Candle[]? | Nguồn dữ liệu. Rỗng/null = chart trống. |
| `mainIndicators` | Indicator[] | Danh sách main indicator đang bật, theo thứ tự vẽ. |
| `secondaryIndicators` | Indicator[] | Danh sách secondary indicator đang bật — mỗi phần tử 1 panel riêng theo đúng thứ tự. |
| `volHidden` | boolean | Ẩn hoàn toàn panel volume (chiều cao = 0). |
| `isLine` | boolean | Vẽ line chart thay vì nến. |
| `isTapShowInfoDialog` | boolean | Cho phép tap (không cần long-press) để bật crosshair + popup. |
| `hideGrid` | boolean | Ẩn toàn bộ đường lưới (grid ngang/dọc mọi panel) — reference-lines (vd 20/80 StochRSI) KHÔNG bị ẩn theo cờ này. |
| `showNowPrice` | boolean | Bật/tắt đường + badge giá hiện tại. |
| `livePrice` | number? | Giá tick real-time — xem §6.12. |
| `fixedLength` | int | Số chữ số thập phân hiển thị (định dạng số, §8). |
| `xFrontPadding` | number | Padding phải tối đa (px tại `referenceChartWidth=375`) — xem §3.1. |
| `minScale`, `maxScale` | number | Biên `scaleX`, mặc định `0.2`/`2.2`. |
| `flingTime`, `flingRatio`, `flingCurve` | — | Tham số animation quán tính, §6.9 (chỉ áp dụng cho trục X — xem §6.6 mục 5). |
| `chartScale` | ScaleState? | `{scaleX, scaleY, scrollX}` để khôi phục zoom khi đổi timeframe. |
| `detailBuilder` | `(candle) → View` | Builder cho popup chi tiết khi long-press/tap. |
| `backgroundLogo` | View? | Watermark giữa vùng main chart. |
| `backgroundLogoOpacity` | number (0–1) | Độ mờ watermark. |
| `onLoadMore` | `(bool) → void` | Xem §6.8. |
| `isLoadingMore` | boolean | Chặn spam trigger `onLoadMore` khi đang chờ kết quả trước. |
| `isOnDrag` | `(bool) → void` | Báo trạng thái đang kéo/animation quán tính. |
| `onVerticalOverscroll` | `(number) → void` | Xem §6.6/§6.7. |
| `onChartScaleChanged` | `(ScaleState) → void` | Xem §6.4/§6.10. |
| `controller` | Controller? | `reset()`/`zoomIn()`/`zoomOut()` điều khiển từ ngoài — xem §1. |
| `isTrendLine` | boolean | Bật chế độ vẽ đoạn thẳng xu hướng bằng tap. |
| `timeFormat` | string[]? | Ép format CỐ ĐỊNH cho MỌI tick trục X + label crosshair, bỏ qua hẳn `tickWeight` — xem §3.3 "Format nhãn". `null` (mặc định) = adaptive theo `tickWeight`. |
| `verticalTextAlignment` | enum `left`/`right` | Panel giá (`priceAxisRect`, §4) + badge now-price/crosshair nằm bên trái hay phải. Mặc định `right`. |
| `showInfoDialog`, `materialInfoDialog` | boolean | Bật/tắt popup chi tiết khi long-press/tap, và style Material hay tự custom hoàn toàn qua `detailBuilder`. |
| `mBaseHeight` | number | Chiều cao main chart do caller truyền — input của công thức layout §4. |
| `mSecondaryHeight` | number? | Ép chiều cao mỗi panel volume/secondary — `null` = tự tính `baseHeight × 0.2` (§4). |
| `chartStyle`, `chartColors` | — | Toàn bộ hằng số kích thước + màu sắc — xem §10. |

---

## 8. Định dạng số (number formatting)

**MUST MATCH** — vì đây là phần user nhìn thấy trực tiếp; sai định dạng số làm 2 nền tảng hiển thị 2 con số khác nhau dù tính toán nội bộ giống hệt.

### 8.1 `formatFixed(value, precision)` — dùng cho hầu hết label giá/indicator

```
1. Parse value thành số thập phân CHÍNH XÁC (decimal/BigDecimal — KHÔNG dùng float, tránh sai số + ký hiệu khoa học "1e-10")
2. Tách phần nguyên / phần thập phân
3. Format phần nguyên với dấu phân cách hàng nghìn (",", kiểu en_US: #,##0)
4. Phần thập phân: pad thêm "0" bên phải cho đủ đúng `precision` ký tự, rồi CẮT (không làm tròn) còn đúng `precision` ký tự
5. Nếu precision == 0: chỉ trả phần nguyên (không có dấu chấm)
6. Ghép "integer.fraction"
```

> Đây là **cắt (truncate), không phải làm tròn (round)** — `formatFixed(1.239, 2)` → `"1.23"`, không phải `"1.24"`.

### 8.2 `format(value, precision)` — dùng ở vài chỗ khác (tương tự nhưng lấy fraction trực tiếp từ phép "floor to N decimal" của thư viện decimal, không tự pad tay)

Về hành vi hiển thị: cùng nguyên tắc "cắt, không làm tròn" như §8.1. Khi port, nên coi 2 hàm này là "cùng 1 hợp đồng cắt-không-làm-tròn" và viết unit test so sánh input giống nhau giữa 2 nền tảng thay vì cố tái tạo khác biệt cài đặt nội bộ (vốn chỉ là chi tiết thư viện Dart `Decimal`).

### 8.3 `formatCompact(value, precision=2)` — dùng cho số lớn (volume, OBV...)

```
if value >= 1e9:  return (value/1e9).toFixed(precision) + "B"
if value >= 1e6:  return (value/1e6).toFixed(precision) + "M"
if value >= 1e4:  return (value/1e3).toFixed(precision) + "K"   // ⚠️ NGƯỠNG so sánh là 1e4 nhưng CHIA cho 1e3
else:              return value.toFixed(precision)
```

> **Chi tiết dễ port sai**: ngưỡng bật hậu tố `"K"` là `>= 10,000`, nhưng số **chia** cho hậu tố K là `1,000` (không phải `10,000`). Hệ quả: `9999` → `"9999.00"` (giữ nguyên, KHÔNG có hậu tố K); `15234` → `"15.23K"`. Nếu lỡ chia cho `1e4` thay vì `1e3`, mọi số hiển thị compact sẽ sai một hệ số 10.

### 8.4 `checkNotNullOrZero(value)`

```
return value != null AND value != 0 AND round(|value|, 4 chữ số thập phân) != "0.0000"
```

Dùng để quyết định có hiển thị 1 label optional hay không (vd label MA5Volume chỉ hiện nếu giá trị "có ý nghĩa", không phải chỉ khác 0 theo nghĩa float tuyệt đối).

---

## 9. Catalogue công thức indicator (20 indicator)

Mọi công thức dưới đây lấy **verbatim** từ `calc()` trong source — kể cả những chỗ có vẻ bất thường/không đối xứng, phải copy nguyên để hành vi giống hệt Flutter (đánh dấu rõ những chỗ này bằng ⚠️).

### 9.1 Main indicators (vẽ chồng lên main chart)

#### MA — Moving Average
- `calcParams = [5, 10, 30, 60]` (nhiều đường cùng lúc)
- Với mỗi chu kỳ `p`, dùng rolling-sum (cộng dồn, trừ giá trị rơi ra khỏi cửa sổ) — KHÔNG tính lại tổng từ đầu mỗi nến:
```
sum[p] += close[i]
if i == p-1:  value = sum[p] / p
elif i >= p:  sum[p] -= close[i-p];  value = sum[p] / p
else:          value = 0            // ⚠️ sentinel 0, KHÔNG PHẢI null — vẽ line có gate "!= 0" để bỏ qua đoạn warm-up
```
- Output: `maValueList[j]` song song `calcParams`.

#### EMA — Exponential Moving Average
- `calcParams = [5, 10, 30, 60]`
- `multiplier = 2/(p+1)`
```
i == 0: ema[p] = close[0]                                   // seed = close đầu tiên, GIỐNG NHAU cho mọi chu kỳ p
i > 0:  ema[p] = (close[i] - ema[p]) * multiplier + ema[p]
```
- Output: `emaValueList[j]`. (Vẽ cũng dùng gate `!= 0` sao chép từ MA dù EMA gần như không bao giờ bằng 0 chính xác — vô hại nhưng copy nguyên cho khớp.)

#### BOLL — Bollinger Bands
- `calcParams = [20, 2]` (chu kỳ n, số độ lệch chuẩn k)
```
bollMa (rolling SMA n, giống MA ở trên, null khi i < n-1)
khi i >= n:
    md = sqrt( Σ (close[j] - bollMa[i])² với j in [i-n+1..i] ) / (n-1) )   // dùng bollMa CỦA CHÍNH NẾN i (không phải per-j)
    mid = bollMa[i];  up = mid + k*md;  dn = mid - k*md
```
- Output: `{up, mid, dn, bollMa}`, null cho tới `i >= n`.

#### SAR — Parabolic Stop And Reverse
- `calcParams = [2, 2, 20]` → `startAf=0.02, step=0.02, maxAf=0.20` (chia 100)
- State: `af` (acceleration factor), `ep` (extreme point, sentinel khởi tạo `-100` = "chưa set"), `isIncreasing` (bool, khởi tạo `false`), `sar` (khởi tạo `0`)

```
for i in 0..n-1:
    preSar = sar
    if isIncreasing:                                    // uptrend
        if ep == -100 or ep < high[i]: ep = high[i]; af = min(af+step, maxAf)
        sar = preSar + af*(ep - preSar)
        lowMin = min(low[max(1,i)-1], low[i])           // i=0 dùng low[0]; i>=1 dùng low[i-1]
        if sar > low[i]:
            sar = ep; af = startAf; ep = -100; isIncreasing = false    // ⚠️ reset af = startAf khi ĐẢO SANG downtrend
        elif sar > lowMin: sar = lowMin
    else:                                                 // downtrend
        if ep == -100 or ep > low[i]: ep = low[i]; af = min(af+step, maxAf)
        sar = preSar + af*(ep - preSar)
        highMax = max(high[max(1,i)-1], high[i])
        if sar < high[i]:
            sar = ep; af = 0; ep = -100; isIncreasing = true            // ⚠️ reset af = 0 (KHÔNG PHẢI startAf) khi ĐẢO SANG uptrend
        elif sar < highMax: sar = highMax
    candle[i].sar = sar
```

> ⚠️ **Bất đối xứng phải giữ nguyên**: khi đảo chiều downtrend→uptrend, `af` reset về `0`, còn khi đảo chiều uptrend→downtrend, `af` reset về `startAf` (`0.02`). Đây gần như chắc chắn là quirk trong code gốc (2 nhánh lẽ ra nên đối xứng), nhưng **phải copy y hệt** để đường SAR khớp pixel-for-pixel với Flutter. Nếu "sửa cho đúng lý thuyết" (luôn reset về `startAf`), kết quả sẽ trôi khác dần theo thời gian.
- Output: `sar` — không bao giờ null từ nến đầu.
- Màu: `sar <= (high+low)/2` → `upColor`, ngược lại → `dnColor`.

#### ZigZag
- `calcParams = [12, 2, 5]` = (depth, backstep, deviation — deviation **không được dùng** trong code hiện tại)
- Thuật toán 3 bước:
```
BƯỚC 1 — đánh dấu local high/low:
  với mỗi i >= depth: candle[i] là "local high" nếu high[i] >= high[i-k] với mọi k in [1..depth]
                       VÀ không bị phá bởi high[i+k] > high[i] với k in [1..backstep] (nếu i+k còn trong mảng)
                       (tương tự cho "local low" với low, đảo dấu so sánh)

BƯỚC 2 — nối các pivot xen kẽ cao/thấp:
  tìm pivot ĐẦU TIÊN (high hoặc low, ưu tiên cái xuất hiện trước theo thời gian)
  duyệt tiếp: nếu đang ở pivot High, pivot hợp lệ tiếp theo phải là Low
    - nếu gặp CẢ high VÀ low mới tại cùng candle: nếu high mới CAO HƠN high pivot hiện tại → cập nhật (nối dài) pivot High hiện tại
      ngược lại → chốt pivot High hiện tại, bắt đầu pivot Low mới
    - nếu chỉ gặp high mới cao hơn (không kèm low) → cập nhật nối dài pivot High
    (đối xứng ngược lại khi đang ở pivot Low)

BƯỚC 3 — nội suy tuyến tính:
  giữa 2 pivot liên tiếp (idx1,val1) và (idx2,val2): candle[idx1].zigzag = val1; candle[idx2].zigzag = val2
  các candle giữa: zigzag = val1 + (val2-val1)/(idx2-idx1) * (j - idx1)
  candle trước pivot đầu tiên và sau pivot cuối cùng: zigzag = null
```
- Output: `zigzag` — null ngoài chuỗi pivot, reset về null toàn bộ mỗi lần `calc()` chạy lại.

#### SuperTrend
- `calcParams = [10, 30]` → `period=10, multiplier = 30/10 = 3.0`
```
TR[i] = i==0 ? (high-low) : max(high-low, |high-prevClose|, |low-prevClose|)
warm-up (i < period): cộng dồn sumTR; tại i==period-1: atr = sumTR/period (seed = SMA)
từ i >= period:
    atr = (atr*(period-1) + TR[i]) / period                       // Wilder smoothing (RMA)
    mid = (high+low)/2
    basicUpper = mid + multiplier*atr;  basicLower = mid - multiplier*atr
    finalUpper = (prevFinalUpper==null OR basicUpper<prevFinalUpper OR prevClose>prevFinalUpper) ? basicUpper : prevFinalUpper
    finalLower = (prevFinalLower==null OR basicLower>prevFinalLower OR prevClose<prevFinalLower) ? basicLower : prevFinalLower
    isUp = prevSuperTrendValue==null ? (close>finalUpper)
           : (prevSuperTrendValue==prevFinalUpper ? (close>finalUpper) : (close>=finalLower))
    value = isUp ? finalLower : finalUpper
```
- Output: `{value, isUp}`, null cho tới `i >= period`.

#### AVL — Average Value Line (kiểu Binance)
- Không có `calcParams`.
```
avl = (amount != null AND amount > 0 AND vol > 0) ? amount/vol : (high+low+close)/3   // fallback = typical price
```
- Output: `avl` — không bao giờ null.

#### Ichimoku Kinko Hyo
- `calcParams = [9, 26, 52]` (tenkanPeriod, kijunPeriod, spanBPeriod) — bộ cổ điển; crypto thường dùng `[20, 60, 120]`.
- `shift = calcParams[1]` — **LUÔN bằng kijun period, không hardcode `26`.** Đổi `calcParams[1]` thì `shift` (và vùng tương lai cần chừa, §3.5) tự đổi theo.
- `HH(p)`/`LL(p)` = cao/thấp nhất trong `p` nến gần nhất tính tới nến hiện tại (bao gồm nến hiện tại) — dùng **sliding-window monotonic deque, O(n)** cho cả 3 chu kỳ (KHÔNG vòng lặp naive `O(n×p)` — chart vài nghìn nến sẽ giật khi pan/zoom nếu tính lại từ đầu mỗi lần):
```
tenkan[i] = i >= tenkanP-1 ? (HH(tenkanP)[i] + LL(tenkanP)[i]) / 2 : null
kijun[i]  = i >= kijunP-1  ? (HH(kijunP)[i]  + LL(kijunP)[i])  / 2 : null
spanA[i]  = (tenkan[i] != null AND kijun[i] != null) ? (tenkan[i] + kijun[i]) / 2 : null   // cần CẢ 2 sẵn sàng
spanB[i]  = i >= spanBP-1 ? (HH(spanBP)[i] + LL(spanBP)[i]) / 2 : null
// chikou KHÔNG lưu field riêng — luôn = close[i], dịch ở draw-time (xem dưới)
```
- Output: `ichimoku: {tenkan, kijun, spanA, spanB}` — mỗi field null độc lập cho tới đủ chu kỳ tương ứng, tính TẠI INDEX TỰ NHIÊN của nến (không dịch trong dữ liệu lưu trữ).
- **Vẽ (draw-time, KHÔNG phải trong `calc()`)** — đây là phần khác biệt so với mọi indicator khác trong bảng này, chi tiết đầy đủ ở §3.5:
```
Tenkan/Kijun:    vẽ tại (lastX, curX)                      — không dịch
Senkou Span A/B: vẽ tại (lastX + shift*pointWidth, curX + shift*pointWidth)   — dịch TỚI TRƯỚC
Chikou:          vẽ tại (lastX - shift*pointWidth, curX - shift*pointWidth), y = close  — dịch LÙI, không warm-up riêng
```
- **Kumo (mây)** = vùng tô giữa Span A/B (đã dịch). Tô 2 màu theo `spanA vs spanB`; nếu dấu hiệu (`spanA - spanB`) đổi giữa `lastPoint`/`curPoint` (2 đường cắt nhau giữa 2 nến liền kề) → **PHẢI** tách polygon tại điểm giao (nội suy tuyến tính theo tỉ lệ `t = lastDiff / (lastDiff - curDiff)`), tô 2 nửa 2 màu riêng — tô nguyên polygon 1 màu sẽ sai màu ở đoạn giao.
- `futureShift = shift` — indicator ĐẦU TIÊN khai báo giá trị này > 0 trong `MainIndicator` (mặc định `0`), kích hoạt toàn bộ cơ chế mở rộng trục X ở §3.5.

### 9.2 Secondary indicators (panel riêng bên dưới)

#### MACD
- `calcParams = [12, 26, 9]` (short, long, signal)
- ⚠️ **Không phải EMA chuẩn từ i=0** — dùng kỹ thuật seed = SMA rồi chuyển sang EMA:
```
closeSum cộng dồn từ i=0
emaShort: tại i == short-1: emaShort = closeSum/short (seed=SMA); tại i > short-1: emaShort = (2*close + (short-1)*emaShort) / (short+1)
           // ⚠️ công thức này TƯƠNG ĐƯƠNG EMA chuẩn multiplier=2/(short+1), chỉ viết dạng khác — verify: = emaShort + 2/(short+1)*(close-emaShort)
emaLong: tương tự với long, bắt đầu từ i == long-1
dif = emaShort - emaLong, chỉ tính từ i >= max(short,long)-1; difSum cộng dồn dif
dea: tại i == max(short,long)+signal-2: dea = difSum/signal (seed=SMA của dif); sau đó: dea = (dif*2 + dea*(signal-1))/(signal+1)
macd(histogram) = (dif - dea) * 2      // chỉ có giá trị từ khi dea bắt đầu
```
- Output: `dif` (từ `i >= max(short,long)-1`), `dea`/`macd` (từ `i >= max(short,long)+signal-2`).
- Vẽ: histogram màu `upColor` nếu `macd>0` ngược lại `dnColor`; style **outline (stroke)** nếu `macd` hiện tại ≥ macd nến trước, ngược lại **fill đặc** — quy ước hiển thị "tăng/giảm động lượng so với nến ngay trước", không phải chuẩn 4-màu TradingView.

#### KDJ
- Không expose `calcParams` (hard-code nội bộ): cửa sổ RSV = 9 nến, hệ số smoothing 1/3–2/3.
```
nến đầu tiên: k=d=j=50  (hằng số cố định, không tính)
từ i=1:
    window = [i-8 .. i] (tối đa 9 nến, co lại ở đầu mảng)
    rsv = (close[i] - low(window)) * 100 / (high(window) - low(window))   // NaN guard → 0
    k = (2*prevK + rsv)/3;  d = (2*prevD + k)/3;  j = 3k - 2d
```
- Output: `k,d,j` — không bao giờ null.
- Label trục Y hiển thị 2 mốc cố định `80`/`20` (chỉ khi nằm trong range hiển thị) — không phải dashed reference-line đầy đủ như StochRSI.

#### RSI
- `calcParams = [6, 12, 24]` khai báo **NHƯNG `calc()` bỏ qua hoàn toàn, hard-code chu kỳ 14** (Wilder). ⚠️ Chỉ 1 đường được vẽ, không phải 3 đường theo params.
```
rMax = max(0, close[i]-close[i-1]);  rAbs = |close[i]-close[i-1]|
rsiMaxEma = (rMax + 13*rsiMaxEma) / 14      // Wilder, seed 0 tại i=0
rsiAbsEma = (rAbs + 13*rsiAbsEma) / 14
rsi = rsiMaxEma / rsiAbsEma * 100
null khi i < 13 (giá trị hợp lệ đầu tiên tại i=13, tức nến thứ 14)
```

#### WR — Williams %R
- `calcParams = [26, 6]` khai báo **NHƯNG `calc()` hard-code cửa sổ 14 nến** — cùng kiểu discrepancy như RSI. ⚠️ Window thực tế dùng `i-14..i` (inclusive) = **15 nến**, không phải 14.
```
window = [max(0,i-14) .. i]
r = -100 * (max(window.high) - close[i]) / (max(window.high) - min(window.low))
i < 13: r = -10   // ⚠️ sentinel -10, KHÔNG PHẢI null
NaN → null
```
- `getMaxMinValue` LUÔN trả range cố định `(-100, 0)` bất kể data thực tế (không auto-scale theo dữ liệu).

#### CCI — Commodity Channel Index
- `calcParams = [20]`
```
tp[i] = (high+low+close)/3
từ i >= period-1:
    maTp = SMA(tp, period)   // rolling sum
    md = mean(|tp[j]-maTp|) với j trong window period
    cci = md != 0 ? (tp[i]-maTp)/md/0.015 : 0
```
- Null trước `i >= period-1`.

#### OBV — On-Balance Volume
- `calcParams = [5]` (chu kỳ MA signal)
```
obv[0] = vol[0]
obv[i] = obv[i-1] + vol[i]   nếu close[i] > close[i-1]
obv[i] = obv[i-1] - vol[i]   nếu close[i] < close[i-1]
obv[i] = obv[i-1]             nếu bằng nhau
signal = SMA(obv, 5), null cho tới khi đủ 5 giá trị
```
- `obv` không bao giờ null; `signal` null cho tới `i >= period-1`.

#### TRIX
- `calcParams = [12, 20]` (N chu kỳ EMA×3, M chu kỳ MA tín hiệu)
```
multiplier = 2/(N+1)
i==0: ema1=ema2=ema3=close[0]   // seed CẢ 3 tầng bằng close đầu tiên (không warm-up riêng từng tầng)
i>0:  ema1 = (close-ema1)*mult+ema1
       ema2 = (ema1-ema2)*mult+ema2
       ema3 = (ema2-ema3)*mult+ema3
trix = (prevEma3 != null AND prevEma3 != 0) ? (ema3-prevEma3)/prevEma3*100 : null   // null tại i=0 (chưa có prevEma3)
trixMa = SMA(trix, M) qua sliding window (chỉ đếm các giá trị trix không null)
```

#### MTM — Momentum
- `calcParams = [12, 6]` (N độ trễ, M chu kỳ MA tín hiệu)
```
mtm[i] = i >= N ? close[i] - close[i-N] : null
mtmMa = SMA(mtm, M) sliding window (chỉ đếm giá trị mtm không null)
```

#### StochRSI
- `calcParams = [14, 14, 3, 3]` (N1 chu kỳ RSI nội bộ, N2 chu kỳ Stoch, M1 smooth %K, M2 smooth %D)
- ⚠️ **RSI tính ĐỘC LẬP, không dùng lại `RSIIndicator`/field `rsi`** — và cách seed cũng KHÁC RSI ở trên:
```
với i trong [1..N1]: avgGain += gain[i]/N1;  avgLoss += loss[i]/N1     // trung bình cộng đơn giản trong lúc warm-up
từ i > N1: avgGain = (avgGain*(N1-1)+gain[i])/N1  (Wilder, giống RSI thường TỪ THỜI ĐIỂM NÀY)
rsi (từ i >= N1):
    if avgGain==0 AND avgLoss==0: rsi = 50            // thị trường đi ngang tuyệt đối → neutral, KHÔNG PHẢI 100
    elif avgLoss==0: rsi = 100
    else: rsi = 100 - 100/(1+avgGain/avgLoss)

stoch (khi đủ N2 giá trị rsi trong sliding window):
    range = max(rsiWindow) - min(rsiWindow)
    stoch = range==0 ? 0 : (rsi - min(rsiWindow))/range * 100        // range=0 (RSI đi ngang tuyệt đối) → 0, quy ước TradingView

%K = SMA(stoch, M1) sliding window
%D = SMA(%K, M2) sliding window
```
- Vẽ kèm **2 đường tham chiếu nét đứt cố định `20`/`80`** (không phụ thuộc data) — panel auto-scale Y PHẢI luôn bao gồm cả `[20,80]` dù dữ liệu không chạm tới, để 2 vạch này không bao giờ bị cắt khỏi khung nhìn.

#### BRAR
- `calcParams = [26]`
- ⚠️ 2 cặp rolling-sum bắt đầu **KHÁC thời điểm nhau**:
```
sumHO = Σ(high-open, n) — bắt đầu tích luỹ từ i=0
sumOL = Σ(open-low, n)  — bắt đầu tích luỹ từ i=0
sumHC = Σ max(0, high - prevClose, n) — CHỈ bắt đầu tích luỹ từ i=1 (cần prevClose)
sumCL = Σ max(0, prevClose - low, n)   — CHỈ bắt đầu tích luỹ từ i=1

ar = (window HO/OL đã đầy n phần tử, tức i >= n-1) ? (sumOL==0 ? 0 : sumHO/sumOL*100) : null
br = (window HC/CL đã đầy n phần tử, tức i >= n, TRỄ HƠN ar ĐÚNG 1 NẾN) ? (sumCL==0 ? 0 : sumHC/sumCL*100) : null
```
- ⚠️ **`ar` và `br` bắt đầu có giá trị ở 2 chỉ số khác nhau** (`ar` tại `i=n-1`, `br` tại `i=n`) — do `sumHC`/`sumCL` khởi động trễ 1 nến. Phải giữ đúng độ trễ lệch này.

#### BIAS
- `calcParams = [6, 12, 24]` (nhiều chu kỳ cùng lúc, không giới hạn đúng 3 phần tử — giống MA)
```
với mỗi chu kỳ p: ma = rolling SMA(close, p)   // null khi i < p-1
bias(p) = (i >= p-1) ? (ma==0 ? 0 : (close-ma)/ma*100) : null    // dùng null, KHÔNG dùng sentinel 0 như MA
```

#### PSY — Psychological Line
- `calcParams = [12, 6]` (N cửa sổ đếm phiên tăng, M chu kỳ MA tín hiệu)
```
từ i >= 1: đẩy boolean (close[i] > close[i-1]) vào sliding window kích thước N
psy = (window đã đầy N phần tử, tức i >= N) ? (số true trong window)/N * 100 : null
psyMa = SMA(psy, M) sliding window
```

---

## 10. Style / màu sắc — hằng số mặc định

Không bắt buộc phải khớp 100% để "chạy đúng", nhưng cần khớp để **nhìn giống hệt** Flutter mặc định. Bảng màu mặc định (hex ARGB):

| Vai trò | Màu |
|---|---|
| Nến tăng (`upColor`) | `#FF14AD8F` (xanh ngọc) |
| Nến giảm (`dnColor`) | `#FFD5405D` (đỏ) |
| Line chart | `#FF217AFF` (xanh dương) |
| Volume MA5 | `#FFFFC634` (vàng) |
| Volume MA10 | `#FF35CDAC` (xanh ngọc nhạt) |
| Text mặc định | `#FF909196` (xám) |
| Grid | `#FFD1D3DB` (xám nhạt) |
| Crosshair | `#FF191919` |
| Nền chart | `#FFFFFFFF` (trắng — theme sáng mặc định) |

Mỗi indicator có style riêng (đường/màu label) — bảng đầy đủ 20 indicator × màu mặc định nằm trong `indicator.md`/`lib/indicator/indicator_style.dart` của repo Flutter gốc, dùng làm nguồn tham chiếu khi cần khớp pixel màu sắc.

Hằng số kích thước quan trọng khác: `crossWidth=0.8`, `nowPriceLineWidth=0.8`, `borderWidth=0.5` (viền badge/crosshair selector).

2 đường phân cách khung strip trục giá (§4 `drawAxisSeparators`, dọc tại `x=plotWidth` + ngang tại `y=dateRect.top`) dùng LẠI đúng màu `Grid` ở trên (`gridColor`), `strokeWidth=0.5` — không phải màu/hằng số riêng.

---

## 11. DepthChart — widget độc lập

`DepthChart` **không** chia sẻ state với chart chính — port thành component riêng biệt.

### 11.1 Input
```
bids: DepthEntity[]   // giá tốt nhất → xa dần (giảm dần), vol = CUMULATIVE
asks: DepthEntity[]   // giá tốt nhất → xa dần (tăng dần), vol = CUMULATIVE
```

### 11.2 Layout & toạ độ
```
drawWidth  = width / 2         // nửa trái = bids, nửa phải = asks
drawHeight = height - 32       // 32px padding đáy cho label giá

maxVolume = max(bids[0].vol, asks.last.vol) * 1.08     // +8% headroom để đường không chạm sát mép trên

getY(vol) = drawHeight - drawHeight * vol / maxVolume    // vol=0 → đáy panel; vol=maxVolume → gần đỉnh

// bids: điểm i vẽ tại x = i * (drawWidth / (bids.length-1))          — trái → phải, index 0 ở x=0
// asks: điểm i vẽ tại x = drawWidth + i * (drawWidth / (asks.length-1))  — bắt đầu từ giữa, tiến sang phải
```

Đường nối giữa các điểm dùng **quadratic bezier** (không phải đường thẳng) để mượt hơn; vùng dưới đường tô đặc (fill) tới `drawHeight`.

### 11.3 Label trục
```
// Trục Y (bên phải): 4 mốc volume, đều nhau: value = maxVolume - (maxVolume/4)*j, j=0..3
// Trục X (dưới): bottomLabelCount mốc giá (mặc định 5), nội suy tuyến tính 2 đoạn:
//   nửa trái [0, 0.5]:  price = startPrice + (centerPrice - startPrice) * (t*2)
//   nửa phải [0.5, 1]:  price = centerPrice + (endPrice - centerPrice) * ((t-0.5)*2)
//   với startPrice = bids[0].price, endPrice = asks.last.price, centerPrice = (bids.last.price + asks[0].price)/2
```

### 11.4 Gesture — chỉ có long-press (không pan/zoom)

```
onLongPressStart/Move: xác định index gần nhất với vị trí chạm (binary search theo x, giống chart chính),
    nếu chạm nửa trái → tra cứu phía bids VÀ tính đối xứng phía asks (indexRight = bids.length - index - 1) để hiển thị CẢ HAI popup cùng lúc
    nếu chạm nửa phải → ngược lại
onLongPressEnd: ẩn popup
```

Mỗi popup hiển thị `price` + `amount` (dùng `formatCompact`, §8.3) của mức giá được chọn, kèm 1 lớp overlay "barrier" phủ mờ phần bên ngoài điểm chọn (để nhấn mạnh vùng đang xem) và 1 đường dashed thẳng đứng qua điểm chọn.

---

## 12. Checklist parity khi port

Danh sách nên viết test đối chiếu số/giá trị (golden test) giữa Flutter gốc và bản port, KHÔNG chỉ test "chạy không crash":

- [ ] Với cùng 1 bộ candle cố định (fixture dùng chung mọi nền tảng), export JSON kết quả `calc()` của cả 20 indicator từ bản Flutter gốc → assert bản port ra đúng từng field, từng index, kể cả các field còn `null`/sentinel `0` ở đúng vị trí warm-up (đặc biệt: SAR §9.1 af-asymmetry, MACD SMA-seed, StochRSI seed khác RSI thường, BRAR ar/br lệch 1 nến, RSI/WR hard-code period 14 dù params khai báo khác, Ichimoku spanA cần cả tenkan+kijun sẵn sàng).
- [ ] Test riêng Ichimoku (§3.5/§9.1) — mây (Span A/B) hiển thị dịch tới trước đủ `shift` nến bên phải nến cuối, KHÔNG bị cắt cụt kể cả khi đã scroll/pan tới sát mép phải; Chikou dừng đúng trước nến cuối `shift` slot; đổi `calcParams[1]` (kijun) → vùng tương lai chừa ra tự đổi theo, không hardcode `26`.
- [ ] Test 3 phạm vi index của §3.5 KHÔNG bị lẫn: label max/min giá + autoscale trục Y (main/volume/secondary) + label chỉ số góc trên CHỈ được phản ánh nến đang thực sự hiển thị (`visibleStartIndex..visibleStopIndex`) — bật 1 indicator có `futureShift > 0`, scroll tới giữa lịch sử (không phải mép mới nhất), xác nhận các label/autoscale này KHÔNG bị ảnh hưởng bởi nến nằm ngoài viewport (dù nến đó vẫn nằm trong vùng "real" mở rộng dùng để vẽ). Đây là lớp bug dễ tái phát nhất khi thêm indicator dịch trục thứ 2 trong tương lai.
- [ ] Test chart có `itemCount < shift` (chưa đủ nến cho Ichimoku warm-up đầy đủ) — không vẽ đường/mây rác kéo về 0, và cơ chế mở rộng trục X (`mFutureSlots`) không tạo ra state bất thường khi hầu như toàn bộ mảng vẫn `null`.
- [ ] Với cùng chuỗi gesture ghi lại (sequence các `dx/dy/scale/pointerCount` theo thời gian), assert `scaleX/scrollX/scaleY/offsetY` cuối cùng khớp — đặc biệt test case chạm vùng phải (dải `priceAxisWidth`, §4 — KHÔNG PHẢI `effectiveRightPaddingPx`) VÀ trong khoảng `y ∈ [0, mainRect.bottom]` để kích hoạt đúng `isScaleYGesture` (§6.4); test thêm case chạm ĐÚNG cột X đó nhưng `y > mainRect.bottom` (ngang hàng volume/secondary) — PHẢI KHÔNG kích hoạt `isScaleYGesture`.
- [ ] Test `effectiveRightPaddingPx` với vài `mPlotWidth` khác reference (< 375px) — đảm bảo tỷ lệ co giãn đúng (đây là công thức padding scroll ở §3.1, tham số truyền vào giờ là `mPlotWidth` chứ không phải full canvas width — khác zone test ở dòng trên).
- [ ] Test 4 trigger `onLoadMore` (§6.8) độc lập, đặc biệt trigger (d) — mount với data ít hơn 1 màn hình, không gesture nào, vẫn phải tự bắn `onLoadMore(true)` đúng 1 lần (không lặp lại khi re-render không đổi độ dài data).
- [ ] Test `formatCompact` quanh ngưỡng `9999`/`10000`/`999999`/`1000000` để bắt lỗi nhầm số chia (§8.3).
- [ ] Test layout heights (§4) với tổ hợp `volHidden × số main indicator × số secondary indicator` khác nhau — đối chiếu từng rect top/bottom.
- [ ] Test `priceAxisWidth` (§4): đổi giá trị label giá qua ngưỡng dài/ngắn nhiều lần liên tục trong vài frame liền — xác nhận có **hysteresis** (chỉ THU khi thấp hơn hẳn 1 bậc 8px, PHÌNH áp ngay) và **trễ đúng 1 frame** (frame vừa đo label rộng hơn KHÔNG được co giãn `plotWidth` ngay lập tức trong CHÍNH frame đó). Test riêng: zoom vào để nến/volume/secondary đè lên `priceAxisRect` (nếu thiếu clip §3.1/§4 sẽ thấy đè trước khi "biến mất" khi scroll — lớp bug đã gặp thật, KHÔNG chỉ lý thuyết).
- [ ] Test weight-ladder tick trục X (§3.3): pan (đổi `scrollX`, giữ nguyên `scaleX`) KHÔNG được đổi tick nào đang được chọn (invariant I4) — chỉ đổi tick nào đang lọt viewport `[0, plotWidth]`. Test riêng zoom liên tục (đổi `barSpacing` mỗi frame) — không có 2 tick liền kề nào cách nhau dưới `MIN_GAP_X=64px`, và trục KHÔNG BAO GIỜ trắng hoàn toàn (fallback "never blank").
- [ ] Test màu nến doji (`open == close`) rơi vào nhánh `upColor` (§4, "vẽ nến").
- [ ] Test `scaleY`/`offsetY` KHÔNG ảnh hưởng panel volume/secondary (chỉ ảnh hưởng main) — regression dễ xảy ra nhất khi port canvas transform sang nền tảng không có ma trận transform composable.
- [ ] Test riêng: set `scaleY != 1` (hoặc `offsetY != 0`) rồi bật crosshair/trend-line (§3.4) — xác nhận bản port cố ý chọn 1 trong 2 hành vi (giữ nguyên quirk "crosshair lệch theo Y" của Flutter gốc, hoặc chủ động fix bằng `_applyScaleY`) chứ không lệch ngẫu nhiên do vô tình bỏ sót.
- [ ] Đối chiếu bảng §3.4 với implementation thật của bản port: mỗi hàng phải khớp đúng cột `scaleX`/`scaleY` (đặc biệt: volume/secondary panel tuyệt đối không dính `scaleY`; label trục Y/max-min/now-price phải tính đúng theo `scaleY` dù vẽ ở screen space).
- [ ] Test dead-zone khi pinch (§6.5-A): pinch vượt `maxScale`, đảo hướng ngay lập tức — `scaleX` phải ĐỨNG YÊN ở `maxScale` cho tới khi ngón tay "undo" đủ khoảng đã pinch quá đà, KHÔNG được giảm ngay lập tức. Làm tương tự ở biên `minScale`. Test riêng trên Android (nếu port dùng `ScaleGestureDetector`) vì đây là nền tảng duy nhất cần tự cộng dồn cumulative ratio thủ công (§6.5 bảng đối chiếu) — nếu bỏ qua, zoom trên Android sẽ "mượt" hơn Flutter một cách sai lệch.
- [ ] Test scaleY/scrollX KHÔNG có dead-zone (§6.5-B): kéo `scrollX` chạm `maxScrollX`, đảo hướng ngay — phải di chuyển ngược lại NGAY LẬP TỨC (không dead-zone). Tương tự cho `scaleY` ở biên `[0.3, 5.0]`.
- [ ] Test `controller.reset()` CHỈ đổi `scaleX`/`scrollX`/`selectX`, giữ nguyên `scaleY`/`offsetY`; double-tap CHỈ đổi `scaleY`/`offsetY`, giữ nguyên `scaleX`/`scrollX` (§6.5-C) — 2 action reset không được lẫn trục.
- [ ] Test khôi phục `chartScale` (§6.13): truyền cùng giá trị `{scaleX,scaleY,scrollX}` nhưng KHÁC instance ở mỗi lần re-render cha — xác nhận state nội bộ KHÔNG bị snap-back liên tục (so sánh phải theo VALUE, không theo reference). Test riêng trường hợp restore lúc data/kích thước chưa layout xong — `scrollX` cuối cùng phải khớp giá trị đã lưu sau khi layout ổn định, không bị kẹt ở giá trị clamp tạm thời ban đầu.
- [ ] Test restore từ `chartScale` KHÔNG tự phát lại `onChartScaleChanged` (§6.13) — nếu port thiếu cờ suppress tương đương, dễ tạo vòng lặp phản hồi vô hạn giữa parent/container khi cả 2 phía đều tự động đồng bộ state qua nhau.
- [ ] Test điểm neo khi pinch (§6.5): pinch-zoom trong lúc đã cuộn sang trái (xem nến cũ, không phải nến mới nhất) — xác nhận điểm neo LUÔN là mép phải chart (`chartWidth - effectiveRightPaddingPx`), KHÔNG phải điểm giữa 2 ngón tay. Nến dưới ngón tay phải "trôi" trong lúc zoom, không đứng yên.
