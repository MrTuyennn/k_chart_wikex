# Indicators — Công dụng & Công thức

Tổng hợp toàn bộ indicator hiện có trong `k_chart_jk`: 8 main (vẽ đè lên biểu đồ giá) + 13 secondary (panel riêng bên dưới). Công thức lấy trực tiếp từ `calc()` trong source, không phải lý thuyết sách vở — khớp đúng những gì code đang chạy.

---

## 1. Main indicators — vẽ đè lên biểu đồ giá

### MA — Moving Average (`ma_indicator.dart`)
- **Công dụng**: đường trung bình động đơn giản, xác định xu hướng và mức hỗ trợ/kháng cự động. Giá cắt lên/xuống MA, hoặc các đường MA cắt nhau (golden cross/death cross) là tín hiệu kinh điển.
- **calcParams**: `[5, 10, 30, 60]` — nhiều đường cùng lúc, mỗi phần tử là 1 chu kỳ.
- **Công thức**: `MA(n) = SUM(close, n) / n` — trung bình cộng n phiên gần nhất (rolling sum).

### EMA — Exponential Moving Average (`ema_indicator.dart`)
- **Công dụng**: giống MA nhưng phản ứng nhanh hơn với giá gần nhất (trọng số giảm dần theo thời gian) — dùng khi cần tín hiệu sớm hơn MA thường, đổi lại dễ nhiễu (whipsaw) hơn.
- **calcParams**: `[5, 10, 30, 60]`.
- **Công thức**: `multiplier = 2/(n+1)`; `EMA[i] = (close[i] - EMA[i-1]) × multiplier + EMA[i-1]` (seed `EMA[0] = close[0]`).

### BOLL — Bollinger Bands (`boll_indicator.dart`)
- **Công dụng**: đo độ biến động (volatility). Dải hẹp → thị trường tích luỹ, sắp có biến động mạnh. Giá chạm dải trên/dưới → có thể quá mua/quá bán hoặc breakout theo dải. Dải mid đóng vai trò MA trung tâm.
- **calcParams**: `[20, 2]` — (chu kỳ MA, số độ lệch chuẩn).
- **Công thức**: `mid = MA(close, 20)`; `md = stdev(close, 20)`; `up = mid + 2×md`; `dn = mid - 2×md`.

### SAR — Parabolic Stop And Reverse (`sar_indicator.dart`)
- **Công dụng**: chấm bám theo giá, dùng đặt stop-loss động (trailing stop) và xác định điểm đảo chiều xu hướng — chấm nằm dưới giá = uptrend, chấm nhảy lên trên giá = tín hiệu đảo sang downtrend.
- **calcParams**: `[2, 2, 20]` — (AF khởi tạo ×100, AF bước tăng ×100, AF tối đa ×100 → 0.02/0.02/0.20).
- **Công thức**: `SAR[i] = SAR[i-1] + AF×(EP - SAR[i-1])` (EP = extreme point của trend hiện tại); AF tăng dần mỗi khi có EP mới, reset khi đảo chiều (giá chạm SAR).
- **Style**: chấm/label tô theo xu hướng — `sar <= (high+low)/2` (SAR dưới giá) = tăng → `upColor`; ngược lại → `dnColor`.

### SuperTrend (`super_trend_indicator.dart`)
- **Công dụng**: đường xu hướng theo ATR (đo biến động thực), dễ đọc hơn SAR (1 đường liền + vùng tô mờ) — dùng xác định xu hướng chính và điểm vào/thoát lệnh theo trend-following.
- **calcParams**: `[10, 30]` — (chu kỳ ATR, hệ số nhân ×10 → factor 3.0).
- **Công thức**:
  ```
  ATR = RMA(TR, N)   // TR = max(h-l, |h-prevClose|, |l-prevClose|), seed = SMA(TR,N) rồi Wilder-smooth
  upperBand = (h+l)/2 + factor×ATR
  lowerBand = (h+l)/2 - factor×ATR
  trend flip khi close cắt qua band hiện tại
  ```

