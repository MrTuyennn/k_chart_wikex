# Changelog

Tổ chức theo **ngày** (mới nhất ở trên). Với các mốc đã đóng gói thành version cụ thể (pub.dev), ngày là ngày commit bump version trong `pubspec.yaml`; các mục chưa lên version mới ghi theo ngày thực hiện trong lịch sử commit / working tree.

> Chi tiết kiến trúc, công thức, API đầy đủ nằm ở [`chart_jk_arch.md`](chart_jk_arch.md) — file đó **không còn** giữ changelog, chỉ còn tài liệu tham khảo.

---

## 2026-08-11

- **fix (example app):** `_onRealtimeFlushed` (`ChartBloc`) merge tick WS vào nến đang chạy qua `mergeKlineBar`/`mergeIntoRunningCandle` (`example/lib/bloc/kline_merge.dart`) — sửa 2 điều liên quan tới báo lỗi "nhãn trục thời gian hiện giờ tương lai" (khung 15', chưa tới giờ mà trục đã hiện mốc sau):
  - So khớp "cùng nến đang chạy" giờ chấp nhận **cả 2 cách đọc** timestamp WS — `wsTime == existingTime` (open-time, đã verify qua REST) hoặc `wsTime == existingTime + intervalMs` (close-time, giả thuyết dựa trên tên field `barCloseTime` — **chưa verify được 100%** vì không snoop được payload WS trực tiếp trong môi trường dev). Trước đây so `==` cứng theo open-time, nên nếu WS thật ra gửi close-time thì tick đầu của mỗi nến bị lệch 1 interval, rơi vào nhánh "nến mới" và tạo entry trùng nến với timestamp tương lai — tồn tại vĩnh viễn.
  - `mergeIntoRunningCandle` không còn lấy `time` từ tick WS — luôn giữ `existing.time`, cùng nguyên tắc với `open`.
  - File: `example/lib/bloc/kline_merge.dart`, `example/lib/bloc/chart_bloc.dart`, `example/test/kline_merge_test.dart`.
- **feat (example app):** Nhãn trục thời gian ép format theo ĐÚNG khung đang chọn (`ChartTimeframe.axisTimeFormat`) thay vì thuật toán thích ứng theo `tickWeight` hay `mFormats` suy từ khoảng cách data — phút (1m/5m/15m/30m) → `HH:mm`; giờ (1H/4H) → `MM-dd HH:mm`; ngày (1D) → `yy-MM-dd`. Không đụng thuật toán CHỌN TICK (weight-ladder) — chỉ đổi CHỮ hiển thị.
  - File: `example/lib/bloc/chart_state.dart`, `example/lib/main.dart`.
- **feat (example app):** `ChartTimeframe` thêm 3 khung `m1`/`m5`/`m30` — đủ bộ 1m/5m/15m/30m/1H/4H/1D. Kèm fix Row chip timeframe tràn ngang (`RenderFlex overflowed`) — bọc `SingleChildScrollView(scrollDirection: Axis.horizontal)`.
  - File: `example/lib/bloc/chart_state.dart`, `example/lib/main.dart`.
- **note (đã thử qua lại nhiều lần trong quá trình làm, chốt lại 1 lần ở đây để khỏi nhầm):** `KChartWidget.timeFormat`/nhãn trục thời gian đã đổi qua lại nhiều công thức trong quá trình phát triển (ép `dd-mm HH:mm` viết tay → adaptive theo `tickWeight` §5.3 → preset `TimeFormat.yearMonthDay(WithHour)` → `mFormats` (công thức trước CHART_AXES.md) → theo timeframe hiện tại — bullet ngay trên). **Trạng thái cuối cùng** là bullet "Nhãn trục thời gian ép format theo ĐÚNG khung đang chọn" ở trên.
- **perf/fix (từ `/code-review` trên diff trục X/Y):** 2 performance + 2 correctness, không đổi thuật toán/output đã chốt:
  - **perf:** `TimeTickPlanner`'s cache key làm tròn `barSpacing` về px nguyên (trước đó là số thực đổi liên tục theo `scaleX` lúc pinch-zoom → cache-miss gần như mỗi frame → rebuild lại toàn dataset).
  - **perf:** `MainRenderer.measureMaxLabelWidth`/`drawVerticalText` dựng lại `TextPainter` mỗi frame dù style/range không đổi → thêm `_priceLabelCache` (`static final Map<(String,TextStyle), TextPainter>`).
  - **fix:** cache tick thời gian có thể trả nhầm data khi đổi symbol/timeframe (cache key cũ không phụ thuộc identity/nội dung data) → thêm `identityHashCode(candles)` vào key.
  - **fix:** `priceAxisWidth` + cache `TimeTickPlanner` từng là `static`, rò rỉ giữa nhiều `KChartWidget` vẽ đồng thời (watchlist mini-chart) → chuyển thành field instance sở hữu bởi `_KChartWidgetState`, truyền xuống `BaseChartPainter`/`ChartPainter` qua constructor (**breaking** cho ai tự implement `BaseChartPainter` ngoài package).
  - File: `lib/utils/time_ticks.dart`, `lib/renderer/base_chart_painter.dart`, `lib/renderer/chart_painter.dart`, `lib/renderer/main_renderer.dart`, `lib/k_chart_widget.dart`.
- **fix:** `drawDate()` đổi sang **clip canvas** (`canvas.clipRect(0, mDateRect.top, mPlotWidth, mDateRect.bottom)`) thay vì kẹp text vào màn hình — label vẽ ở đúng `tick.x` thật, canvas tự cắt phần thừa khi trượt qua mép, y hệt cách nến/volume đã luôn được clip — hết khái niệm ẩn/hiện đột ngột ở 2 mép khi scroll.
  - File: `lib/renderer/chart_painter.dart`.
- **feat (example app):** Cờ `_kIndicatorsEnabledByDefault` (`bool`) — tắt hết indicator mặc định trong demo (trước đây bật sẵn toàn bộ 6 main + 9 secondary). Test `persistent_isolate_test.dart` cập nhật assertion theo (`contains` thay vì `isNot(contains)`).
  - File: `example/lib/bloc/chart_state.dart`, `example/test/persistent_isolate_test.dart`.
- **docs:** Đổi cấu trúc tài liệu — `chart_jk_arch.md` không còn giữ changelog, dồn hết vào `CHANGELOG.md` này (tổ chức theo ngày thay vì semver) để `chart_jk_arch.md` chỉ còn kiến trúc/công thức/API.
  - File: `CHANGELOG.md`, `chart_jk_arch.md`.

## 2026-08-10

- **feat (breaking — thiết kế lại trục X/Y):** Viết lại toàn bộ cơ chế trục thời gian + trục giá theo spec `CHART_AXES.md` (file mới, tự chứa). Thay hẳn cơ chế "chia đều pixel theo `mGridColumns`" cũ bằng 2 module thuần độc lập test được: `lib/utils/time_ticks.dart` (trục X) + `lib/utils/price_ticks.dart` (trục Y). Xem chi tiết ở [`chart_jk_arch.md`](chart_jk_arch.md) §9.4 và §11.
  - **Trục X — weight ladder thay vì chia cột đều:** mỗi nến gán 1 `tickWeight` (cache 1 lần — có rơi đúng ranh giới lịch giờ/ngày/tháng/năm theo local time không). Mỗi frame chọn threshold-bậc từ hình học thuần (`barSpacing`, `interval`), đóng gói ứng viên theo `MIN_GAP_X=64px` trên absolute space (pan không đổi tick nào được chọn), lọc lại theo pixel thật. Cache tĩnh (`TimeTickPlanner`) chỉ rebuild khi zoom/data đổi.
  - **Trục Y — nice-number thay vì chia đều `gridRows`:** ladder `1·2·2.5·5·10 × 10^n`, số thập phân suy từ chính `step`. `MainRenderer` tính lại tick mỗi frame từ range giá đang thực sự hiển thị (đã áp gesture zoom/pan dọc).
  - **Layout — price axis tách strip riêng bên phải:** `BaseChartPainter` thêm `mPlotWidth`/`mPriceAxisRect`/`mCornerRect`; mọi rect panel chỉ rộng `mPlotWidth = mWidth - priceAxisWidth`. Width tự đo theo label rộng nhất, clamp `[48,96]`, làm tròn bội 8, có hysteresis.
  - **Gesture:** vùng kéo dọc scaleY + double-tap reset dùng đúng `priceAxisWidth` thật; fix `mMainRect` hẹp lại khiến gesture scaleY hợp lệ bị nuốt mất ở nhánh "outside main".
  - File: `CHART_AXES.md` (mới), `lib/utils/time_ticks.dart` (mới), `lib/utils/price_ticks.dart` (mới), `lib/entity/k_line_entity.dart` (`tickWeight`), `lib/renderer/base_chart_painter.dart`, `lib/renderer/base_chart_renderer.dart`, `lib/renderer/chart_painter.dart`, `lib/renderer/main_renderer.dart`, `lib/renderer/vol_renderer.dart`, `lib/renderer/secondary_renderer.dart`, `lib/k_chart_widget.dart`, `lib/utils/index.dart`, `test/time_ticks_test.dart` (mới), `test/price_ticks_test.dart` (mới).
- **fix:** Label trục thời gian "dính cứng" ở 2 đầu mép khi zoom vào — do lọc tick theo margin index thay vì pixel thật. Sửa: lọc nghiêm ngặt theo `x ∈ [0, mPlotWidth]`.
- **fix:** Tick trục giá không thích ứng theo gesture zoom dọc — trước tính 1 lần từ `minValue`/`maxValue` gốc. Thêm `MainRenderer._priceAtScreenY()` (nghịch đảo chính xác transform canvas thật) để tính range giá đang thực sự hiển thị rồi sinh tick nice-number theo range đó.
  - File: `lib/renderer/main_renderer.dart`.
- **fix (example app):** REST fetch lịch sử nến (`ChartBloc._loadHistory`) trả về ít hơn hẳn `initialBatchSize` khi sàn có gap/downtime gần hiện tại (gặp thật ở khung 15m — gap ~2 ngày khiến cửa sổ 200 nến chỉ nhận ~46). Sửa: nếu fetch đầu không đủ mà server chưa trả rỗng, tự mở rộng cửa sổ lùi xa hơn (×4/lần, tối đa 4 lần) rồi thử lại.
  - File: `example/lib/bloc/chart_bloc.dart`.
- **implement rồi revert theo yêu cầu (ghi lại để khỏi làm lại nhầm):** CHART_AXES.md §6.6 (instrument tick size) và §6.7 (drawing the price strip — occlusion, "drop rather than drag", tabular figures, `exp`-based scale+lock) đã implement đầy đủ kèm test T9-T12, sau đó revert toàn bộ theo yêu cầu — không còn trong code/spec hiện tại.

## 2026-08-04

- **style (example app):** Cập nhật lại bộ màu demo — indicator style mặc định, `DepthChartStyle`, `KChartStyle`, `LivePriceStyle`.
  - File: `example/lib/bloc/chart_state.dart`, `example/lib/main.dart`, `lib/indicator/indicator_style.dart`, `lib/styles/depth_chart_style.dart`, `lib/styles/k_chart_style.dart`, `lib/styles/live_price_style.dart`.

## 2026-07-28

- **feat:** `ATRIndicator` (ATR) — secondary indicator Average True Range (Wilder). `calcParams: [14, 6]` (N: chu kỳ làm mượt Wilder, M: chu kỳ MA tín hiệu). `TR = max(high-low, |high-prevClose|, |low-prevClose|)`; `ATR` seed bằng `SMA(TR,N)` rồi làm mượt Wilder `ATR[i] = (TR[i] + (N-1)×ATR[i-1])/N`; `MAATR = MA(ATR,M)`. Đo độ biến động, không đo hướng xu hướng.
  - File: `lib/entity/atr_entity.dart` (mới), `lib/entity/macd_entity.dart` + `lib/entity/k_entity.dart` (nối `ATREntity`, trước `MACDEntity`), `lib/indicator/indicator_style.dart` (`ATRStyle`), `lib/indicator/secondary/atr_indicator.dart` (mới), `lib/indicator/indicator_template.dart`, `lib/styles/k_chart_style.dart`, `example/lib/bloc/chart_state.dart`, `example/lib/bloc/chart_bloc.dart`, `example/lib/main.dart` (chip + `_demoColors`).

## 2026-07-22

- **feat (thêm lại sau revert 07-18):** `IchimokuIndicator` (Ichimoku Kinko Hyo) — main indicator thứ 8, dựa trên spec `ichimoku.md` (root repo). `calcParams: [9, 26, 52]` (tenkan/kijun/spanB period); `shift` luôn = kijun period, không hardcode `26`. 5 đường: Tenkan-sen/Kijun-sen (vẽ tại index gốc), Senkou Span A/B (dịch **tới trước** `shift` nến — mây/Kumo), Chikou (dịch **lùi** `shift` nến, = `close`). Kumo tách polygon tại điểm Span A/B giao nhau (nội suy tuyến tính) để tô đúng 2 màu tăng/giảm.
  - **Khác biệt cốt lõi so với bản V1/V2 đã gỡ**: Span A/B/Chikou vẫn lưu 1 giá trị/nến TẠI INDEX GỐC (giống mọi indicator khác) thay vì mảng dài `n+shift` như V2 cũ — phần dịch `±shift` chỉ là cộng/trừ `shift × pointWidth` vào toạ độ X **ngay tại draw-time**, không kéo dài entity/mảng dữ liệu. Cơ chế mở rộng trục X dùng chung rút gọn còn đúng 1 property `MainIndicator.futureShift` (mặc định `0`) thay vì 3 hook `requiredFutureBars`/`getFutureMaxMinValue`/`drawFutureSegment` của V2 cũ — indicator dịch trục khác chỉ cần override `futureShift`. Renderer tự tính `mFutureSlots = max(futureShift)`, tự mở rộng `mDataLen`/biên scroll/binary-search index.
  - `calc()` dùng sliding-window monotonic deque O(n) cho cả 3 chu kỳ HH/LL (không phải naive O(n×52) — tránh giật khi pan/zoom).
  - **7 bug phát hiện qua `/code-review` (high effort, 8 finder angle)** trên phần thêm lại này, cùng 1 nguyên nhân gốc: vòng quét/vẽ rộng hơn viewport (`mRealStartIndex`/`mRealStopIndex`, chừa đủ nến nguồn cho đường bị dịch) bị tái sử dụng nhầm cho việc PHẢI gắn chặt với "nến đang thực sự hiển thị" — label max/min giá lệch vị trí/vô hình khi extreme nằm ngoài viewport; label chỉ số góc trên hiện sai nến khi cuộn giữa lịch sử; autoscale trục Y main/volume/secondary bị nến off-screen ảnh hưởng; field public `currentStartIndex` có thể vượt bound dữ liệu thật (`RangeError` cho consumer ngoài package); `IchimokuIndicator.pointWidth` có nguy cơ lệch khỏi `KChartStyle.pointWidth` nếu class này cho phép subclass. Sửa: tách `mVisibleStartIndex`/`mVisibleStopIndex` (hẹp, đúng viewport) khỏi `mRealStartIndex`/`mRealStopIndex` (rộng, chỉ dùng cho vẽ + Y-range riêng của indicator có dịch trục), clamp `currentStartIndex`, `KChartStyle` → `final class` (khoá subclass ghi đè `pointWidth`). Nhân tiện fix lãng phí `2×mFutureSlots` draw call/frame.
  - **Docs:** `architecture.md` thêm §3.5 "Vùng tương lai" (cơ chế dịch trục dùng chung, bảng 3 phạm vi index, cảnh báo MUST MATCH cho lớp bug vừa fix); `ichimoku.md` check lại checklist theo thực tế đã ship, thêm ghi chú khác biệt giữa bản thật và spec gốc (draw-time pixel-shift thay vì mảng đã dịch sẵn).
  - File: `lib/entity/candle_entity.dart` (field `ichimoku`), `lib/indicator/indicator_style.dart` (`IchimokuStyle`), `lib/indicator/indicator_template.dart` (`futureShift` getter, switch case), `lib/indicator/main/ichimoku_indicator.dart` (mới), `lib/styles/k_chart_style.dart` (→ `final class`), `lib/renderer/base_chart_painter.dart`, `lib/renderer/chart_painter.dart`, `example/lib/bloc/chart_state.dart`, `example/lib/bloc/chart_bloc.dart`, `example/lib/main.dart`, `architecture.md`, `ichimoku.md`.

## 2026-07-20

- **feat:** `PSYIndicator` (PSY) — secondary indicator thứ 12, Psychological Line / 心理线. `calcParams: [12, 6]` (N: chu kỳ đếm phiên tăng, M: chu kỳ MA tín hiệu). `PSY = COUNT(close > REF(close,1), N) / N × 100`; `MAPSY = MA(PSY, M)`. Cần `REF(close,1)` nên đủ dữ liệu tại `i=N` (không phải `i=N-1`) — cùng loại "trễ 1 nến khởi tạo" như `BR` của BRAR. Đo % số phiên tăng trong N phiên gần nhất — quá cao (>75-83) dễ điều chỉnh giảm, quá thấp (<25-17) dễ hồi phục.
  - File: `lib/entity/psy_entity.dart` (mới), `lib/entity/macd_entity.dart` + `lib/entity/k_entity.dart` (trước `MACDEntity`, cùng vị trí `BIASEntity`), `lib/indicator/indicator_style.dart` (`PSYStyle`), `lib/indicator/secondary/psy_indicator.dart` (mới), `lib/indicator/indicator_template.dart`, `lib/styles/k_chart_style.dart`, `example/lib/bloc/chart_state.dart`, `example/lib/bloc/chart_bloc.dart`, `example/lib/main.dart`.

## 2026-07-18

- **revert:** Ichimoku Cloud (main indicator, cả V1 lẫn V2 chiếu cloud ra "tương lai") gỡ **hoàn toàn** khỏi codebase theo yêu cầu — không chỉ tắt trong demo. Rà lại toàn bộ `lib/` + `example/`, không còn field/class/wiring nào sót, kể cả 3 hook chung `requiredFutureBars`/`getFutureMaxMinValue`/`drawFutureSegment` (thêm vào `IndicatorTemplate`/`BaseChartPainter`/`MainRenderer` riêng cho V2, dù no-op không ảnh hưởng indicator khác). *(Thêm lại theo yêu cầu 4 ngày sau — xem 2026-07-22.)*
- **feat:** `BRARIndicator` (BRAR) — secondary indicator thứ 10, Popularity/Willingness Index (人气意愿指标). `calcParams: [26]`, rolling-sum O(n): `AR = Σ(high-open,26)/Σ(open-low,26)×100`, `BR = Σmax(0,high-prevClose,26)/Σmax(0,prevClose-low,26)×100`, guard chia 0 → `0.0`. `BR` cần `prevClose` nên trễ hơn `AR` đúng 1 nến ở warm-up. Đo tâm lý thị trường qua biên độ nến (khác RSI chỉ nhìn close) — AR/BR cùng cao (>150-200) → quá hưng phấn; cùng thấp (<50) → quá bi quan.
  - File: `lib/entity/brar_entity.dart` (mới), `lib/entity/macd_entity.dart` + `lib/entity/k_entity.dart`, `lib/indicator/indicator_style.dart` (`BRARStyle`), `lib/indicator/secondary/brar_indicator.dart` (mới), `lib/indicator/indicator_template.dart`, `lib/styles/k_chart_style.dart`, `example/lib/bloc/chart_state.dart`, `example/lib/bloc/chart_bloc.dart`, `example/lib/main.dart`.
- **feat:** `BIASIndicator` (BIAS) — secondary indicator thứ 11, Bias Ratio / 乖离率. `calcParams: [6, 12, 24]` — nhiều chu kỳ cùng lúc (cùng pattern `MAStyle.maColors`, khác BRAR/KDJ dùng field cố định). `BIAS(n) = (close - MA(close,n))/MA(close,n) × 100%`, rolling-sum O(n). Output dùng `double?` (không sentinel `0` như MA) vì BIAS hợp lệ đi qua 0 rất thường xuyên (giá cắt MA) — sentinel sẽ nhầm "giá == MA" với "chưa tính xong".
  - File: `lib/entity/bias_entity.dart` (mới), `lib/entity/macd_entity.dart` + `lib/entity/k_entity.dart`, `lib/indicator/indicator_style.dart` (`BIASStyle`), `lib/indicator/secondary/bias_indicator.dart` (mới), `lib/indicator/indicator_template.dart`, `lib/styles/k_chart_style.dart`, `example/lib/bloc/chart_state.dart`, `example/lib/bloc/chart_bloc.dart`, `example/lib/main.dart`.

## 2026-07-17

- **fix (4 bug correctness qua `/code-review` high effort, 8 finder angle + verify):**
  - **KDJ null-check `||` thay vì `&&`:** `KDJIndicator.drawChart` vẽ K/D/J khi `curPoint.k != null || lastPoint.k != null` rồi force-unwrap cả 2 bằng `!` — 1 điểm null (vd nến mới append từ tick live chưa kịp `calc()`) → crash `Null check operator used on a null value`. Sửa: `||` → `&&`, khớp pattern RSI/WR/MTM/TRIX/StochRSI.
    - File: `lib/indicator/secondary/kdj_indicator.dart`.
  - **SAR không đọc `indicatorStyle`, hard-code màu theo `candleStyle` main chart:** set màu qua `KChartColors.sarStyle` chỉ đổi được label, không đổi được chấm. Sửa: `SARStyle` đổi `sarColor` (1 màu) thành `upColor`/`dnColor` (convention `SuperTrendStyle`) — chấm và label cùng tự chọn màu theo xu hướng thật (`sar <= (high+low)/2` = tăng → `upColor`).
    - File: `lib/indicator/main/sar_indicator.dart`, `lib/indicator/indicator_style.dart`, `example/lib/main.dart`.
  - **`LivePriceStyle.textStyle` không fallback màu:** không set `color` ra chữ đen mặc định, gần như vô hình trên badge màu. Sửa: dùng chung helper mới `resolveTextStyle(base, fallback, {forceColor})`, fallback `Colors.white`.
    - File: `lib/renderer/chart_painter.dart`.
  - **Alpha ghi đè thay vì nhân dồn — còn sót ở 2 renderer sau fix 07-16:** `MainRenderer` (`bgColor.withAlpha(80)`) và `SecondaryRenderer` (`defaultTextColor.withAlpha(90)`). Sửa cùng pattern: `color.withValues(alpha: color.a * factor)`.
    - File: `lib/renderer/main_renderer.dart`, `lib/renderer/secondary_renderer.dart`.
- **cleanup/efficiency (cùng đợt code review):**
  - Gom logic fallback màu textStyle (lặp lại độc lập ở 6 chỗ/5 file) thành `resolveTextStyle()` dùng chung.
    - File: `lib/utils/text_style_util.dart` (mới), áp dụng ở `chart_painter.dart`, `vol_renderer.dart`, `secondary_renderer.dart`, `indicator_template.dart`, `depth_chart.dart`.
  - Thay `identical(indicatorStyle, const XxxStyle())` (không phân biệt được "không truyền" với "truyền const y hệt default" do Dart const-canonicalization) bằng field `isDefaultStyle` tường minh — constructor cả 16 indicator đổi `indicatorStyle` sang `XxxStyle?` nullable, `isDefaultStyle = (indicatorStyle == null)`.
    - File: `lib/indicator/indicator_template.dart` + 16 file `lib/indicator/{main,secondary}/*.dart`.
  - `getTextStyle`'s `forceColor` đổi từ positional bool sang named param (`getTextStyle(color, base: style, forceColor: true)`).
    - File: `lib/indicator/indicator_template.dart` + ~30 call site.
  - `LivePriceBadgePainter` cache `Paint`/`Path` thành `static` thay vì dựng mới mỗi `paint()` (chạy mỗi frame theo tick giá live không throttle). `applyIndicatorColorStyles()` cache theo `identical()` của bộ 3 tham số đầu vào — bỏ qua switch 16-case khi không đổi giữa 2 lần `ChartPainter` dựng liên tiếp.
    - File: `lib/styles/live_price_style.dart`, `lib/indicator/indicator_template.dart`.
- **fix (lint `library_private_types_in_public_api`):** `DepthChart.createState()` trả về kiểu private `_DepthChartState` trong API public — đổi sang `State<DepthChart>` (đúng pattern đã áp dụng từ commit `c1d04f8` cho chính widget này trước đây, có lẽ bị lệch lại qua refactor sau).
  - File: `lib/depth_chart.dart`.

## 2026-07-16

- **feat:** `LivePriceStyle` + `LivePriceBadgePainter` (now-price badge). Tách `nowPriceUpColor`/`nowPriceDnColor` khỏi `KChartColors` thành model riêng, cùng convention `CandleStyle`/`VolumeStyle` dựng hôm 07-15 — `upColor`/`dnColor` CHỈ tô nền badge + đường kẻ ngang, màu CHỮ luôn lấy từ `textStyle.color` riêng (mặc định `Colors.white`, không dùng chung màu nền cho chữ — nền đặc + chữ cùng màu sẽ vô hình).
  - Badge "flag" (nền bo góc + mũi tên nhỏ trỏ trái) convert từ `assets/Number.svg` (`viewBox="0 0 54 14"`), gắn thẳng vào `ChartPainter.drawNowPrice()` thay `RRect + border` phẳng cũ. Nền + mũi tên cùng nhân 1 cặp tỉ lệ `scaleX/scaleY` theo viewBox thật — bug ban đầu: chỉ nền được scale, mũi tên để nguyên toạ độ tuyệt đối → lệch khi badge không đúng 54×14. Mũi tên trỏ trái khớp đúng khi badge ở mép PHẢI chart (mặc định); dùng `left` thì mũi tên trỏ ra ngoài (hạn chế asset gốc, chưa có bản mirror).
  - Padding badge đổi `(3, 1.5)` → `(5, 3)`. Xoá 2 field thừa `nowPriceSelectorPaint`/`nowPriceSelectorBorderPaint`.
  - File: `lib/styles/live_price_style.dart` (mới), `lib/renderer/chart_painter.dart`.
- **feat:** `textStyle` riêng từng indicator style — thêm field vào base class `IndicatorStyle` (default `fontSize: 10`), forward qua `super.textStyle` ở 15 subclass. Label mỗi indicator giờ chỉnh font độc lập, thay vì dùng chung `candleStyle.textStyle` như fix 07-15.
  - File: `lib/indicator/indicator_style.dart`, `lib/indicator/indicator_template.dart` + 16 file.
- **fix:** Volume bar opacity bị ghi đè thay vì nhân dồn — `VolRenderer.drawChart` dùng `base.withValues(alpha: chartStyle.volBarOpacity)`, ghi đè hoàn toàn alpha sẵn có của `volumeStyle.upColor`/`dnColor`. Sửa: `base.withValues(alpha: base.a * chartStyle.volBarOpacity)` — nhân dồn, kết hợp được cả 2 nguồn alpha.
  - File: `lib/renderer/vol_renderer.dart`.
- **fix:** `textStyle.color` tự set bị ghi đè vô điều kiện ở 5 nơi — `getTextStyle()`/`getTextPainter()` luôn `.copyWith(color: màuNgữNghĩa)`. Sửa: chỉ copy màu ngữ nghĩa khi `textStyle.color == null`; không breaking (mặc định không set `color` vẫn giữ hành vi cũ).
  - File: `lib/renderer/chart_painter.dart` (`candleStyle.textStyle`), `lib/renderer/vol_renderer.dart` (`volumeStyle.textStyle`), `lib/indicator/indicator_template.dart` (`indicatorStyle.textStyle`), `lib/depth_chart.dart` (`chartStyle.textStyle` + `annotationTextStyle`).

## 2026-07-15

- **refactor (breaking):** `KChartColors`/`KChartStyle` tái cấu trúc toàn bộ — gom màu/text theo khu vực thay vì field rời rạc, cho phép cấu hình màu indicator từ 1 chỗ duy nhất.
  - `CandleStyle` (main chart) + `VolumeStyle` (panel volume) — mỗi class tự chứa cả màu lẫn `textStyle` riêng. Thay thế `kLineColor`, `kLineFillColors`, `upColor`, `dnColor`, `ma5Color`, `ma10Color`, `volUpColor`, `volDnColor`. Xoá `volColor` (dead field).
  - 16 field style indicator thêm vào `KChartColors` (`maStyle`, `emaStyle`, `bollStyle`, `sarStyle`, `zigzagStyle`, `superTrendStyle`, `avlStyle`, `macdStyle`, `kdjStyle`, `rsiStyle`, `wrStyle`, `cciStyle`, `obvStyle`, `trixStyle`, `mtmStyle`, `stochRsiStyle`) — `applyIndicatorColorStyles()` (chạy 1 lần trong constructor `ChartPainter`) gán màu, chỉ khi instance còn dùng style mặc định.
  - `KChartColors.copyWith()` — method mới. Text style dời hẳn khỏi `KChartStyle` vào `CandleStyle.textStyle`/`VolumeStyle.textStyle`.
  - `example/lib/main.dart`/`chart_bloc.dart` cập nhật theo API mới — state mặc định bật sẵn toàn bộ 6 main + 9 secondary indicator (giai đoạn này; đã tắt lại sau, xem 2026-08-11).
  - File: `lib/styles/k_chart_style.dart`, `lib/indicator/indicator_template.dart`, `lib/indicator/indicator_style.dart`, `lib/indicator/main/sar_indicator.dart`, `lib/renderer/{base_chart_painter,chart_painter,main_renderer,vol_renderer}.dart`, `example/lib/bloc/chart_bloc.dart`, `example/lib/main.dart`, `example/test/persistent_isolate_test.dart`.
- **fix (5 bug correctness qua `/code-review` high effort):**
  - `AVLIndicator`/`ZigZagIndicator`/`BOLLIndicator._fillPaint` bake màu Paint 1 lần trong constructor, không đọc lại khi vẽ → set màu qua `KChartColors` không có tác dụng lên đường/vùng tô (chỉ đổi được label). Sửa: đọc lại `indicatorStyle.xxxColor` ngay trước mỗi lần vẽ.
    - File: `lib/indicator/main/avl_indicator.dart`, `zigzag_indicator.dart`, `boll_indicator.dart`.
  - `applyIndicatorColorStyles()` "đơ" màu sau lần áp đầu tiên — `identical(indicatorStyle, const XxxStyle())` không còn `identical` sau khi tự gán 1 lần, nên build sau (vd đổi theme runtime) không áp lại màu mới nếu app giữ instance ổn định. Sửa: thêm `_originalIndicatorStyle` (snapshot bất biến lúc khởi tạo), so `identical()` với snapshot.
    - File: `lib/indicator/indicator_template.dart`.
  - `VolumeStyle.textStyle` không áp cho label trục volume — `ChartPainter.drawVerticalText` tính chung 1 `textStyle` cho cả main lẫn volume renderer. Sửa: gọi riêng `mVolRenderer.getTextStyle(...)`.
    - File: `lib/renderer/chart_painter.dart`.
  - Label indicator không đổi font theo `KChartColors` — `IndicatorTemplate.getTextStyle` hard-code `fontSize: 10`. Sửa: nhận thêm param `base`, mọi `drawFigure()` (16 file) truyền `chartColors.candleStyle.textStyle` vào (nâng cấp tiếp thành `indicatorStyle.textStyle` riêng từng indicator ở 07-16).
    - File: `lib/indicator/indicator_template.dart` + 16 file.
- **cleanup (non-correctness, cùng đợt code review):** `applyIndicatorColorStyles()` gộp switch 16 case thành 1 helper generic `_applyDefaultStyle<K>()` (rút từ ~90 dòng còn ~45); `DepthChartStyle` thêm `textStyle`/`annotationTextStyle` (cùng convention `CandleStyle`/`VolumeStyle`); `example/lib/main.dart` cache `_mainIndicatorsFor`/`_secondaryIndicatorsFor` theo nội dung `Set` (trước đó mỗi tick `livePrice` không throttle kéo theo rebuild lại toàn bộ 15 indicator + Paint dù `mainTypes`/`secondaryTypes` không đổi).

## 2026-07-09

- **fix:** Main Indicator hỗ trợ chọn nhiều (multi-select), giống Secondary Indicator — `_MainType` từ single enum (giá trị `none`) đổi sang `Set<_MainType> _mainTypes`, có thể bật đồng thời nhiều indicator (MA, BOLL, EMA, SuperTrend, ZigZag, AVL) cùng lúc. Bỏ chọn hết chip tương đương "không có main indicator" (bỏ giá trị `none`). Đổi `_setMain(type)` → `_toggleMain(type)`.
  - File: `example/lib/main.dart`.
- **investigated, revert theo yêu cầu (chưa merge):** Tối ưu live-tick bằng `livePrice` (tách giá tick khỏi `_data`, chỉ gọi `DataUtil.calculateAll` khi nến thực sự đóng thay vì mỗi tick) — DevTools Performance Overlay cho thấy `_tickInterval` 50ms khiến `_updateLastCandle` gọi full O(n) recalc ở MỌI tick, jank ~13ms lặp lại thường xuyên dù FPS trung bình vẫn ~106fps (số trung bình che mất giật thực tế). Đã implement (`_livePrice` field, `KChartWidget(livePrice: ...)`, `calculateAll` chỉ trong `_addNewCandle` khi nến đóng) nhưng bị revert theo yêu cầu — `_updateLastCandle` hiện vẫn giữ hành vi cũ.

## 2026-07-08

- **feat (v1.0.3):** `StochRSIIndicator` (StochRSI) — Stochastic RSI, `calcParams: [n1, n2, m1, m2]` (default `14, 14, 3, 3`). RSI Wilder tính nội bộ trong `calc()` (không dùng lại `entity.rsi`), `StochRSI = (RSI − MIN(RSI,n2)) / (MAX(RSI,n2) − MIN(RSI,n2)) × 100`, `%K = SMA(StochRSI, m1)`, `%D = SMA(%K, m2)`. Kèm 2 đường tham chiếu nét đứt 20/80 kiểu Binance.
- **feat (v1.0.3):** `AVLIndicator` (AVL) — average value line, `AVL = amount / vol` (quote volume ÷ base volume), fallback typical price `(H+L+C)/3` khi thiếu `amount`.
- **feat (v1.0.3):** `MTMIndicator` (MTM) — `calcParams: [12, 6]`. `MTM = CLOSE − REF(CLOSE, N)`, `MTMMA = MA(MTM, M)`.
- **feat (v1.0.3):** Cơ chế đường tham chiếu ngang dùng chung cho secondary indicator (`SecondaryIndicator.referenceValues`, `SecondaryRenderer.drawReferenceLines`) — dùng bởi 20/80 của StochRSI, tái dùng được cho indicator khác không cần đụng renderer.
- **feat (v1.0.2, cùng ngày):** `SuperTrendIndicator` (SUPER) — ATR-based trend line (Wilder), `calcParams: [10, 30]`, band `(H+L)/2 ± factor×ATR`, fill mờ giữa band và giá.
- **feat (v1.0.2, cùng ngày):** `TRIXIndicator` (TRIX) — triple-smoothed EMA rate-of-change, `calcParams: [12, 20]`.
- **fix (cùng ngày, sau khi ship v1.0.3):** AVL công thức tính sai bản chất — trước dùng cumulative VWAP (`Σ(typicalPrice×vol)/Σ(vol)` cộng dồn từ nến đầu tiên, giá trị trôi theo toàn bộ lịch sử); sửa thành per-candle average đúng công thức trên. Mở rộng điều kiện fallback: `amount <= 0` (không chỉ `null`) cũng coi là không đáng tin khi `vol > 0`.
  - File: `lib/entity/avl_entity.dart`, `lib/indicator/main/avl_indicator.dart`.
- **fix:** StochRSI trả sai khi thị trường đi ngang tuyệt đối — `avgGain == 0 && avgLoss == 0` trước bị tính theo nhánh `avgLoss == 0` → RSI = 100 (overbought giả). Sửa: tách riêng case này → RSI = 50 (neutral).
  - File: `lib/indicator/secondary/stoch_rsi_indicator.dart`.
- **fix:** StochRSI bỏ ép cứng range 20/80 trùng lặp trong `getMaxMinValue` — logic bao range theo `referenceValues` chuyển lên xử lý chung ở `BaseChartPainter.getSecondaryMaxMinValue` (tự động bao mọi `indicator.referenceValues` vào min/max, không cần mỗi indicator tự ép range riêng).
  - File: `lib/indicator/secondary/stoch_rsi_indicator.dart`, `lib/renderer/base_chart_painter.dart`.
- **improved:** `drawReferenceLines` gate bởi `hideGrid` (coi đường tham chiếu là 1 dạng lưới nền); gom nét đứt vào 1 `Path` vẽ 1 lần bằng `canvas.drawPath()` thay vì hàng chục `canvas.drawLine()` riêng lẻ; trở thành method ảo trên `BaseChartRenderer` (trước chỉ ở `SecondaryRenderer`) — `mSecondaryRendererList` đổi kiểu `Set<SecondaryRenderer>` → `Set<BaseChartRenderer>`.
  - File: `lib/renderer/chart_painter.dart`, `lib/renderer/secondary_renderer.dart`, `lib/renderer/base_chart_renderer.dart`.

## 2026-07-06

- **feat (v1.0.1 + v1.0.0, cùng ngày):** `KChartScaleState` — lưu/khôi phục trạng thái zoom (`scaleX`, `scaleY`, `scrollX`) qua `KChartWidget.chartScale`, `scaleX` tự clamp `minScale`/`maxScale`; callback `onChartScaleChanged` sau pinch/scaleY drag/zoom controller/double-tap reset.
- **feat (v1.0.0):** Panel volume hiển thị thêm label giá trị nhỏ nhất (min vol vùng hiển thị) ở góc dưới-phải, giống MACD. `mVolMinValue` không còn hardcode `0`.
- **fix (v1.0.1):** `onLoadMore(true)` không được gọi khi data ban đầu (hoặc sau load thêm) chưa lấp đầy chiều rộng chart (`maxScrollX <= 0`) và user chưa gesture — thêm `_maybeLoadMoreForNarrowData()` (`initState`/`didUpdateWidget` qua `addPostFrameCallback`), guard bằng `_narrowLoadRequestedForLength`.
- **fix (v1.0.0):** `onLoadMore(true)` không được gọi khi scale nhỏ tới mức data vừa đủ viewport (`maxScrollX == 0`) — bỏ guard `maxScrollX > 0`, thêm post-frame callback trong `onScaleEnd` sau pinch zoom-out.
- **docs (v1.0.1):** Sửa doc comment gây `dartdoc` warning — generic `List<SecondaryIndicator<MACDEntity, dynamic>>` bị hiểu nhầm thẻ HTML, `[0]`/`[i]`/`[i-1]`/`[scaleX]` bị hiểu nhầm doc-reference link.

## 2026-07-02

- **fix (3 lỗ hổng `shouldRepaint` phát hiện qua code review):**
  - `isLine` (toggle nến ↔ line) thiếu trong `BaseChartPainter.shouldRepaint` — chuyển loại chart không trigger repaint tới khi có field khác đổi kèm.
  - `isTrendLine`/`selectY`/`lines` thiếu trong `ChartPainter.shouldRepaint`; sâu hơn: `lines` bị `KChartWidget` **mutate in-place** (`lines.add(...)`) rồi truyền cùng reference vào `ChartPainter` mỗi build → `oldDelegate.lines != lines` không bao giờ đúng. Sửa: truyền snapshot mới `List<TrendLine>.of(lines)` mỗi build + so sánh theo giá trị (`_trendLinesEqual`).
  - Cache chuỗi ngày `getDate()` (`_dateStringCache`) gần như bị clear mỗi frame — so `mFormats` theo identity nhưng `initFormats()` luôn gán list literal MỚI mỗi lần `ChartPainter` dựng lại. Sửa: so sánh theo giá trị (`_formatsEqual`).
  - Cùng 1 lớp lỗi "mutate in-place → `!=` không bao giờ đúng → `shouldRepaint` không nhận ra thay đổi" như bug `livePrice`/`datas` (xem 06-26).
  - File: `lib/k_chart_widget.dart`, `lib/renderer/base_chart_painter.dart`, `lib/renderer/chart_painter.dart`.

## 2026-06-26

- **fix:** `BaseChartPainter.shouldRepaint` trước đó `return true` vô điều kiện — MỌI lần `CustomPainter` rebuild đều full-repaint bất kể có gì đổi. Thay bằng so sánh field thật (`datas`, `scaleX`, `scrollX`, `isLongPress`, `selectX`, `isOnTap`, `offsetY`, `volHidden`, `mainIndicators`, `secondaryIndicators`). Đưa khởi tạo `Paint` (background, trend-line) ra khỏi `paint()`/`drawBg()` vào constructor `ChartPainter` — trước đó `new Paint()` mới mỗi frame.
  - File: `lib/renderer/base_chart_painter.dart`, `lib/renderer/chart_painter.dart`, `lib/renderer/base_chart_renderer.dart`.
- **fix:** Thêm `ChartPainter.shouldRepaint` override check `oldDelegate.livePrice != livePrice` — cơ chế đứng sau pattern tách giá real-time khỏi `datas`. `DepthChartPainter.shouldRepaint` cùng lỗi `return true` vô điều kiện — đổi sang so sánh `mBuyData`/`mSellData`/`isLongPress`/`pressOffset`. Thêm `scaleY` vào so sánh của `BaseChartPainter.shouldRepaint` (trước thiếu, đổi scaleY qua pinch không đảm bảo repaint).
  - File: `lib/depth_chart.dart`, `lib/renderer/base_chart_painter.dart`, `lib/renderer/chart_painter.dart`.

## 2026-06-12

- **fix:** Cùng nhóm bug `onLoadMore` (xem v1.0.0) — bỏ điều kiện `maxScrollX > 0` khỏi trigger `onLoadMore` khi scroll/pinch, thêm `addPostFrameCallback` check sau khi kết thúc pinch-zoom-out (vì `maxScrollX` chỉ cập nhật sau khi `paint()` chạy xong).
  - File: `lib/k_chart_widget.dart`.
- **fix:** Cùng nội dung với v1.0.0 mục "min-volume label" — `mVolMinValue` hết hardcode `0`, tính `min(mVolMinValue, item.vol)` theo data thực tế; `VolRenderer` vẽ thêm label min ở góc dưới-phải panel volume.
  - File: `lib/renderer/base_chart_painter.dart`, `lib/renderer/vol_renderer.dart`.

## 2026-06-08

- **fix:** `StreamController<InfoWindowEntity?>()` → `.broadcast()` — stream info-window vốn single-subscription, `StreamBuilder` trong info dialog rebuild lại ném lỗi "Stream has already been listened to."
- **fix:** Vùng gesture scaleY / double-tap-reset ở cạnh phải chart hết hardcode cố định `100px`, tính qua `BaseChartPainter.effectiveRightPaddingPx(xFrontPadding, width)` — co giãn theo tỉ lệ, tránh chiếm quá nhiều trên màn hình hẹp.
  - File: `lib/k_chart_widget.dart`.

## 2026-06-06

- **fix:** Thêm `KChartWidget.didUpdateWidget` → `_compensateScrollOnDataChange` — khi parent append nến mới (live tick) hoặc prepend nến cũ (lazy-load), `mScrollX` bị "trôi" vì `getMinTranslateX` tính lại theo độ dài data mới. Bù `mScrollX` thêm `diff × pointWidth` khi append để view không giật — TRỪ khi user đang ở rightmost (`mScrollX <= 0`, cố ý giữ nguyên để chart tự follow nến mới nhất kiểu TradingView/Binance).
- **fix:** `KChartWidget.minScale` mặc định nới `0.5` → `0.2`, cho phép pinch-zoom-out xa hơn.
  - File: `lib/k_chart_widget.dart`.

## 2026-05-27

- **fix:** `MACDEntity` mixin mở rộng `on` clause bắt buộc thêm `OBVEntity` để entity dựng trên `MACDEntity` truy cập trực tiếp `.obv`/`.obvSignal`. (Cùng commit gốc thêm `_liveChip()` — tick real-time mô phỏng qua `Timer.periodic` trong `example/lib/main.dart`.)
- **fix:** Sửa bug thứ tự mixin phát sinh từ commit trên — `KEntity` khai `MACDEntity` trước `OBVEntity` nhưng `MACDEntity on ... OBVEntity` đòi `OBVEntity` đứng trước theo linearization của Dart. Đổi lại `..., OBVEntity, MACDEntity, ZigZagEntity`. `OBVIndicator` đổi generic type sang `SecondaryIndicator<MACDEntity, OBVStyle>`.
  - File: `lib/entity/k_entity.dart`, `lib/entity/macd_entity.dart`, `lib/indicator/secondary/obv_indicator.dart`, `example/lib/main.dart`.

## 2026-05-23

- **fix:** Nối tiếp fix scaleY 05-19 — label trục giá (`MainRenderer.drawVerticalText`) vẫn tính theo range giá trị TRƯỚC transform, nên sau pinch đổi scaleY label không còn khớp vị trí nến render. Sửa: truyền `externalScaleY`/`scaleCenterY` vào `MainRenderer`, đảo ngược transform khi map vị trí Y mỗi grid row về giá trị giá.
  - File: `lib/renderer/chart_painter.dart`, `lib/renderer/main_renderer.dart`.

## 2026-05-19

- **feat:** Đổi thứ tự layout panel: main chart → volume → thanh thời gian → secondary indicators (trước đó thanh thời gian nằm GIỮA main chart và volume). Sửa vùng gesture scaleY dừng đúng ở đáy `main + volume + secondary` thay vì kéo dài tới đáy widget.
  - File: `example/lib/main.dart`, `lib/k_chart_widget.dart`, `lib/renderer/base_chart_painter.dart`.
- **fix:** `onLoadMore(true)` trước chỉ được gọi khi fling cuộn tới đúng `mScrollX <= 0`. Thêm check trực tiếp trong `onScaleUpdate`/`onScaleEnd`: bắn `onLoadMore(true)` ngay khi `mScrollX >= maxScrollX * 0.8` — load chủ động trước khi chạm đáy. Thêm param `isLoadingMore` để chặn gọi trùng khi đang fetch dở.
  - File: `lib/k_chart_widget.dart`.
- **fix:** Dọn lint `flutter analyze` trên ~20 file — thêm `{}` cho `if` 1 dòng, bỏ `this.` thừa, `KLineEntity` đổi field `late` gán sau sang constructor param bắt buộc, enum `TimeFormat.YEAR_MONTH_DAY_WITH_HOUR` → `yearMonthDayWithHour`, thêm `const`/`super.key` cho `DepthChart`, `createState()` trả `State<DepthChart>` public thay vì kiểu private. Không đổi hành vi.
- **fix:** Đổi kiến trúc scaleY — trước co giãn range min/max giá trị đưa vào `MainRenderer` (làm sai cách tính label trục giá, gắn chặt zoom-Y vào logic range indicator). Sau: scaleY áp qua **canvas transform** (`canvas.translate` + `canvas.scale(1.0, scaleY)` quanh tâm `mMainRect`, có `clipRect` chống tràn ra time bar/secondary panel). Secondary indicator vẽ ở vòng lặp riêng, NGOÀI transform này — pinch-zoom-Y chỉ ảnh hưởng nến/volume chính. Volume panel gộp làm overlay đè lên 20% dưới main chart thay vì panel riêng bên dưới. Thêm helper `_applyScaleY()` cho label vẽ ngoài canvas transform (max/min giá, livePrice).
  - File: `lib/k_chart_widget.dart`, `lib/renderer/base_chart_painter.dart`, `lib/renderer/chart_painter.dart`, `lib/renderer/main_renderer.dart`, `lib/renderer/vol_renderer.dart`.

## 0.0.1 — 2026-05-18

* Initial release of k_chart_jk — a Flutter candlestick chart package.
* Candlestick and line chart rendering with smooth gesture support (pan, zoom, fling).
* Main indicators: MA, EMA, BOLL, SAR, ZigZag.
* Secondary indicators: MACD, KDJ, RSI, WR, CCI.
* Volume bar chart with MA5/MA10 overlay.
* Long-press info dialog with customizable `detailBuilder`.
* Dark/light theme support via `KChartColors`.
* `KChartController` for programmatic zoom in/out and reset.
* Depth chart widget (`DepthChart`) for order book visualization.
* Multi-language support via `ChartTranslations`.
