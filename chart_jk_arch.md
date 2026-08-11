# k_chart_jk — Tài liệu tổng hợp

> Tổng hợp từ: `HANDBOOK.md`, `chart_jk.md`, `chart_plush.md`, `CHANGELOG.md`, `chart_jk_arch.md`.

---

## Mục lục

1. [Changelog](#1-changelog)
2. [Tổng quan kiến trúc](#2-tổng-quan-kiến-trúc)
3. [Cài đặt & Quick Start](#3-cài-đặt--quick-start)
4. [Entry point & exports](#4-entry-point--exports)
5. [Entity — data models](#5-entity--data-models)
6. [KChartWidget — API đầy đủ](#6-kchartwidget--api-đầy-đủ)
7. [KChartController](#7-kchartcontroller)
8. [KChartStyle & KChartColors](#8-kchartstyle--kchartcolors)
9. [Indicators — main & secondary](#9-indicators--main--secondary)
10. [DataUtil & helpers](#10-datautil--helpers)
11. [DepthChart — orderbook depth](#11-depthchart--orderbook-depth)
12. [Renderer internals](#12-renderer-internals)
13. [Gesture model](#13-gesture-model)
14. [Recipes — công thức thường dùng](#14-recipes--công-thức-thường-dùng)
    - [14.10 Real-time WebSocket price ticker](#1410-real-time-websocket-price-ticker)
15. [Troubleshooting & pitfalls](#15-troubleshooting--pitfalls)
16. [Phân tích cơ chế Y Grid & Anchor Zoom (MEXC / TradingView)](#16-phân-tích-cơ-chế-y-grid--anchor-zoom-mexc--tradingview)

---

## 1. Changelog

### Unreleased

- **fix:** `drawDate()` đổi sang **clip canvas** thay vì kẹp text vào trong màn hình (cách cũ, xem bullet '"dính cứng" ở 2 đầu mép' bên dưới — vẫn đúng lý do gốc, nhưng cách khắc phục giờ khác). Giờ `canvas.clipRect(0, mDateRect.top, mPlotWidth, mDateRect.bottom)` rồi vẽ label ở ĐÚNG `tick.x` thật, không dịch, không điều kiện fit — canvas tự cắt phần thừa khi label trượt qua mép, **y hệt cách nến/cột volume đã luôn được clip khi ra khỏi viewport** — không còn khái niệm ẩn/hiện, chỉ có trượt vào/ra liên tục.
  - File: `lib/renderer/chart_painter.dart`
- **fix (test, đi kèm entry "tắt hết indicator mặc định"):** `example/test/persistent_isolate_test.dart` assertion khớp lại đúng `_kIndicatorsEnabledByDefault = false` hiện tại của `ChartBloc` — toggle nghĩa là BẬT (`contains`), không phải TẮT (`isNot(contains)`).
  - File: `example/test/persistent_isolate_test.dart`
- **perf/fix (từ `/code-review` trên diff trục X/Y):** 4 vấn đề phát hiện qua code review — 2 performance, 2 correctness — đều đã sửa, KHÔNG đổi thuật toán/output hiển thị đã chốt ở bullet bên dưới, không đụng indicator nào.
  - **perf — cache tick thời gian rescan toàn dataset gần như mỗi frame lúc pinch-zoom:** `TimeTickPlanner`'s cache key có `barSpacing` dạng số thực, đổi liên tục theo `scaleX` trong lúc zoom → cache-miss gần như mỗi frame → rebuild lại `buildTimeTickPlan` trên TOÀN BỘ dataset (alloc `DateTime`/nến trong `_assignTickWeights`), đúng lúc cần mượt nhất. Sửa: làm tròn `barSpacing` về px nguyên CHỈ trong cache key (giá trị chính xác vẫn dùng để build khi thật sự rebuild) — sai lệch dưới 1px không đổi tick nào được chọn trong thực tế (`SURPLUS=4` ở threshold đã chừa biên an toàn).
  - **perf — `MainRenderer.measureMaxLabelWidth` dựng lại `TextPainter` + `layout()` mỗi frame** dù range giá/style không đổi. Sửa: thêm `_priceLabelCache` (`static final Map<(String, TextStyle), TextPainter>`, an toàn dùng chung process vì là hàm THUẦN của input) — dùng lại cho cả `measureMaxLabelWidth` lẫn `drawVerticalText`. Đúng khuyến nghị "Cache laid-out text by (string, colour, size, weight)" ở CHART_AXES.md §8.
  - **fix — cache tick thời gian có thể trả nhầm data khi đổi symbol/timeframe:** cache key cũ (`barSpacing, length, interval, format`) không phụ thuộc identity/nội dung data — đổi sang dataset trùng shape (cùng số nến, cùng interval) tái dùng NHẦM plan cũ, hiện sai nhãn ngày cho tới khi zoom lại. Sửa: thêm `identityHashCode(candles)` vào key.
  - **fix — `priceAxisWidth` + cache `TimeTickPlanner` là `static`, rò rỉ giữa nhiều `KChartWidget` vẽ đồng thời** (watchlist mini-chart, so sánh nhiều symbol — code tự thừa nhận giả định "1 chart active" nhưng không guard). Sửa: bỏ `static`, chuyển thành field instance sở hữu bởi `_KChartWidgetState` (`PriceAxisWidthCache _priceAxisWidthCache`, `TimeTickPlanner _timeTickPlanner` — bền qua các lần `build()` giống `mScaleX`/`mScrollX`), truyền xuống `BaseChartPainter`/`ChartPainter` qua constructor (2 param mới, required). **Breaking** cho ai tự implement `BaseChartPainter` bên ngoài package. `BaseChartPainter.priceAxisWidth`/`updatePriceAxisWidth` trong bullet gốc bên dưới, cũng như `TimeTickPlanner.getOrBuild`, từ nay là **instance member**, không còn gọi qua tên class.
  - File: `lib/utils/time_ticks.dart`, `lib/renderer/base_chart_painter.dart`, `lib/renderer/chart_painter.dart`, `lib/renderer/main_renderer.dart`, `lib/k_chart_widget.dart`
- **feat (breaking — thiết kế lại trục X/Y):** Viết lại toàn bộ cơ chế trục thời gian + trục giá theo spec `CHART_AXES.md` (file mới ở root repo, tự chứa — đọc trực tiếp nếu cần công thức chính xác thay vì suy từ code). Đây là thay đổi lớn nhất kể từ khi thêm Ichimoku, thay hẳn cơ chế "chia đều pixel theo `mGridColumns`" cũ mô tả ở [10.4](#104-auto-detect-time-format--grid-alignment) (bản cũ) bằng 2 module thuần độc lập test được: `lib/utils/time_ticks.dart` (trục X) + `lib/utils/price_ticks.dart` (trục Y). Xem lại [10.4](#104-time-tick-planner--price-ticks-trục-xy) và [12](#12-renderer-internals) (đã viết lại) để biết chi tiết hiện tại.
  - **Trục X — weight ladder thay vì chia cột đều:** Mỗi nến được gán 1 `tickWeight` (int, cache 1 lần lúc load — `MINOR..YEAR`, 12 bậc) dựa trên việc nó có rơi đúng ranh giới lịch (đầu giờ/ngày/tháng/năm, theo **local time**) hay không. Mỗi frame, `BaseChartPainter._updateTimeTicks()` chọn threshold-bậc từ hình học thuần (`barSpacing`, `interval` — KHÔNG đếm số nến hiển thị, tránh nhấp nháy), lọc + đóng gói ứng viên theo `MIN_GAP_X=64px` trên **absolute space** (loại `scrollOffset` — pan không đổi tick nào được chọn), rồi lọc lại theo pixel thật `x ∈ [0, mPlotWidth]`. Kết quả cache tĩnh (`TimeTickPlanner`, theo `(barSpacing, count, interval, format)`) — chỉ rebuild khi zoom/data đổi, KHÔNG rebuild mỗi frame pan.
  - **Trục Y — nice-number thay vì chia đều `gridRows`:** `lib/utils/price_ticks.dart` sinh tick theo ladder `1·2·2.5·5·10 × 10^n` (`niceStep`), số chữ số thập phân suy từ chính `step` (`decimalsFor` — KHÔNG suy từ magnitude, sai với họ `2.5`). `MainRenderer` tính lại `_priceTicks` mỗi frame từ **range giá đang thực sự hiển thị** (đã áp gesture zoom/pan dọc `mScaleY`/`offsetY` — hàm nghịch đảo `_priceAtScreenY`, xem bullet fix bên dưới), không phải range gốc.
  - **Layout — price axis tách strip riêng bên phải** (đúng CHART_AXES.md §7, trước đây label giá vẽ ĐÈ lên nến/cột vol/indicator): `BaseChartPainter` thêm `mPlotWidth`/`mPriceAxisRect`/`mCornerRect`; mọi rect panel (main/vol/secondary/date) giờ chỉ rộng `mPlotWidth = mWidth - priceAxisWidth`, không còn full `mWidth`. `priceAxisWidth` (`static`, cache qua frame giống `maxScrollX`) tự đo theo label rộng nhất, clamp `[48,96]`, làm tròn bội 8, có hysteresis (chỉ thu khi thấp hơn hẳn 1 bậc — chống vòng lặp phản hồi width→layout→label→width). 13 file indicator (MACD/KDJ/RSI/...) **không phải sửa** — `SecondaryRenderer` dùng `canvas.translate` để giữ nguyên công thức `chartRect.width - x` (giả định local x=0) của chúng dù giờ vẽ vào 1 rect có `left != 0`.
  - **Gesture:** vùng kéo dọc để scaleY + double-tap reset (trước đồng bộ với `xFrontPadding`/`effectiveRightPaddingPx` — vốn là padding SAU nến cuối, không liên quan) giờ dùng đúng `BaseChartPainter.priceAxisWidth` (bề rộng strip thật đang vẽ). Kèm 1 fix: `mMainRect` hẹp lại (không phủ strip giá) khiến `isInMainRect` trả `false` khi chạm strip → nhánh "outside main, forward outer scroll" nuốt mất gesture scaleY hợp lệ; sửa bằng cách loại trừ `_isScaleYGesture` khỏi điều kiện đó — xem [13.3](#133-scale).
  - File: `CHART_AXES.md` (mới), `lib/utils/time_ticks.dart` (mới), `lib/utils/price_ticks.dart` (mới), `lib/entity/k_line_entity.dart` (`tickWeight` field), `lib/renderer/base_chart_painter.dart`, `lib/renderer/base_chart_renderer.dart`, `lib/renderer/chart_painter.dart`, `lib/renderer/main_renderer.dart`, `lib/renderer/vol_renderer.dart`, `lib/renderer/secondary_renderer.dart`, `lib/k_chart_widget.dart`, `lib/utils/index.dart`, `test/time_ticks_test.dart` (mới), `test/price_ticks_test.dart` (mới)
- **fix:** Label trục thời gian bị "dính cứng" ở 2 đầu mép trái/phải khi zoom vào — trông như hardcode. Nguyên nhân: `_updateTimeTicks()` lọc tick theo margin **index** (`mStartIndex±1`) thay vì theo **pixel** thật; 1 index dư ra khi `barSpacing` lớn có thể ứng với hàng chục px NGOÀI màn hình, và `drawDate()` chỉ kẹp TEXT (không kẹp gridline, đúng invariant I6 của CHART_AXES.md) nên label của tick off-screen đó bị kẹp dính vào mép. Sửa: lọc nghiêm ngặt theo `x ∈ [0, mPlotWidth]` — đúng thuật toán `ticksFor()` §5.2 của spec.
  - File: `lib/renderer/base_chart_painter.dart`
- **fix:** Tick trục giá không thích ứng theo gesture zoom dọc (`mScaleY`/`offsetY`) — trước đây tính 1 lần từ `minValue`/`maxValue` GỐC (auto-scale theo data thật), gesture chỉ áp transform lên toạ độ VẼ chứ không tính lại tick, nên zoom Y thu nhỏ thì hầu hết tick cũ dạt ra ngoài view, còn lại rất ít label. Sửa: thêm `MainRenderer._priceAtScreenY()` — nghịch đảo CHÍNH XÁC transform canvas thật `ChartPainter.drawChart` dùng cho nến (`translate(0, centerY*(1-scaleY)+offsetY); scale(1.0, scaleY)`), dùng nó tính range giá đang THỰC SỰ hiển thị rồi sinh tick nice-number theo range đó — tick "ảo" (không nhất thiết trùng giá nến thật) luôn lấp đầy trục dù zoom tới đâu.
  - File: `lib/renderer/main_renderer.dart`
- **fix (example app):** REST fetch lịch sử nến (`ChartBloc._loadHistory`) trả về ÍT hơn hẳn `initialBatchSize` khi sàn có gap/downtime gần "hiện tại" (gặp thật ở symbol demo, khung 15m — gap ~2 ngày ngay trước hiện tại khiến cửa sổ mặc định 200 nến chỉ nhận được ~46, dù mở rộng cửa sổ ra sẽ thấy data vẫn còn rất nhiều xa hơn). App trước đó chấp nhận bất kỳ số nến nào trả về, khiến chart trông như "chỉ scroll được 1 page". Sửa: nếu lần fetch đầu không đủ `initialBatchSize` mà server CHƯA trả rỗng (còn lịch sử xa hơn), tự động mở rộng cửa sổ lùi xa hơn (×4 mỗi lần, tối đa 4 lần ≈ phủ 256x cửa sổ gốc) rồi thử lại; tìm đủ thì cắt về đúng `initialBatchSize` nến mới nhất.
  - File: `example/lib/bloc/chart_bloc.dart`
- **implement rồi revert theo yêu cầu (ghi lại để khỏi làm lại nhầm):** CHART_AXES.md §6.6 (instrument tick size — step trục giá không mịn hơn tick size sàn cho phép) và §6.7 (drawing the price strip — occlusion giữa label thường/last-price tag/crosshair tag, "drop rather than drag" khi label lệch vị trí thật, tabular figures, `exp`-based vertical drag scale+lock) đã được implement đầy đủ kèm test T9-T12, sau đó **revert toàn bộ** theo yêu cầu — không còn trong code hiện tại. `CHART_AXES.md` hiện tại cũng không còn 2 mục này. §5.3 (label text theo weight) cũng revert về đúng format gốc của spec (`"2026"/"Aug"/"10"/"09:05"`) sau khi từng đổi sang `DD-MM HH:MM`/`YYYY-MM-DD` theo 1 yêu cầu khác đã bị huỷ.
- **feat (thêm lại sau revert):** `IchimokuIndicator` (Ichimoku Kinko Hyo) — main indicator, thêm lại theo yêu cầu sau khi đã revert hoàn toàn ở mục "revert" bên dưới (07-18). Lần này dựng lại từ đầu với cơ chế đơn giản hơn bản V2 cũ (1 property `futureShift` thay vì 3 hook `requiredFutureBars`/`getFutureMaxMinValue`/`drawFutureSegment`). Xem chi tiết công thức/API tại [9.2](#92-built-in-indicators) và cơ chế renderer dùng chung tại [12](#12-renderer-internals) mục "Vùng tương lai".
  - `calcParams: [9, 26, 52]` (tenkanPeriod, kijunPeriod, spanBPeriod) — bộ cổ điển; `shift` LUÔN = `calcParams[1]` (kijun period), không hardcode `26`.
  - 5 đường: Tenkan/Kijun (vẽ tại index gốc, không dịch), Senkou Span A/B (dịch **tới trước** `shift` nến), Chikou (dịch **lùi** `shift` nến, = `close`, không lưu field riêng). Mây (Kumo) tô giữa Span A/B, tách polygon tại điểm giao (nội suy tuyến tính) để đổi màu đúng đoạn tăng/giảm.
  - **Khác biệt cốt lõi so với V1/V2 cũ**: Span A/B/Chikou vẫn lưu 1 giá trị/nến TẠI INDEX GỐC (giống mọi indicator khác) — phần dịch `±shift` chỉ là phép cộng/trừ `shift × pointWidth` vào toạ độ X **ngay tại draw-time** (`IchimokuIndicator.drawChart`), không lưu mảng đã dịch sẵn `spanA[n+shift]`, không kéo dài entity/mảng dữ liệu.
  - `calc()` dùng sliding-window monotonic deque O(n) cho cả 3 chu kỳ HH/LL — không phải vòng lặp naive O(n×52).
  - `MainIndicator.futureShift` (getter mới, mặc định `0`) — hook chung cho MỌI main indicator cần dịch trục, không riêng Ichimoku; `IchimokuIndicator.futureShift = shift`. Renderer tự tính `mFutureSlots = max(futureShift)` và mở rộng `mDataLen`/biên scroll theo đó — xem [12](#12-renderer-internals).
  - **7 bug phát hiện qua `/code-review` (high effort, 8 finder angle) trên lần thêm lại này** — đã fix hết, đều xoay quanh việc renderer conflate "vùng cần quét để có đủ nến nguồn vẽ đường dịch" (rộng hơn viewport `mFutureSlots` mỗi phía) với "vùng nến đang thực sự hiển thị" (hẹp hơn): label max/min giá lệch vị trí/vô hình khi extreme nằm ngoài viewport; label chỉ số góc trên hiện sai nến khi cuộn giữa lịch sử; autoscale trục Y main/volume/secondary bị nến off-screen ảnh hưởng; field public `currentStartIndex` có thể vượt bound dữ liệu thật; `IchimokuIndicator.pointWidth` có nguy cơ lệch khỏi `KChartStyle.pointWidth` nếu class này từng cho phép subclass. Sửa bằng cách tách riêng `mVisibleStartIndex/mVisibleStopIndex` (hẹp, đúng viewport) khỏi `mRealStartIndex/mRealStopIndex` (rộng, chỉ dùng cho vẽ + Y-range của riêng indicator có dịch trục), clamp `currentStartIndex`, và đổi `KChartStyle` thành `final class`.
    - File: `lib/entity/candle_entity.dart` (field `ichimoku`), `lib/indicator/indicator_style.dart` (`IchimokuStyle`), `lib/indicator/indicator_template.dart` (`part`, `futureShift` getter, switch case), `lib/indicator/main/ichimoku_indicator.dart` (mới), `lib/styles/k_chart_style.dart` (`ichimokuStyle` field/default/`copyWith`, `KChartStyle` → `final class`), `lib/renderer/base_chart_painter.dart` (`mFutureSlots`/`mVisibleStartIndex`/`mVisibleStopIndex`/`mRealStartIndex`/`mRealStopIndex`, `timeAt()`), `lib/renderer/chart_painter.dart`, `example/lib/bloc/chart_state.dart`, `example/lib/bloc/chart_bloc.dart`, `example/lib/main.dart` (chip)
- **feat:** `PSYIndicator` (PSY) — secondary indicator mới, Psychological Line / 心理线. `calcParams: [12, 6]` (N: đếm phiên tăng, M: MA tín hiệu). `PSY = COUNT(close>prevClose,N)/N×100`; `MAPSY = MA(PSY,M)`. Cùng cấu trúc 2-đường-signal như MTM/TRIX. `PSY` cần `prevClose` nên bắt đầu trễ 1 nến (`i=N`, không phải `i=N-1`) — cùng loại trễ như `BR` của BRAR.
  - File: `lib/entity/psy_entity.dart` (mới), `lib/entity/macd_entity.dart` + `lib/entity/k_entity.dart` (nối `PSYEntity` vào mixin chain, trước `MACDEntity`), `lib/indicator/indicator_style.dart` (`PSYStyle`), `lib/indicator/secondary/psy_indicator.dart` (mới), `lib/indicator/indicator_template.dart` (`part` + switch case), `lib/styles/k_chart_style.dart` (`psyStyle` field/default/`copyWith`), `example/lib/bloc/chart_state.dart`, `example/lib/bloc/chart_bloc.dart`, `example/lib/main.dart` (chip + `_demoColors`)
- **feat:** `BIASIndicator` (BIAS) — secondary indicator mới, Bias Ratio / 乖离率. `calcParams: [6, 12, 24]` — nhiều chu kỳ cùng lúc (cùng pattern `MAStyle.maColors`/`getMAColor`, không giới hạn đúng 3). `BIAS(n) = (close - MA(close,n))/MA(close,n) × 100%`, rolling-sum O(n). Output `entity.biasValueList = List<double?>` dùng `double?` (không phải sentinel `0` như MA) vì BIAS hợp lệ đi qua 0 rất thường xuyên.
  - File: `lib/entity/bias_entity.dart` (mới), `lib/entity/macd_entity.dart` + `lib/entity/k_entity.dart` (nối `BIASEntity` vào mixin chain, trước `MACDEntity`), `lib/indicator/indicator_style.dart` (`BIASStyle`), `lib/indicator/secondary/bias_indicator.dart` (mới), `lib/indicator/indicator_template.dart` (`part` + switch case), `lib/styles/k_chart_style.dart` (`biasStyle` field/default/`copyWith`), `example/lib/bloc/chart_state.dart`, `example/lib/bloc/chart_bloc.dart`, `example/lib/main.dart` (chip + `_demoColors`)
- **feat:** `BRARIndicator` (BRAR) — secondary indicator mới, Popularity/Willingness Index (人气意愿指标). `calcParams: [26]`. `AR = Σ(high-open,26)/Σ(open-low,26)×100`, `BR = Σmax(0,high-prevClose,26)/Σmax(0,prevClose-low,26)×100`, tính bằng rolling-sum O(n), guard chia 0 → 0. Xem chi tiết công dụng/công thức tại [9.2](#92-built-in-indicators) và `indicator.md` (mới, ở root repo — tổng hợp công dụng + công thức toàn bộ 7 main + 12 secondary indicator, đọc trực tiếp từ `calc()` trong source).
  - File: `lib/entity/brar_entity.dart` (mới), `lib/entity/macd_entity.dart` + `lib/entity/k_entity.dart` (nối `BRAREntity` vào mixin chain, trước `MACDEntity`), `lib/indicator/indicator_style.dart` (`BRARStyle`), `lib/indicator/secondary/brar_indicator.dart` (mới), `lib/indicator/indicator_template.dart` (`part` + switch case), `lib/styles/k_chart_style.dart` (`brarStyle` field/default/`copyWith`), `example/lib/bloc/chart_state.dart`, `example/lib/bloc/chart_bloc.dart`, `example/lib/main.dart` (chip + `_demoColors`)
- **revert:** Ichimoku Cloud (main indicator, gồm cả V1 và V2 chiếu cloud ra tương lai) đã gỡ hoàn toàn khỏi codebase theo yêu cầu — không còn field/class/wiring nào sót lại, kể cả cơ chế chung `requiredFutureBars`/`getFutureMaxMinValue`/`drawFutureSegment` (hook no-op thêm vào `IndicatorTemplate`/`base_chart_painter.dart`/`main_renderer.dart` cho V2) cũng đã bị gỡ theo (đã rà lại toàn bộ `lib/` + `example/`, không còn tham chiếu nào). *(Cập nhật: thêm lại theo yêu cầu — xem bullet đầu Unreleased.)*
- **fix:** KDJ `drawChart` dùng `||` thay `&&` trong guard null-check K/D/J rồi force-unwrap cả 2 điểm bằng `!` — nến mới chưa kịp `calc()` lại (vd tick live) có thể crash `Null check operator used on a null value`. Sửa: đổi sang `&&`, khớp pattern mọi secondary indicator khác (RSI/WR/MTM/TRIX/StochRSI).
  - File: `lib/indicator/secondary/kdj_indicator.dart`
- **fix:** `SARIndicator.drawChart` hard-code màu chấm SAR theo `candleStyle.upColor`/`dnColor`/`defaultTextColor` của MAIN CHART, bỏ qua hẳn `indicatorStyle` — set màu qua `KChartColors.sarStyle` không có tác dụng lên chấm vẽ, chỉ đổi được label `"SAR: ..."`. Sửa: `SARStyle` đổi field `sarColor` (1 màu) thành `upColor`/`dnColor` (theo convention `SuperTrendStyle`) — cả chấm lẫn label giờ tự chọn màu theo xu hướng (`sar <= (high+low)/2` = tăng → `upColor`, ngược lại → `dnColor`), độc lập với `candleStyle`.
  - File: `lib/indicator/main/sar_indicator.dart`, `lib/indicator/indicator_style.dart`
- **fix:** `LivePriceStyle.textStyle` không có guard fallback màu như 5 chỗ khác trong codebase — `textStyle` không tự set `color` sẽ ra chữ đen mặc định của `TextPainter`, gần như vô hình trên nền badge màu `upColor`/`dnColor`. Gom guard này (và 5 chỗ khác) vào 1 helper dùng chung `resolveTextStyle(base, fallback, {forceColor})`.
  - File: `lib/renderer/chart_painter.dart`, `lib/utils/text_style_util.dart` (mới) — áp dụng luôn cho `vol_renderer.dart`, `secondary_renderer.dart`, `indicator_template.dart`, `depth_chart.dart`
- **fix:** Alpha bị `.withAlpha()` ghi đè vô điều kiện thay vì nhân dồn — cùng lớp lỗi `VolRenderer` đã fix ở mục dưới, còn sót ở `MainRenderer` (`bgColor.withAlpha(80)` cho nền label indicator) và `SecondaryRenderer` (`defaultTextColor.withAlpha(90)` cho đường tham chiếu nét đứt). Sửa theo cùng pattern nhân dồn `color.withValues(alpha: color.a * factor)`.
  - File: `lib/renderer/main_renderer.dart`, `lib/renderer/secondary_renderer.dart`
- **refactor:** Thay cơ chế `identical(indicatorStyle, const XxxStyle())` (xem mục "16 field style indicator" bên dưới) bằng field `isDefaultStyle` tường minh — `identical()` không phân biệt được "caller không truyền `indicatorStyle`" với "caller chủ động truyền `const XxxStyle()` y hệt default" (Dart const-canonicalization khiến 2 trường hợp giống hệt nhau), nên trường hợp sau bị nhận nhầm là "chưa customize" và bị `KChartColors` ghi đè ngoài ý muốn. Sửa: constructor cả 16 indicator đổi `indicatorStyle` sang nhận `XxxStyle?` (nullable, mặc định `null`), field mới `isDefaultStyle = (indicatorStyle == null)` thay cho so sánh `identical()`.
  - File: `lib/indicator/indicator_template.dart` + 16 file `lib/indicator/{main,secondary}/*.dart`
- **refactor:** `getTextStyle`'s `forceColor` đổi từ positional bool (`getTextStyle(color, style, true)` — không tên, dễ chép sai khi copy giữa 16 file indicator gần giống nhau) sang named param (`getTextStyle(color, base: style, forceColor: true)`).
  - File: `lib/indicator/indicator_template.dart` + ~30 call site trong `lib/indicator/{main,secondary}/*.dart`
- **perf:** `LivePriceBadgePainter` cache `Paint`/`Path` thành `static` thay vì dựng mới (2 `Paint` + 1 `Path`) mỗi lần `paint()` — chạy mỗi frame theo tick giá live không throttle. `applyIndicatorColorStyles()` thêm cache theo `identical()` của bộ 3 tham số đầu vào, bỏ qua switch 16-case khi `mainIndicators`/`secondaryIndicators`/`chartColors` không đổi giữa 2 lần `ChartPainter` được dựng liên tiếp (rebuild do tick giá).
  - File: `lib/styles/live_price_style.dart`, `lib/indicator/indicator_template.dart`
- **fix:** `DepthChart.createState()` trả về kiểu private `_DepthChartState` trong API public (lint `library_private_types_in_public_api`) — đổi return type sang `State<DepthChart>` (public), đúng pattern đã áp dụng từ commit `c1d04f8` cho chính widget này trước đây (có lẽ bị lệch lại qua refactor sau này).
  - File: `lib/depth_chart.dart`
- **fix:** `textStyle.color` do người dùng tự set (vd `CandleStyle(textStyle: TextStyle(color: Colors.amber))`) bị **ghi đè vô điều kiện** ở 5 nơi — `getTextStyle()`/`getTextPainter()` luôn gọi `.copyWith(color: mauNguQuNghia)` (`defaultTextColor`/`crossTextColor`/`maxColor`/`indicatorStyle.xxxColor`/`annotationColor`...), nên set `color` trong `textStyle` không có tác dụng gì. Sửa: chỉ `copyWith(color: ...)` khi `textStyle.color == null` (chưa tự set); nếu đã set thì dùng nguyên `textStyle`, bỏ qua màu ngữ nghĩa truyền vào. Mặc định (không set `color`) hành vi giữ nguyên như cũ, không breaking.
  - File: `lib/renderer/chart_painter.dart` (`candleStyle.textStyle`), `lib/renderer/vol_renderer.dart` (`volumeStyle.textStyle`), `lib/indicator/indicator_template.dart` (`indicatorStyle.textStyle`, dùng chung 16 indicator), `lib/depth_chart.dart` (`chartStyle.textStyle` + `annotationTextStyle`).
- **refactor (breaking):** `KChartColors`/`KChartStyle` tái cấu trúc lại toàn bộ — gom màu/text theo khu vực thay vì field rời rạc, và cho phép cấu hình màu indicator từ 1 chỗ duy nhất. Xem chi tiết [8.2](#82-kchartcolors).
  - **`CandleStyle`** (main chart) + **`VolumeStyle`** (panel volume) — 2 class mới trong `styles/k_chart_style.dart`, mỗi class tự chứa cả màu LẪN `textStyle` riêng (mặc định fontSize 10). Thay thế các field cũ: `kLineColor`, `kLineFillColors`, `upColor`, `dnColor` → `CandleStyle`; `ma5Color`, `ma10Color`, `volUpColor`, `volDnColor` → `VolumeStyle`.
  - **Xoá `volColor`** — dead field, không có code nào đọc, không mang sang `VolumeStyle`.
  - **16 field style indicator** thêm vào `KChartColors` (`maStyle`, `emaStyle`, `bollStyle`, `sarStyle`, `zigzagStyle`, `superTrendStyle`, `avlStyle`, `macdStyle`, `kdjStyle`, `rsiStyle`, `wrStyle`, `cciStyle`, `obvStyle`, `trixStyle`, `mtmStyle`, `stochRsiStyle`) — set màu toàn bộ indicator từ `KChartColors` thay vì phải tự tạo từng instance `AVLIndicator(indicatorStyle: ...)`.
    - Cơ chế: `applyIndicatorColorStyles()` (`indicator/indicator_template.dart`) chạy 1 lần trong constructor `ChartPainter`, dùng `switch` theo runtime type để gán `colors.xxxStyle` vào `indicator.indicatorStyle` — **chỉ khi** instance đó còn dùng style mặc định. Instance nào tự truyền `indicatorStyle` riêng thì KHÔNG bị ghi đè. *(Cập nhật 07-17: phát hiện "còn default không" ban đầu dùng `identical()` với `const XxxStyle()`, sau đó thay bằng field `isDefaultStyle` tường minh — xem bullet đầu Unreleased.)*
    - Kéo theo: `IndicatorTemplate.indicatorStyle` đổi từ `final` sang mutable field.
    - Kéo theo: `indicator/indicator_style.dart` không còn là `part of 'indicator_template.dart'` nữa mà là file độc lập (`import`/`export`) — để `k_chart_style.dart` import thẳng các class `XxxStyle` mà không tạo vòng lặp import.
  - Text style **không** còn nằm ở `KChartStyle` (`textStyle`/`volTextStyle` đã bị xoá khỏi đó) — dời hẳn vào `CandleStyle.textStyle`/`VolumeStyle.textStyle` để mỗi khu vực tự chứa đủ cả màu lẫn font trong 1 object.
  - `example/lib/main.dart` (`_buildKChart`/`_demoColors`) và `example/lib/bloc/chart_bloc.dart` (`_initialState`) cập nhật theo API mới — state mặc định giờ bật sẵn TOÀN BỘ 6 main + 9 secondary indicator (trước chỉ MA + MACD) kèm palette màu riêng cho từng cái, để demo xem hết 1 lượt.
  - Test `example/test/persistent_isolate_test.dart` phải sửa theo: vì default giờ bật sẵn mọi indicator, toggle trong test nghĩa là TẮT (trước đây default rỗng nên toggle nghĩa là BẬT) — assertion đổi từ `contains` sang `isNot(contains(...))`.
- **fix:** 5 bug correctness phát hiện qua `/code-review` (high effort, 8 finder angle) trên refactor `KChartColors` ở trên — đã fix hết:
  - `AVLIndicator`/`ZigZagIndicator` bake màu Paint 1 lần trong constructor từ `indicatorStyle`, không bao giờ đọc lại trong `drawChart` → set `avlStyle`/`zigzagStyle` qua `KChartColors` **không có tác dụng lên đường vẽ**, chỉ đổi được label text (đọc `indicatorStyle` live). Sửa: bỏ `..color = ...` khỏi constructor, gán lại `_linePaint..color = indicatorStyle.xxxColor` ngay trước mỗi lần vẽ.
  - `BOLLIndicator._fillPaint` cùng lỗi — vùng tô mờ giữa 2 band không đổi màu theo `bollStyle.fillColor`, dù 3 đường band (đọc live) đã đúng.
  - `applyIndicatorColorStyles()` dùng `identical(indicator.indicatorStyle, const XxxStyle())` để biết "còn default không" — sau lần gán đầu tiên, field không còn `identical` với default nữa nên mọi lần build sau (vd đổi theme runtime) không bao giờ áp lại màu mới cho indicator đó, nếu app giữ instance ổn định qua nhiều build. Sửa: thêm field `_originalIndicatorStyle` (`final`, snapshot chụp 1 lần lúc khởi tạo qua initializer list), so `identical()` với snapshot này thay vì giá trị `indicatorStyle` hiện tại (có thể đã bị chính cơ chế này ghi đè). *(Cập nhật 07-17: `identical()`-với-snapshot vẫn không phân biệt được caller truyền `const XxxStyle()` y hệt default — thay hẳn bằng field `isDefaultStyle` tường minh, xem bullet đầu Unreleased.)*
  - `ChartPainter.drawVerticalText` tính chung 1 `textStyle` (từ `candleStyle.textStyle`) rồi truyền cho cả main lẫn volume renderer → `VolumeStyle.textStyle` không áp dụng cho label max/min trục phải của panel volume (chỉ áp cho header `VOL:/MA5:/MA10:`). Sửa: gọi riêng `mVolRenderer.getTextStyle(...)` cho nhánh volume.
  - `IndicatorTemplate.getTextStyle` vẫn hard-code `fontSize: 10`, chưa nối với `candleStyle.textStyle` — label mọi indicator (RSI/MACD/KDJ/AVL/BOLL/SuperTrend/...) không đổi font theo `KChartColors` dù docs claim có. Sửa: `getTextStyle` nhận thêm param optional `base`, toàn bộ `drawFigure()` (16 file main + secondary indicator) truyền `chartColors.candleStyle.textStyle` vào — sau đó nâng cấp tiếp thành `indicatorStyle.textStyle` riêng từng indicator (xem mục dưới).
- **feat:** Mỗi indicator style (`AVLStyle`, `MAStyle`, `BOLLStyle`, `RSIStyle`, `MACDStyle`, `KDJStyle`...) giờ có `textStyle` RIÊNG — thêm field vào base class `IndicatorStyle` (mặc định `fontSize: 10`), forward qua `super.textStyle` ở cả 15 subclass. Label mỗi indicator giờ chỉnh font độc lập nhau qua `KChartColors.xxxStyle.textStyle`, không còn dùng chung `candleStyle.textStyle` như bước fix bug ở trên.
- **refactor (cleanup):** dọn 4 finding non-correctness (cleanup/altitude/efficiency) còn lại từ cùng đợt code review:
  - `KChartColors.copyWith()` — method mới, override 1-2 field giữ nguyên phần còn lại, thay vì tự liệt kê tay đủ 25+ field (`example/lib/main.dart`'s `_demoColors` trước đó phải copy tay 9 field chỉ để giữ nguyên).
  - `applyIndicatorColorStyles()` gộp switch 16 case gần giống hệt nhau thành 1 helper generic `_applyDefaultStyle<K>(ind, defaultStyle, override)` — rút từ ~90 dòng còn ~45.
  - `DepthChartStyle` thêm `textStyle`/`annotationTextStyle` (default fontSize 10/9) — theo đúng convention `CandleStyle`/`VolumeStyle` vừa làm, thay 2 chỗ hard-code fontSize trong `depth_chart.dart` (`getTextPainter`, `_PopupPainter._getTextPainter`).
  - `example/lib/main.dart`: cache `_mainIndicatorsFor`/`_secondaryIndicatorsFor` theo nội dung `Set` (so bằng `_setEquals`, không phải reference) — trước đó `ChartState.mainIndicators`/`secondaryIndicators` là getter tạo instance (+ Paint) mới mỗi lần gọi, và `BlocBuilder` rebuild trên MỌI thay đổi state (kể cả `livePrice` cập nhật mỗi tick WS không throttle) → mỗi tick giá rebuild lại toàn bộ 15 indicator dù `mainTypes`/`secondaryTypes` không đổi.
- **feat:** `LivePriceStyle` (`lib/styles/live_price_style.dart`) — tách `nowPriceUpColor`/`nowPriceDnColor` khỏi `KChartColors` thành model riêng (`upColor`, `dnColor`, `textStyle`), cùng convention `CandleStyle`/`VolumeStyle`. **`upColor`/`dnColor` CHỈ tô nền badge + đường kẻ ngang** (`ChartPainter.drawNowPrice`); màu CHỮ luôn lấy từ `textStyle.color` (default `Colors.white`) — KHÔNG dùng `upColor`/`dnColor` cho chữ, vì nền badge giờ là màu đặc nên chữ cùng màu nền sẽ gần như vô hình.
- **feat:** `LivePriceBadgePainter` (cùng file) — badge "flag" (nền bo góc + mũi tên nhỏ trỏ trái) convert từ `assets/Number.svg` (`viewBox="0 0 54 14"`), gắn thẳng vào `ChartPainter.drawNowPrice()` thay cho `RRect + border` phẳng cũ (gọi trực tiếp `LivePriceBadgePainter(...).paint(canvas, size)` lên canvas thật, không qua widget `CustomPaint`). Nền + mũi tên cùng nhân 1 cặp tỉ lệ `scaleX = size.width/54`, `scaleY = size.height/14` — khớp đúng cách SVG gốc tự scale ĐỒNG BỘ mọi phần tử con theo viewBox (bug ban đầu: chỉ nền được scale, mũi tên để nguyên toạ độ tuyệt đối → lệch khi badge không đúng 54×14); nhờ vậy badge tự co giãn đúng tỉ lệ theo độ dài số giá. Mũi tên trỏ trái khớp đúng ngữ nghĩa "chỉ vào đường giá" khi badge đứng mép PHẢI chart (`VerticalTextAlignment.right`, mặc định); dùng `left` thì mũi tên trỏ ra ngoài thay vì vào chart (hạn chế của asset gốc — chỉ có 1 chiều, chưa có bản mirror).
  - Padding badge (`chart_painter.dart` `drawNowPrice`) đổi từ `(paddingX: 3, paddingY: 1.5)` → `(5, 3)`.
  - Kéo theo: xoá 2 field `nowPriceSelectorPaint`/`nowPriceSelectorBorderPaint` trên `ChartPainter` (không còn dùng sau khi badge chuyển sang vẽ qua `LivePriceBadgePainter`).
- **fix:** `VolRenderer.drawChart` — cột volume dùng `base.withValues(alpha: chartStyle.volBarOpacity)`, **ghi đè hoàn toàn** alpha sẵn có của `volumeStyle.upColor`/`dnColor` thay vì nhân dồn. Hệ quả: set alpha thẳng trong `Color` (vd `Color(0x8076FF03)`) bị bỏ qua vô hình nếu `chartStyle.volBarOpacity` giữ nguyên default `1.0`. Sửa: `base.withValues(alpha: base.a * chartStyle.volBarOpacity)` — set opacity qua alpha-channel của `Color` hoặc qua `volBarOpacity` đều dùng được, kết hợp được cả hai (nhân dồn).
- **feat:** `StochRSIIndicator` — secondary indicator Stochastic RSI. Xem chi tiết [9.2](#92-built-in-indicators).
  - `calcParams: [14, 14, 3, 3]` — (N1: RSI length, N2: Stoch length, M1: smooth %K, M2: smooth %D), chuẩn Binance/TradingView.
  - Công thức: RSI Wilder tính **nội bộ** trong `calc()` (không dùng lại `entity.rsi` — RSIIndicator có thể không được bật, period có thể khác), `StochRSI = (RSI − MIN(RSI,N2)) / (MAX(RSI,N2) − MIN(RSI,N2)) × 100`, `%K = SMA(StochRSI, M1)`, `%D = SMA(%K, M2)`. Pipeline 4 tầng chạy 1 vòng lặp O(n).
  - Output: `entity.stochRsiK` / `entity.stochRsiD` — mixin mới `StochRSIEntity` (`lib/entity/stoch_rsi_entity.dart`), nối vào `on` clause của `MACDEntity`, đứng **trước** `MACDEntity` trong `KEntity`.
  - Style: `StochRSIStyle({ kColor, dColor })` — K vàng `0xFFFFC634`, D xanh `0xff35cdac`.
  - Kèm **2 đường tham chiếu nét đứt 20/80** (quá bán/quá mua) kiểu Binance qua `referenceValues => [20, 80]`; `getMaxMinValue` ép range panel bao luôn `[20, 80]` để vạch không chạy ra ngoài.
  - Edge case: `MAX == MIN` (RSI đi ngang tuyệt đối) → StochRSI = 0 theo convention TradingView. Null-chain: %K có từ nến ~30, %D từ nến ~32 với params mặc định.
- **feat:** Cơ chế **đường tham chiếu ngang** dùng chung cho mọi secondary indicator (không riêng StochRSI):
  - `SecondaryIndicator.referenceValues` — getter mới, mặc định `[]`; indicator phụ nào muốn có vạch mốc chỉ cần override, không đụng renderer.
  - `SecondaryRenderer.drawReferenceLines(canvas)` — vẽ nét đứt 4px-4px, màu `defaultTextColor` alpha 90, strokeWidth 0.5, một lần mỗi frame.
  - Gọi từ `ChartPainter.drawChart()` ở **screen space trước translate/scale** → vạch không giãn theo scaleX, nằm phía sau đường indicator, và **vẫn hiển thị khi `hideGrid = true`** (khác grid thường).
  - Kéo theo: `ChartPainter.mSecondaryRendererList` thu hẹp kiểu từ `Set<BaseChartRenderer>` → `Set<SecondaryRenderer>`.
- **feat:** `AVLIndicator` — main indicator Average Value Line kiểu Binance, đường đi xuyên qua thân nến. Xem chi tiết [9.2](#92-built-in-indicators).
  - Công thức: `AVL = amount / vol` — giá khớp lệnh trung bình thực của từng nến (quote volume ÷ base volume); fallback khi `amount` null/0 hoặc `vol = 0`: typical price `(H+L+C)/3` (vẫn luôn nằm trong range high–low của nến).
  - `calcParams: []` — không có param chu kỳ.
  - Output: `entity.avl` — mixin mới `AVLEntity` (`lib/entity/avl_entity.dart`); theo pattern ZigZag: đứng **sau** `MACDEntity` trong `KEntity`, indicator cast `entity as AVLEntity` (main indicator dùng `CandleEntity` làm T — không cần vào `on` clause).
  - Style: `AVLStyle({ avlColor, lineWidth })` — mặc định vàng `0xFFFFC634`, lineWidth 1.0.
  - Cần API trả `amount` (quote volume) để có giá trị thực; thiếu thì fallback vẫn bám nến nhưng không phản ánh volume-weighting. Biến thể đã thử và bỏ: cumulative VWAP (đường trôi xa khỏi cụm nến, kéo giãn trục Y), rolling VWAP N nến (mượt nhưng vẫn lệch nến, không giống Binance).
- **feat:** `MTMIndicator` — secondary indicator Momentum. Xem chi tiết [9.2](#92-built-in-indicators).
  - `calcParams: [12, 6]` — (N: chu kỳ momentum, M: chu kỳ MA signal).
  - Công thức: `MTM = CLOSE − REF(CLOSE, N)` (biến thể tuyệt đối classic), `MTMMA = MA(MTM, M)` — sliding-window sum O(n).
  - Output: `entity.mtm` / `entity.mtmMa` — mixin mới `MTMEntity` (`lib/entity/mtm_entity.dart`), nối vào `on` clause của `MACDEntity`, đứng **trước** `MACDEntity` trong `KEntity`.
  - Style: `MTMStyle({ mtmColor, mtmMaColor })` — MTM vàng `0xFFFFC634`, MTMMA xanh `0xff35cdac`.
  - Null: `mtm` null khi `i < N`; `mtmMa` null tới khi đủ M giá trị MTM. Scale phụ thuộc giá tuyệt đối của symbol (BTC ra hàng trăm/nghìn) — cần scale % thì đổi 1 dòng trong `calc()` sang ROC-style `(CLOSE − REF)/REF × 100`.
- **feat:** `entity/index.dart` export đầy đủ các entity mixin: bổ sung `avl_entity.dart`, `mtm_entity.dart`, `stoch_rsi_entity.dart`, và `trix_entity.dart` (trước đây bị sót export dù TRIX đã release ở 1.0.2).
- **feat:** Example app (`example/lib/main.dart`) bổ sung chip toggle cho các indicator mới:
  - Main: **ZigZag** (indicator có từ 0.0.1 nhưng chưa có chip demo), **AVL**.
  - Secondary: **MTM**, **StochRSI**.

### 1.0.2

- **feat:** `SuperTrendIndicator` (SUPER) — main indicator SuperTrend. Xem chi tiết [9.2](#92-built-in-indicators).
  - `calcParams: [10, 30]` — (N: ATR period, multiplier×10 → factor 3.0).
  - Công thức: `ATR = RMA(TR, N)` (seed = SMA(TR,N), sau đó Wilder smoothing `atr = (atr×(N−1)+tr)/N`), band = `(H+L)/2 ± factor×ATR`, trend flip khi close cắt qua band hiện tại.
  - Output: `entity.superTrend = SuperTrend { value, isUp }` — class định nghĩa trong `super_trend_indicator.dart`, field nằm ở `CandleEntity` (main indicator, không cần entity mixin riêng).
  - Style: `SuperTrendStyle({ upColor, dnColor, upFillColor, dnFillColor, lineWidth })` — đường đổi màu theo `isUp` (xanh uptrend/band dưới giá, đỏ downtrend/band trên giá) + fill mờ giữa band và giá; label `SUPER: x` cũng đổi màu theo trend.
- **feat:** `TRIXIndicator` (TRIX) — secondary indicator TRIX/MATRIX. Xem chi tiết [9.2](#92-built-in-indicators).
  - `calcParams: [12, 20]` — (N: chu kỳ triple EMA, M: chu kỳ MA signal).
  - Công thức: `EMA1 = EMA(CLOSE,N)`, `EMA2 = EMA(EMA1,N)`, `EMA3 = EMA(EMA2,N)`, `TRIX = (EMA3 − REF(EMA3,1)) / REF(EMA3,1) × 100`, `MATRIX = MA(TRIX, M)` — EMA seed bằng close nến đầu, MA signal sliding-window sum O(n).
  - Output: `entity.trix` / `entity.trixMa` — mixin `TRIXEntity` (`lib/entity/trix_entity.dart`), nối vào `on` clause của `MACDEntity`, đứng **trước** `MACDEntity` trong `KEntity`.
  - Style: `TRIXStyle({ trixColor, trixMaColor })` — TRIX vàng `0xFFFFC634`, MATRIX xanh `0xff35cdac`.
  - Null: `trix` null ở nến đầu (chưa có `prevEma3`); `trixMa` null tới khi đủ M giá trị TRIX.

### 1.0.1

- **fix:** `onLoadMore(true)` không được tự động gọi khi data ban đầu (hoặc sau khi load thêm) chưa lấp đầy chiều rộng chart (`ChartPainter.maxScrollX <= 0`) và user chưa thực hiện gesture nào. Trước đây `onLoadMore` chỉ trigger từ `onScaleUpdate`/`onScaleEnd`/fling nên chart hiển thị ít data hơn màn hình sẽ đứng im vô thời hạn. Đã thêm `_maybeLoadMoreForNarrowData()` gọi trong `initState`/`didUpdateWidget` (qua `addPostFrameCallback`), guard bằng `_narrowLoadRequestedForLength` để không gọi trùng `onLoadMore` mỗi khi widget rebuild vì lý do không liên quan tới `datas`. Chi tiết: [13.9](#139-auto-load-khi-data-chưa-lấp-đầy-chart-không-cần-gesture).
- **docs:** Sửa doc comment gây warning khi generate `dartdoc`: generic type `List<SecondaryIndicator<MACDEntity, dynamic>>` bị hiểu nhầm là thẻ HTML, và `[0]`/`[i]`/`[i-1]`/`[scaleX]` bị hiểu nhầm là doc-reference link không tồn tại.

### 1.0.0

- **feat:** `KChartScaleState` — class lưu/khôi phục trạng thái zoom (`scaleX`, `scaleY`, `scrollX`). Truyền qua `KChartWidget.chartScale` để restore khi đổi timeframe; `scaleX` tự clamp theo `minScale`/`maxScale`. Callback `onChartScaleChanged` (`OnChartScaleChanged`) emit sau khi kết thúc pinch, scaleY drag, zoom controller, hoặc double-tap reset scaleY.
- **feat:** Panel volume hiển thị thêm label giá trị nhỏ nhất (min vol trong vùng hiển thị) ở góc dưới-phải, giống cách MACD hiển thị min. `mVolMinValue` không còn hardcode `0` mà được tính từ data thực tế.

### 0.0.1

- Initial release of k_chart_jk — a Flutter candlestick chart package.
- Candlestick and line chart rendering with smooth gesture support (pan, zoom, fling).
- Main indicators: MA, EMA, BOLL, SAR, ZigZag.
- Secondary indicators: MACD, KDJ, RSI, WR, CCI.
- Volume bar chart with MA5/MA10 overlay.
- Long-press info dialog with customizable `detailBuilder`.
- Dark/light theme support via `KChartColors`.
- `KChartController` for programmatic zoom in/out and reset.
- Depth chart widget (`DepthChart`) for order book visualization.
- Multi-language support via `ChartTranslations`.

---

## 2. Tổng quan kiến trúc

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
- **Tính min/max chỉ trên vùng dữ liệu visible** (`mStartIndex..mStopIndex`, tính theo `mPlotWidth` — KHÔNG phải `mWidth`, xem [12](#12-renderer-internals) "Price axis strip").
- **`scrollX` và `scaleX` thành phép biến đổi canvas**, không vẽ tay từng phần.
- **`scaleY` áp riêng cho main**, secondary nằm ngoài transform để không bị giãn.
- **Tick trục X/Y tính lại mỗi frame theo layer riêng** (`BaseChartPainter._updateTimeTicks()` cho X, `MainRenderer` constructor cho Y) — renderer con không tự chọn tick, chỉ vẽ danh sách đã tính sẵn. Chi tiết đầy đủ ở `CHART_AXES.md` + [10.4](#104-time-tick-planner--price-ticks-trục-xy).
- **Mọi label vẽ ngoài canvas transform** phải đi qua `_applyScaleY(rawY)`.

---

## 3. Cài đặt & Quick Start

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

Widget tự chứa (copy-paste chạy được, chỉ cần cắm nguồn data thật vào `_fetchInitialCandles`/`_loadMoreHistory`) — bật **toàn bộ** 6 main + 9 secondary indicator, custom màu qua `CandleStyle`/`VolumeStyle`/style riêng từng indicator (xem [8.2](#82-kchartcolors)), toggle dark mode / line-vs-candlestick, zoom qua `KChartController`, và `DepthChart` đi kèm. Đây gần như nguyên bản cách `example/lib/main.dart` + `example/lib/bloc/chart_bloc.dart` trong repo demo dựng lên (repo demo tách phần data/network ra `ChartBloc` — ở đây gộp thẳng vào `State` cho gọn).

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

**Kèm `DepthChart`** (order book — widget độc lập, không phụ thuộc `KChartWidget`, xem [11](#11-depthchart--orderbook-depth)):

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

`DepthChartStyle` hiện KHÔNG có field `textStyle`/`fontSize` — nhãn trục và popup annotation của `DepthChart` vẫn hard-code `fontSize: 10`/`9` trong `depth_chart.dart` (chưa được tách ra như `CandleStyle.textStyle`/`VolumeStyle.textStyle` ở [8.2](#82-kchartcolors)); nói nếu muốn mình bổ sung tương tự.

---

## 4. Entry point & exports

File chính import: `package:k_chart_jk/k_chart_plus.dart`. Re-export:

| Export                              | Chứa gì                                                                              |
| ----------------------------------- | ------------------------------------------------------------------------------------ |
| `k_chart_widget.dart`               | `KChartWidget`, `TimeFormat`, `WidgetDetailBuilder`                                  |
| `styles/k_chart_style.dart`         | `KChartStyle`, `KChartColors`                                                        |
| `styles/depth_chart_style.dart`     | `DepthChartStyle`, `DepthChartColors`                                                |
| `depth_chart.dart`                  | `DepthChart` widget                                                                  |
| `chart_translations.dart`           | `DepthChartTranslations`                                                             |
| `utils/index.dart`                  | `DataUtil`, `dateFormat`, `NumberUtil`, format tokens                                |
| `entity/index.dart`                 | Toàn bộ entity & mixin                                                               |
| `renderer/index.dart`               | `ChartPainter`, `BaseChartPainter`, renderer base                                    |
| `renderer/k_chart_controller.dart`  | `KChartController`                                                                   |
| `extension/num_ext.dart`            | `num.toStringAsFixedNoZero(...)`                                                     |
| `indicator/indicator_template.dart` | `IndicatorTemplate`, `MainIndicator`, `SecondaryIndicator`, tất cả indicator + style |

---

## 5. Entity — data models

### 5.1 `KLineEntity`

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

### 5.2 `KEntity` & các mixin

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

### 5.3 `InfoWindowEntity`

```dart
class InfoWindowEntity {
  KLineEntity kLineEntity;  // nến đang được chọn
  bool isLeft;              // true: vẽ dialog bên trái
}
```

### 5.4 `DepthEntity`

```dart
class DepthEntity {
  double price;
  double vol;  // phải là cumulative volume
}
```

### 5.5 Mixin type system — generic indicator

Khi dùng `List<SecondaryIndicator<MACDEntity, dynamic>>`, indicator mới cần entity riêng → thêm entity vào `on` clause của `MACDEntity` và đặt trước `MACDEntity` trong `KEntity`:

```dart
// Quy tắc khi thêm entity mới
// 1. Tạo <Name>Entity mixin đơn giản (không có `on`)
// 2. Thêm <Name>Entity vào `on` clause của MACDEntity
// 3. Đặt <Name>Entity TRƯỚC MACDEntity trong KEntity
// 4. Dùng MACDEntity làm T trong <Name>Indicator
```

---

## 6. `KChartWidget` — API đầy đủ

File: `lib/k_chart_widget.dart`.

### 6.1 Required

| Param           | Kiểu                           | Ý nghĩa                               |
| --------------- | ------------------------------ | ------------------------------------- |
| `datas`         | `List<KLineEntity>?`           | Data nguồn. Empty/null = chart trống. |
| `chartStyle`    | `KChartStyle`                  | Kích thước, padding, line width.      |
| `chartColors`   | `KChartColors`                 | Toàn bộ màu.                          |
| `detailBuilder` | `Widget Function(KLineEntity)` | Builder cho info dialog (long-press). |
| `isTrendLine`   | `bool`                         | Bật mode vẽ trend line.               |

### 6.2 Indicators & display

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
| `xFrontPadding`         | `100`                     | Padding phải sau nến cuối (px tại chart ≥375px).      |
| `verticalTextAlignment` | `right`                   | `left` / `right` — vị trí label giá dọc.              |
| `fixedLength`           | `2`                       | Số chữ số thập phân format giá.                       |

### 6.3 Pan / zoom / scroll

| Param              | Default             | Ý nghĩa                              |
| ------------------ | ------------------- | ------------------------------------ |
| `minScale`         | `0.5`               | Min cho `mScaleX`.                   |
| `maxScale`         | `2.2`               | Max cho `mScaleX`.                   |
| `flingTime`        | `600`               | ms — duration fling animation.       |
| `flingRatio`       | `0.5`               | Hệ số nhân vận tốc fling.            |
| `flingCurve`       | `Curves.decelerate` | Curve animation fling.               |
| `mBaseHeight`      | `360`               | Height (px) của main chart panel.    |
| `mSecondaryHeight` | `mBaseHeight * 0.2` | Height (px) của mỗi secondary panel. |

### 6.4 Load more / callback

| Param                  | Kiểu                          | Ý nghĩa                                                                                                                                                                 |
| ---------------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `onLoadMore`           | `void Function(bool isLeft)?` | Trigger khi scroll gần biên **hoặc** khi data chưa lấp đầy chart (xem [13.9](#139-auto-load-khi-data-chưa-lấp-đầy-chart-không-cần-gesture)). `true` = load data cũ hơn. |
| `isLoadingMore`        | `bool`                        | Cờ khoá tránh duplicate request.                                                                                                                                        |
| `isOnDrag`             | `void Function(bool)?`        | Callback start/stop drag.                                                                                                                                               |
| `controller`           | `KChartController?`           | Điều khiển từ ngoài.                                                                                                                                                    |
| `onChartScaleChanged`  | `OnChartScaleChanged?`        | Emit sau mỗi lần kết thúc pinch/scaleY/zoom/reset.                                                                                                                      |
| `onVerticalOverscroll` | `ValueChanged<double>?`       | Fire khi pan Y vượt clamp 50%.                                                                                                                                          |

**Lưu ý:** `onLoadMore` không chỉ trigger từ gesture (pan/pinch/fling) mà còn tự bắn từ `initState`/`didUpdateWidget` nếu data hiện tại chưa đủ lấp đầy chiều rộng chart — không cần user tương tác gì (fix 1.0.1).

### 6.5 Zoom state

| Param        | Kiểu                | Ý nghĩa                                                 |
| ------------ | ------------------- | ------------------------------------------------------- |
| `chartScale` | `KChartScaleState?` | Scale đã lưu — truyền lại khi đổi timeframe để restore. |

### 6.6 Background watermark

| Param                   | Default | Ý nghĩa                                                      |
| ----------------------- | ------- | ------------------------------------------------------------ |
| `backgroundLogo`        | `null`  | Widget overlay ở giữa main chart. Có `IgnorePointer` nội bộ. |
| `backgroundLogoOpacity` | `1.0`   | 0.0 ẩn — 1.0 hiện đầy đủ.                                    |

### 6.7 `TimeFormat` constants & ép format nhãn trục thời gian

```dart
TimeFormat.yearMonthDay         // yyyy-MM-dd
TimeFormat.yearMonthDayWithHour // yyyy-MM-dd HH:mm
```

`KChartWidget.timeFormat` (`List<String>?`, mặc định `null`) — ép format này cho **MỌI** tick trục X + label crosshair, bất kể `tickWeight`, bỏ qua hẳn thuật toán thích ứng ở [10.4](#104-time-tick-planner--price-ticks-trục-xy). `null` (mặc định) = giữ hành vi thích ứng (format tự đổi theo mức zoom — "10" ở ranh giới ngày, "09:05" giữa ngày, ...).

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

---

## 7. `KChartController`

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

## 8. `KChartStyle` & `KChartColors`

### 8.1 `KChartStyle`

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

### 8.2 `KChartColors`

#### `CandleStyle` — main chart (nến hoặc line chart)

| Field              | Default             | Ý nghĩa                                                          |
| ------------------ | -------------------- | ----------------------------------------------------------------- |
| `upColor`          | `0xFF14AD8F`         | Nến tăng (`MainRenderer`); cũng dùng lại cho chấm SAR khi trend tăng. |
| `dnColor`          | `0xFFD5405D`         | Nến giảm (`MainRenderer`); cũng dùng lại cho chấm SAR khi trend giảm. |
| `kLineColor`       | `0xFF217AFF`         | Đường line chart (`isLine = true`).                              |
| `kLineFillColors`  | gradient blue        | Gradient tô dưới đường line chart.                               |
| `textStyle`        | `fontSize: 10`       | Text main chart: trục giá/thời gian, crosshair, label indicator, max/min, now-price. |

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

## 9. Indicators — main & secondary

### 9.1 Hierarchy

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

### 9.2 Built-in indicators

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
- **`futureShift`:** `IchimokuIndicator.futureShift = shift` — indicator đầu tiên trong thư viện khai báo giá trị này (`MainIndicator.futureShift` mặc định `0`, no-op cho mọi indicator khác). Kích hoạt cơ chế mở rộng trục X ở [12](#12-renderer-internals) mục "Vùng tương lai" — chart tự chừa `shift` nến trống bên phải nến cuối để mây không bị cắt cụt, tự mở rộng biên scroll/zoom tương ứng.
- **Lưu ý:** với chart `itemCount < 52` (chưa đủ nến cho Span B), các field vẫn `null` đúng vị trí warm-up thay vì sentinel `0` — không vẽ đường/mây rác kéo về 0. Crosshair/tap-selection bị clamp về nến thật đang hiển thị, KHÔNG cho chọn vào vùng tương lai trống (đơn giản hoá có chủ đích, xem `ichimoku.md` §7 mục 4 ở root repo).

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

### 9.3 Custom indicator

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

### 9.4 Pattern thêm secondary indicator mới

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

## 10. `DataUtil` & helpers

### 10.1 `DataUtil`

| Method                                          | Effect                                                                      |
| ----------------------------------------------- | --------------------------------------------------------------------------- |
| `calculateAll(data, mains, secondaries)`        | Gọi `calcVolumeMA` + tính tất cả indicator. Phải gọi mỗi khi data thay đổi. |
| `calculateIndicators(data, mains, secondaries)` | Chỉ tính indicator, bỏ qua volume MA.                                       |
| `calculateIndicator(data, indicator)`           | Tính 1 indicator riêng.                                                     |
| `calcVolumeMA(data)`                            | Tính `MA5Volume` & `MA10Volume`.                                            |

**Quan trọng:** Khi load thêm data cũ (left), phải merge list rồi gọi `calculateAll` LẠI trên list mới — indicator phụ thuộc vào toàn bộ historical data.

### 10.2 `NumberUtil`

| Method                                     | Ví dụ                                |
| ------------------------------------------ | ------------------------------------ |
| `NumberUtil.format(value, precision)`      | Format tự động (loại trailing zero). |
| `NumberUtil.formatFixed(value, precision)` | Fix precision (giữ trailing zero).   |

### 10.3 Date format

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

### 10.4 Time-tick planner & price ticks (trục X/Y)

> **Thay thế hoàn toàn** cơ chế cũ ("Auto-detect time format & grid alignment" — chia đều `mGridColumns` cột, format chọn theo khoảng cách 2 candle đầu). Bản cũ có 1 nhược điểm cố hữu: số lượng/vị trí label KHÔNG đổi theo `barSpacing` (zoom) trong 1 phiên — chỉ đổi khi `ChartPainter` được dựng lại với data mới. Bản mới (theo `CHART_AXES.md`, spec tự chứa — đọc file đó nếu cần công thức chính xác) tính lại tick **mỗi frame** theo đúng mức zoom hiện tại. `mGridColumns`/`gridColumns` không còn quyết định gì cho trục thời gian nữa.

**Trục X — `lib/utils/time_ticks.dart`, gọi từ `BaseChartPainter._updateTimeTicks()` (trong `calculateValue()`, 1 lần/frame):**

1. **Tick weight** (`KLineEntity.tickWeight`, cache 1 lần lúc load/append, KHÔNG tính lại mỗi frame): mỗi nến được gán 1 trong 12 bậc `MINOR..YEAR` dựa trên việc timestamp (local time) có rơi đúng ranh giới lịch không (`alignmentWeight`), cộng thêm `crossingWeight` (bắt case nến không thẳng hàng ranh giới local — vd nến 4h ở GMT+7 rơi 03:00/07:00/11:00, không có `hour==0`).
2. **Threshold** (`thresholdRung`): suy TRỰC TIẾP từ hình học (`barSpacing`, `interval`) — KHÔNG đếm số nến hiển thị (đếm sẽ dao động ±1 khi pan, gây nhấp nháy).
3. **Kế hoạch** (`buildTimeTickPlan`, cache qua `TimeTickPlanner` — instance sở hữu bởi `_KChartWidgetState`, key `(identityHashCode(candles), count, barSpacing.round(), interval, format)`): lọc ứng viên qua threshold, đóng gói theo `MIN_GAP_X=64px` trên **absolute space** (`absX(i) = i*barSpacing + barSpacing/2`, KHÔNG trừ `scrollOffset`) — pan không đổi tick nào được chọn (invariant I4). Ưu tiên weight cao trước (đảm bảo ranh giới ngày thắng nến intraday), tie-break theo index. Key có `identityHashCode` để đổi symbol/timeframe (data khác) không tái dùng nhầm plan cũ; `barSpacing` làm tròn px CHỈ trong key (giá trị build thật vẫn chính xác) để pinch-zoom không rebuild toàn dataset gần như mỗi frame.
4. **Chiếu mỗi frame** (`_updateTimeTicks`): lọc lại theo pixel `x = translateXtoX(getX(index)) ∈ [0, mPlotWidth]` — KHÔNG theo margin index, xem fix "label dính cứng ở mép" trong Unreleased.
5. **Label text** — theo `tickWeight` của TỪNG tick: `YEAR→"2026"`, `MONTH→"Aug"`, `DAY→"10"`, còn lại→`"09:05"`. Ép cố định qua `KChartWidget.timeFormat`/`KChartStyle.dateTimeFormat` — xem [6.7](#67-timeformat-constants--ép-format-nhãn-trục-thời-gian).

Kết quả cache vào `BaseChartPainter.mTimeTicks` (`List<({int index, double x, String label})>`) — `drawGrid()` (đường dọc, dùng chung cho main/vol/secondary) VÀ `drawDate()` (label) đều đọc TỪ ĐÂY, không renderer nào tự chọn tick riêng (invariant I3/I6).

**Trục Y — `lib/utils/price_ticks.dart`, gọi từ `MainRenderer` constructor (mỗi frame, renderer bị dựng lại mỗi lần `initChartRenderer()`):**

```dart
niceStep(range, targetTicks)   // ladder 1·2·2.5·5·10 × 10^n
decimalsFor(step)              // KHÔNG suy từ magnitude — sai với họ step 2.5
priceTicks(minPrice: ..., maxPrice: ..., height: ..., targetTicks: 6)
```

Range đưa vào `priceTicks()` là range giá **THỰC SỰ đang hiển thị** (`MainRenderer._priceAtScreenY(chartRect.top/bottom)` — nghịch đảo transform canvas `scaleY`/`offsetY` thật, không phải `minValue`/`maxValue` auto-scale gốc) — nếu dùng range gốc, zoom Y (gesture kéo dọc) sẽ khiến hầu hết tick dạt ra ngoài view (xem fix trong Unreleased). Grid ngang + độ rộng strip giá (`priceAxisWidth`, [12](#12-renderer-internals) "Price axis strip") đều ăn theo cùng `_priceTicks` này.

**Test:** `test/time_ticks_test.dart` (T1-T5: never-blank, min-gap, no-dup-label, pan-stability, append-stability), `test/price_ticks_test.dart` (T6-T7: price ticks trong range, decimals đúng cho họ 2.5) — chạy `flutter test` ở root repo.

---

## 11. `DepthChart` — orderbook depth

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

## 12. Renderer internals

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

**Tick trục X thật sự hiển thị** (`mTimeTicks`, `List<({int index, double x, String label})>`) tính trong `calculateValue()` qua `BaseChartPainter._updateTimeTicks()` — thuật toán weight-ladder đầy đủ ở [10.4](#104-time-tick-planner--price-ticks-trục-xy) + `CHART_AXES.md` §5. `drawGrid()`/`drawDate()` chỉ đọc từ đây, không tự chọn tick.

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

`_applyScaleY` dùng cho label vẽ ngoài canvas transform (nowPrice, maxMin, crosshair). `MainRenderer` có bản NGHỊCH ĐẢO riêng, `_priceAtScreenY(yScreen)` — suy giá TẠI 1 toạ độ Y màn hình, dùng để tính range giá đang thực sự hiển thị rồi sinh tick nice-number theo đó (xem [10.4](#104-time-tick-planner--price-ticks-trục-xy)). 2 hàm này là nghịch đảo của nhau về mặt toán học (cùng công thức `centerY + (v-centerY)*scaleY + offsetY`, chỉ khác `centerY` là `(mMainRect.top+bottom)/2` hay `scaleCenterY` truyền vào — thực chất là 1).

### Vùng tương lai (future zone) — indicator dịch trục (Ichimoku)

Thêm khi implement Ichimoku ([9.2](#92-built-in-indicators)) — cơ chế dùng chung, không hardcode riêng cho 1 indicator. Bất kỳ `MainIndicator` nào override `futureShift` (mặc định `0`) đều tự động được renderer chừa chỗ:

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

| `mPlotWidth` (xFrontPadding=100) | Padding màn hình |
| --------------------------------- | ---------------- |
| ≥ 375px                           | 100px            |
| 250px                              | ~67px            |
| 187px                              | ~50px            |

> Trước khi có strip giá, hàm này dùng thẳng `mWidth` (= `mPlotWidth` lúc đó vì chưa có strip). `effectiveRightPaddingPx` vẫn còn dùng nguyên cho mục đích này; nó KHÔNG còn quyết định bề rộng vùng gesture scaleY nữa — xem [13.3](#133-scale).

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
```

**Quy tắc:** nếu thêm field mới vào `ChartPainter`/`BaseChartPainter` mà ảnh hưởng visual → phải thêm vào `shouldRepaint`, nếu không chart sẽ không cập nhật (đã xảy ra thật với `isLine`, `isTrendLine`/`selectY`/`lines` — xem changelog).

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

## 13. Gesture model

### 13.1 Single tap

- Trong main rect: toggle crosshair.
- `isTrendLine: true`: tap = record điểm cho trend line.

### 13.2 Long press

- Hiện crosshair + drag để di chuyển.
- Phát `InfoWindowEntity` qua stream → `detailBuilder` render dialog.

### 13.3 Scale

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
| 1 ngón drag tự do                 | `mScrollX += dx / mScaleX`. Pan Y chỉ active khi `mScaleY != 1.0`. |

**Gesture gate vol/secondary:**

```
Finger chạm vol/secondary + 1 ngón:
  dx → scrollX nến (như main)
  dy → forward onVerticalOverscroll (KHÔNG pan chart Y)
Pinch ≥2 ngón: scaleX bình thường
```

### 13.4 Clamp `mOffsetY`

```dart
double _clampOffsetY(double v) {
  final maxOffset = mBaseHeight * mScaleY / 2;
  return v.clamp(-maxOffset, maxOffset);
}
```

### 13.5 Overscroll handoff

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

### 13.6 Double-tap (vùng phải scaleY)

Double-tap trong cùng vùng `priceAxisWidth` ở trên → reset `mScaleY = 1.0`, `mOffsetY = 0.0`.

### 13.7 Fling

Sau drag end, animation Tween chạy với `flingTime` ms, `flingCurve`, `flingRatio` × velocity.

### 13.8 Auto-compensate scroll khi append nến mới

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

### 13.9 Auto-load khi data chưa lấp đầy chart (không cần gesture)

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

---

## 14. Recipes — công thức thường dùng

### 14.1 Live tick

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

### 14.2 Load more khi scroll trái

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

### 14.3 Dark theme

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

### 14.4 Toggle nhiều secondary

```dart
List<SecondaryIndicator> get _secondary => [
  if (showMACD) MACDIndicator(),
  if (showKDJ) KDJIndicator(),
  if (showRSI) RSIIndicator(),
];
```

### 14.5 Custom date format

```dart
KChartWidget(
  data, style, colors,
  detailBuilder: ...,
  isTrendLine: false,
  timeFormat: const [dd, '/', mm, ' ', hour24Padded, ':', nn],
)
```

### 14.6 Watermark logo

```dart
KChartWidget(
  ...,
  backgroundLogo: SvgPicture.asset('assets/logo.svg', width: 80, height: 80),
  backgroundLogoOpacity: 0.15,
)
```

### 14.7 External zoom buttons

```dart
final ctrl = KChartController();
KChartWidget(..., controller: ctrl)
IconButton(onPressed: ctrl.zoomIn, icon: Icon(Icons.zoom_in))
IconButton(onPressed: ctrl.zoomOut, icon: Icon(Icons.zoom_out))
IconButton(onPressed: ctrl.reset, icon: Icon(Icons.refresh))
```

### 14.8 Lưu/khôi phục zoom state khi đổi timeframe

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

### 14.10 Real-time WebSocket price ticker

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

### 14.9 Overscroll handoff sang outer scrollview

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

## 15. Troubleshooting & pitfalls

### "Indicator không hiện"

- Đã gọi `DataUtil.calculateAll(data, mains, secondaries)` chưa? Phải gọi lại MỖI khi list data thay đổi.
- Đủ data cho period chưa? VD MA30 cần ≥30 nến.

### "Sai data sau load more"

- Phải merge `[...older, ...current]` ROI `calculateAll` lại trên list merged.

### "Time hiển thị sai"

- `time` phải là **milliseconds** Unix epoch. Nếu API trả seconds, nhân 1000.

### "Crosshair label dính vào cạnh"

- Tăng `xFrontPadding` (mặc định 100px tại chart ≥375px).

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

## 16. Phân tích cơ chế Y Grid & Anchor Zoom (MEXC / TradingView)

> Tổng hợp từ phân tích kỹ thuật `anchor_zoom.md` và `scroll_vertical_y.md`. Đây là tham khảo thiết kế — k_chart_jk hiện dùng mô hình `mScaleY + mOffsetY` (canvas transform), không phải `visibleMinPrice / visibleMaxPrice` làm state chính.
>
> **Cập nhật:** phần **16.2 Dynamic Y Grid** bên dưới giờ **đã implement**, chỉ khác cách tiếp cận — không lưu `visibleMinPrice`/`visibleMaxPrice` làm state, mà mỗi frame `MainRenderer` NGHỊCH ĐẢO transform `mScaleY`/`offsetY` hiện có để suy ra range đang hiển thị (`_priceAtScreenY`), rồi sinh nice-number step từ range đó (`lib/utils/price_ticks.dart`, xem [10.4](#104-time-tick-planner--price-ticks-trục-xy)) — cùng kết quả cuối (grid tự thích ứng, không nhảy), khác cơ chế lưu trữ. 16.1 (Vertical Scroll bằng `visibleMinPrice`/`visibleMaxPrice`) và 16.3 (Anchor Zoom tường minh) vẫn CHỈ là tham khảo, chưa áp dụng — `mScaleY`/`offsetY` hiện tại không anchor chính xác tại điểm chạm khi zoom Y (chỉ có `zoomAt` cho trục X làm việc này — xem `CHART_AXES.md` §4).

### 16.1 Vertical Scroll — di chuyển khoảng giá

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

### 16.2 Dynamic Y Grid

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

### 16.3 Anchor Zoom

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