### ZigZag (`zigzag_indicator.dart`)
- **Công dụng**: lọc nhiễu, chỉ nối các đỉnh/đáy quan trọng thành đường zig-zag — giúp nhìn rõ cấu trúc sóng (swing high/low) để vẽ Fibonacci, đếm sóng Elliott, hoặc xác định higher-high/lower-low.
- **calcParams**: `[12, 2, 5]` — (depth: số nến xét local high/low, backstep: số nến xác nhận không bị phá, deviation: chưa dùng trong bản hiện tại).
- **Công thức**: tìm local high/low trong cửa sổ `depth` nến hai bên (không bị chọc thủng trong `backstep` nến kế tiếp), nối các pivot cao/thấp xen kẽ, nội suy tuyến tính giữa 2 pivot liên tiếp.

### AVL — Average Value Line, kiểu Binance (`avl_indicator.dart`)
- **Công dụng**: đường giá khớp lệnh trung bình THỰC của từng nến (không phải MA cộng dồn) — luôn nằm trong thân nến, bám sát giá thật hơn MA/EMA, giống đường "AVL" trên app Binance.
- **calcParams**: `[]` — không có chu kỳ.
- **Công thức**: `AVL = AMOUNT / VOL` (quote volume ÷ base volume của chính nến đó); fallback `(high+low+close)/3` khi thiếu `amount` hoặc `vol = 0`.

### Ichimoku — Ichimoku Kinko Hyo, 一目均衡表 (`ichimoku_indicator.dart`)
- **Công dụng**: hệ thống 5 đường + mây (Kumo) cho xu hướng, hỗ trợ/kháng cự động, và tín hiệu đảo chiều cùng lúc trong 1 indicator — không cần kết hợp nhiều đường riêng lẻ như MA+BOLL.
- **calcParams**: `[9, 26, 52]` (tenkanPeriod, kijunPeriod, spanBPeriod) — bộ cổ điển (chứng khoán/forex, gốc Nhật). Bộ thường dùng cho crypto (24/7, không phiên nghỉ): `[20, 60, 120]`. `shift` LUÔN = `calcParams[1]` (kijun period), KHÔNG hardcode `26` — đổi param thì shift đổi theo.
- **Công thức** (`HH(n)`/`LL(n)` = cao/thấp nhất trong n nến gần nhất, tính cả nến hiện tại):
  ```
  Tenkan-sen  (Conversion) = (HH(9) + LL(9)) / 2      tại nến hiện tại
  Kijun-sen   (Base)       = (HH(26) + LL(26)) / 2     tại nến hiện tại
  Senkou Span A (Leading A)= (Tenkan + Kijun) / 2       dịch TỚI TRƯỚC shift nến
  Senkou Span B (Leading B)= (HH(52) + LL(52)) / 2      dịch TỚI TRƯỚC shift nến
  Chikou Span (Lagging)    = close                       dịch LÙI shift nến
  ```
  **Kumo (mây)** = vùng tô giữa Span A/B — `Span A > Span B` → mây tăng (xanh), ngược lại → mây giảm (đỏ); polygon tách tại điểm 2 đường giao nhau (nội suy tuyến tính) để đổi màu đúng đoạn.
- **Warm-up**: Tenkan cần 9 nến, Kijun/Span A cần 26, Span B cần 52 — chart `itemCount < 52` thì mây chưa vẽ đủ; field giữ `null` đúng vị trí warm-up (không sentinel `0`, tránh đường/mây rác kéo về 0).
- **Hiệu năng**: `calc()` dùng sliding-window monotonic deque O(n) cho cả 3 chu kỳ HH/LL — không phải vòng lặp naive O(n×period), tránh giật khi pan/zoom trên chart nhiều nến.
- **Render đặc biệt — "vùng tương lai"**: main indicator DUY NHẤT cần vẽ ra ngoài phạm vi `0..itemCount-1` của mảng nến (Span A/B dịch tới trước, Chikou dịch lùi). Cơ chế mở rộng trục X dùng chung cho việc này (`MainIndicator.futureShift`, `mFutureSlots`, 3 phạm vi index tách biệt viewport/hiển-thị-thật/real-mở-rộng) — xem đầy đủ, trung lập nền tảng ở `architecture.md` §3.5. Bản thật (`ichimoku_indicator.dart`) KHÔNG lưu mảng đã dịch sẵn kiểu `spanA[n+shift]` — Span A/B/Chikou vẫn lưu 1 giá trị/nến tại index gốc như mọi indicator khác, phần dịch `±shift` chỉ là cộng/trừ `shift × pointWidth` vào toạ độ X ngay tại draw-time (`IchimokuIndicator.drawChart`). Crosshair/tap-selection bị clamp về nến thật đang hiển thị, KHÔNG cho chọn vào vùng tương lai trống (đơn giản hoá có chủ đích).

---

## 2. Secondary indicators — panel riêng bên dưới

### MACD — Moving Average Convergence Divergence (`macd_indicator.dart`)
- **Công dụng**: đo động lượng xu hướng qua khoảng cách 2 EMA. Histogram đổi màu (macd cắt 0) hoặc DIF cắt DEA là tín hiệu mua/bán kinh điển; phân kỳ (giá tạo đỉnh mới nhưng MACD không) báo hiệu suy yếu xu hướng.
- **calcParams**: `[12, 26, 9]` — (EMA nhanh, EMA chậm, chu kỳ tín hiệu).
- **Công thức**: `DIF = EMA(close,12) - EMA(close,26)`; `DEA = EMA(DIF, 9)`; `MACD = (DIF - DEA) × 2` (histogram).

### KDJ — Stochastic Oscillator biến thể Trung Quốc (`kdj_indicator.dart`)
- **Công dụng**: dao động 0-100 (thực tế K/D/J có thể vượt biên), xác định vùng quá mua (>80)/quá bán (<20) và tín hiệu qua K cắt D. Đường J nhạy nhất, dùng để bắt đỉnh/đáy sớm.
- **calcParams**: cố định trong `calc()` — 9 nến RSV, smoothing 1/3-2/3.
- **Công thức**: `RSV = (close - low9)/(high9 - low9) × 100`; `K = (2×K_prev + RSV)/3`; `D = (2×D_prev + K)/3`; `J = 3K - 2D`. Seed `K=D=J=50`.

### RSI — Relative Strength Index (`rsi_indicator.dart`)
- **Công dụng**: đo sức mạnh tăng/giảm giá, dao động 0-100. >70 quá mua, <30 quá bán (quy ước phổ biến, không hard-code trong code này). Phân kỳ RSI vs giá là tín hiệu đảo chiều mạnh.
- **calcParams**: `[6, 12, 24]` khai báo nhưng `calc()` hiện hard-code chu kỳ 14 (Wilder smoothing EMA-14 cho phần tăng/giảm).
- **Công thức**: `RSI = 100 × avgGain / (avgGain + avgLoss)`, với `avgGain`/`avgLoss` là EMA-14 (Wilder) của phần tăng/giảm mỗi phiên.

### WR — Williams %R (`wr_indicator.dart`)
- **Công dụng**: đo vị trí giá đóng cửa trong biên độ 14 phiên gần nhất, dao động -100 đến 0. Gần 0 = quá mua (giá sát đỉnh biên độ), gần -100 = quá bán (giá sát đáy biên độ) — phản ứng nhanh hơn RSI, hay dùng lọc tín hiệu đảo chiều ngắn hạn.
- **calcParams**: `[26, 6]` khai báo nhưng `calc()` hard-code cửa sổ 14.
- **Công thức**: `WR = -100 × (high14 - close) / (high14 - low14)`.

### CCI — Commodity Channel Index (`cci_indicator.dart`)
- **Công dụng**: đo độ lệch giá hiện tại so với giá trung bình, không giới hạn biên (khác RSI/WR) — thường dùng ±100 làm ngưỡng quá mua/quá bán, vượt ±200 là biến động cực đoan. Tốt cho phát hiện breakout sớm.
- **calcParams**: `[20]`.
- **Công thức**: `TP = (high+low+close)/3`; `CCI = (TP - MA(TP,20)) / (0.015 × meanDeviation(TP,20))`.

### OBV — On-Balance Volume (`obv_indicator.dart`)
- **Công dụng**: đo dòng tiền tích luỹ qua volume theo hướng giá — xác nhận xu hướng (OBV và giá cùng tăng/giảm) hoặc cảnh báo phân kỳ (giá đi ngang/giảm nhưng OBV tăng = tiền đang âm thầm vào, sắp đảo chiều tăng, và ngược lại).
- **calcParams**: `[5]` — chu kỳ MA của đường signal.
- **Công thức**: `OBV[i] = OBV[i-1] + vol[i]` nếu `close[i] > close[i-1]`, trừ `vol[i]` nếu giảm, giữ nguyên nếu bằng; `signal = SMA(OBV, 5)`.

### TRIX — Triple Exponential Average (`trix_indicator.dart`)
- **Công dụng**: tốc độ biến đổi (rate of change) của EMA làm mượt 3 lần liên tiếp — lọc nhiễu ngắn hạn rất mạnh, chỉ giữ lại xu hướng dài hạn. Tín hiệu qua TRIX cắt đường MATRIX (signal), phù hợp thị trường dao động chậm.
- **calcParams**: `[12, 20]` — (chu kỳ EMA×3, chu kỳ MA tín hiệu).
- **Công thức**: `EMA1=EMA(close,12)`; `EMA2=EMA(EMA1,12)`; `EMA3=EMA(EMA2,12)`; `TRIX=(EMA3-prevEMA3)/prevEMA3×100`; `MATRIX=MA(TRIX,20)`.

### MTM — Momentum (`mtm_indicator.dart`)
- **Công dụng**: đo tốc độ thay đổi giá thô (không chuẩn hoá %) so với N phiên trước — đơn giản, trực quan, dùng xác nhận động lượng xu hướng đang mạnh lên hay yếu đi.
- **calcParams**: `[12, 6]` — (chu kỳ momentum, chu kỳ MA tín hiệu).
- **Công thức**: `MTM = close - close[n bars ago]`; `MTMMA = MA(MTM, m)`.

### StochRSI — Stochastic RSI (`stoch_rsi_indicator.dart`)
- **Công dụng**: áp công thức Stochastic lên chính chuỗi RSI (thay vì lên giá) — nhạy hơn RSI thường rất nhiều, tín hiệu quá mua/quá bán (20/80, có vẽ 2 đường tham chiếu nét đứt) xuất hiện sớm và thường xuyên hơn, phù hợp giao dịch ngắn hạn/lướt sóng.
- **calcParams**: `[14, 14, 3, 3]` — (chu kỳ RSI nội bộ, chu kỳ Stoch, smoothing %K, smoothing %D).
- **Công thức**: `RSI` tính nội bộ (Wilder, không phụ thuộc `RSIIndicator` có bật hay không); `StochRSI = (RSI - min14(RSI)) / (max14(RSI) - min14(RSI)) × 100`; `%K = SMA(StochRSI,3)`; `%D = SMA(%K,3)`.

### BRAR — Popularity/Willingness Index (`brar_indicator.dart`)
- **Công dụng**: đo tâm lý/động lực thị trường qua biên độ nến (khác RSI chỉ nhìn giá đóng cửa) — AR đo "năng lượng" quanh giá mở cửa, BR đo ý chí mua/bán so với giá đóng cửa phiên trước. Cả 2 cùng cao (>150-200) → quá hưng phấn, dễ điều chỉnh; cả 2 cùng thấp (<50) → quá bi quan, dễ hồi phục. BR cắt AR hoặc 2 đường phân kỳ mạnh báo hiệu đổi momentum. **Không phải chỉ báo xu hướng** — chỉ dùng lọc tín hiệu kèm indicator xu hướng khác.
- **calcParams**: `[26]`.
- **Công thức**:
  ```
  AR = Σ(high - open, 26) / Σ(open - low, 26) × 100
  BR = Σmax(0, high - prevClose, 26) / Σmax(0, prevClose - low, 26) × 100
  ```
  (guard chia 0 → 0, tránh NaN/Infinity).

### BIAS — Bias Ratio / 乖离率 (`bias_indicator.dart`)
- **Công dụng**: đo % lệch giá hiện tại so với đường MA cùng chu kỳ — lệch dương lớn = giá đang chạy quá xa MA lên trên (dễ điều chỉnh giảm về MA), lệch âm lớn = giá chạy quá xa xuống dưới (dễ hồi phục lên MA). Vẽ nhiều chu kỳ cùng lúc (mặc định 6/12/24) để so sánh độ lệch ngắn/trung/dài hạn — 3 đường hội tụ về gần 0 thường báo hiệu sắp có biến động mạnh.
- **calcParams**: `[6, 12, 24]` — nhiều chu kỳ cùng lúc, giống MA (mỗi phần tử là 1 đường riêng, không giới hạn đúng 3).
- **Công thức**: `BIAS(n) = (close - MA(close, n)) / MA(close, n) × 100%`.

### PSY — Psychological Line / 心理线 (`psy_indicator.dart`)
- **Công dụng**: đo % số phiên TĂNG trong N phiên gần nhất — phản ánh tâm lý đám đông đang lạc quan hay bi quan. PSY quá cao (>75-83) → thị trường quá lạc quan, dễ điều chỉnh giảm; quá thấp (<25-17) → quá bi quan, dễ hồi phục. MAPSY (signal MA) cắt PSY dùng lọc tín hiệu, giảm nhiễu so với dùng PSY một mình.
- **calcParams**: `[12, 6]` — (N: chu kỳ đếm phiên tăng, M: chu kỳ MA tín hiệu).
- **Công thức**: `PSY = COUNT(close > REF(close,1), N) / N × 100`; `MAPSY = MA(PSY, M)`.

### ATR — Average True Range (`atr_indicator.dart`)
- **Công dụng**: đo độ biến động (volatility) thị trường, không đo hướng xu hướng. ATR cao → thị trường biến động mạnh (nến dao động rộng); ATR thấp → thị trường yên tĩnh. Thường dùng để đặt stop-loss theo % biến động thực tế (vd `stop = giá - 2×ATR`) hoặc điều chỉnh kích thước vị thế, thay vì để so sánh xu hướng tăng/giảm.
- **calcParams**: `[14, 6]` — (N: chu kỳ làm mượt Wilder của ATR, M: chu kỳ MA tín hiệu MAATR).
- **Công thức**:
  ```
  TR    = max(high-low, |high-prevClose|, |low-prevClose|)
  ATR[N-1] = SMA(TR, N)                         (seed)
  ATR[i]   = (TR[i] + (N-1) × ATR[i-1]) / N     (i >= N, Wilder smoothing)
  MAATR    = MA(ATR, M)
  ```

---

## Ghi chú chung
- Tất cả indicator secondary dùng chung `MACDEntity` làm generic type `T` (trừ output field riêng của từng indicator được thêm vào mixin chain `KEntity`/`MACDEntity`'s `on` clause) — xem `lib/entity/k_entity.dart`/`lib/entity/macd_entity.dart` để biết thứ tự mixin bắt buộc khi thêm indicator mới.
- Màu sắc mỗi indicator cấu hình qua `KChartColors.xxxStyle` (vd `colors.rsiStyle`, `colors.brarStyle`) — style riêng của instance (`RSIIndicator(indicatorStyle: ...)`) sẽ KHÔNG bị `KChartColors` ghi đè, xem `IndicatorTemplate.isDefaultStyle`.
- Chi tiết wiring/kiến trúc đầy đủ hơn xem `chart_jk_arch.md` §9.2.
