/// Time-tick planner cho trục X — theo CHART_AXES.md §5.
///
/// Thay cho cách hiện có (chia MÀN HÌNH thành N cột đều nhau rồi lấy nến gần
/// nhất mỗi cột), module này chọn tick theo Ý NGHĨA LỊCH (đầu giờ/ngày/tháng/
/// năm — "weight ladder"), số lượng tick tự co giãn theo `barSpacing` (zoom)
/// và không bao giờ chồng nhãn (MIN_GAP_X), ổn định khi pan (I4: chọn tick
/// trên "absolute space" — loại `scrollOffset`, không phụ thuộc vị trí cuộn).
library;

import 'dart:math' as math;
import '../entity/k_line_entity.dart';
import 'date_format_util.dart';

/// Khoảng cách tối thiểu (px) giữa 2 label thời gian liền kề.
const double kMinGapX = 64.0;

/// Hệ số "dư" ứng viên khi lọc threshold — giữ nhiều ứng viên hơn mức sẽ sống
/// sót qua bước đóng gói (§5.1), để rung không nhảy nguyên bậc mỗi khi hết chỗ.
const double kTickSurplus = 4.0;

// ── Tick weight ladder (§3) — số nguyên cụ thể, có khoảng trống để chèn thêm
// bậc sau này mà không phải đánh số lại. ──
const int kMinor = 0;
const int kMin1 = 10;
const int kMin5 = 11;
const int kMin15 = 12;
const int kMin30 = 13;
const int kHour1 = 20;
const int kHour3 = 21;
const int kHour6 = 22;
const int kHour12 = 23;
const int kDay = 30;
const int kMonth = 40;
const int kYear = 50;

class _Rung {
  final int weight;
  final int nominalPeriodMs;
  const _Rung(this.weight, this.nominalPeriodMs);
}

/// Ladder tăng dần theo nominal period — dùng bởi [thresholdRung]. Period của
/// month/year là số trung bình, chỉ dùng để CHỌN bậc, không dùng để đặt vị trí
/// tick (vị trí tick luôn là chỉ số nến thật).
const List<_Rung> _kLadder = [
  _Rung(kMinor, 0),
  _Rung(kMin1, 60000),
  _Rung(kMin5, 300000),
  _Rung(kMin15, 900000),
  _Rung(kMin30, 1800000),
  _Rung(kHour1, 3600000),
  _Rung(kHour3, 10800000),
  _Rung(kHour6, 21600000),
  _Rung(kHour12, 43200000),
  _Rung(kDay, 86400000),
  _Rung(kMonth, 2629746000),
  _Rung(kYear, 31556952000),
];

/// Trọng số của [t] dựa trên việc nó có nằm đúng ranh giới lịch hay không
/// (t LÀ local time). Giữ label khả dụng ở mọi mức zoom, kể cả khi không có
/// ranh giới giờ/ngày nào lọt vào khung nhìn.
int alignmentWeight(DateTime t) {
  if (t.minute != 0) {
    if (t.minute % 30 == 0) return kMin30;
    if (t.minute % 15 == 0) return kMin15;
    if (t.minute % 5 == 0) return kMin5;
    return kMin1;
  }
  if (t.hour != 0) {
    if (t.hour % 12 == 0) return kHour12;
    if (t.hour % 6 == 0) return kHour6;
    if (t.hour % 3 == 0) return kHour3;
    return kHour1;
  }
  if (t.day != 1) return kDay;
  if (t.month != 1) return kMonth;
  return kYear;
}

/// Trọng số bổ sung khi [cur] vừa "vượt" qua ranh giới lịch so với [prev] —
/// bắt các case nến không thẳng hàng với ranh giới local (vd nến 4h ở GMT+7
/// rơi vào 03:00/07:00/11:00, không nến nào có `hour == 0`).
int crossingWeight(DateTime prev, DateTime cur) {
  if (cur.year != prev.year) return kYear;
  if (cur.month != prev.month) return kMonth;
  if (cur.day != prev.day) return kDay;
  if (cur.hour != prev.hour) return kHour1;
  return kMinor;
}

/// Gán [KLineEntity.tickWeight] cho các nến CHƯA có (null) — an toàn để gọi
/// lại nhiều lần: nến đã có weight sẽ được bỏ qua, phù hợp cả 2 case (a) data
/// mới load hoàn toàn (mọi weight null), (b) 1 nến vừa được append realtime
/// (chỉ nến mới có weight null) — không cần hook riêng cho append (§9).
void _assignTickWeights(List<KLineEntity> candles) {
  if (candles.isEmpty) return;
  DateTime? prevLocal;
  for (int i = 0; i < candles.length; i++) {
    final candle = candles[i];
    final cur = DateTime.fromMillisecondsSinceEpoch(candle.time ?? 0);
    candle.tickWeight ??= prevLocal == null
        ? alignmentWeight(cur)
        : math.max(alignmentWeight(cur), crossingWeight(prevLocal, cur));
    prevLocal = cur;
  }
}

/// Khoảng thời gian (ms) giữa 2 nến liên tiếp — lấy MIN (không phải mean) của
/// tối đa 64 khoảng đầu tiên để downtime sàn giao dịch không làm lệch kết quả.
int detectIntervalMs(List<KLineEntity> candles) {
  int? minDiff;
  final int limit = math.min(candles.length - 1, 63);
  for (int i = 0; i < limit; i++) {
    final int? a = candles[i].time;
    final int? b = candles[i + 1].time;
    if (a == null || b == null) continue;
    final int diff = b - a;
    if (diff > 0 && (minDiff == null || diff < minDiff)) minDiff = diff;
  }
  return minDiff ?? 60000;
}

/// Bậc weight tối thiểu để 1 nến được coi là ứng viên tick, suy ra từ hình học
/// thuần (barSpacing, interval) — KHÔNG đếm số nến đang hiển thị (đếm sẽ dao
/// động ±1 khi cuộn, gây nhấp nháy label — FAILURE MODE 3).
int thresholdRung(double barSpacing, int intervalMs) {
  if (barSpacing <= 0) return kYear;
  final double required = kMinGapX * intervalMs / (barSpacing * kTickSurplus);
  for (final rung in _kLadder) {
    final int period = math.max(rung.nominalPeriodMs, intervalMs);
    if (period >= required) return rung.weight;
  }
  return _kLadder.last.weight;
}

/// 1 tick đã chọn trên trục thời gian — toạ độ pixel do painter tính (dùng lại
/// đúng 1 hệ quy chiếu `translateXtoX(getX(index))` đang có, không tự bịa toạ
/// độ riêng — I2/I6).
class TimeTick {
  final int index;
  final int weight;
  final String label;

  const TimeTick({required this.index, required this.weight, required this.label});
}

/// Nhãn cho 1 nến CỤ THỂ dựa trên `tickWeight` đã cache của nó — dùng cho
/// fallback "never blank" khi không ứng viên nào trong kế hoạch rơi vào vùng
/// đang hiển thị (viewport quá hẹp so với khoảng cách giữa 2 tick đã chọn).
/// Giả định `tickWeight` đã được gán trước đó (vd sau khi [buildTimeTickPlan]
/// chạy qua cùng danh sách nến chứa [candle]) — nếu chưa, coi như MINOR.
String labelForCandle(KLineEntity candle, {List<String>? forcedFormat}) {
  final local = DateTime.fromMillisecondsSinceEpoch(candle.time ?? 0);
  return _labelFor(local, candle.tickWeight ?? kMinor, forcedFormat);
}

String _labelFor(DateTime local, int weight, List<String>? forcedFormat) {
  if (forcedFormat != null) return dateFormat(local, forcedFormat);
  if (weight >= kYear) return dateFormat(local, const [yyyy]);
  if (weight >= kMonth) return dateFormat(local, const [M]);
  if (weight >= kDay) return dateFormat(local, const [d]);
  return dateFormat(local, const [hour24Padded, ':', nn]);
}

class _Candidate {
  final int index;
  final double absX;
  final int weight;

  const _Candidate(this.index, this.absX, this.weight);
}

/// Xây kế hoạch tick — chạy trên "absolute space" (`absX = i*barSpacing +
/// barSpacing/2`, KHÔNG trừ scrollOffset) nên việc cuộn không làm thay đổi
/// ứng viên nào thắng (I4); chỉ cần rebuild khi `barSpacing`/số nến/interval
/// đổi — xem [TimeTickPlanner] cho phần cache.
///
/// Không bao giờ trả về rỗng khi `candles` không rỗng — Fallback A (bước đều
/// theo MIN_GAP_X) đảm bảo điều này (§5.2, T1).
List<TimeTick> buildTimeTickPlan({
  required List<KLineEntity> candles,
  required double barSpacing,
  required int intervalMs,
  List<String>? forcedFormat,
}) {
  if (candles.isEmpty || barSpacing <= 0) return const [];
  _assignTickWeights(candles);

  final int threshold = thresholdRung(barSpacing, intervalMs);
  double absX(int i) => i * barSpacing + barSpacing / 2;

  List<_Candidate> candidates = [];
  for (int i = 0; i < candles.length; i++) {
    final int w = candles[i].tickWeight ?? kMinor;
    if (w >= threshold) candidates.add(_Candidate(i, absX(i), w));
  }

  if (candidates.isEmpty) {
    // Fallback A: threshold không có ứng viên nào (vd khoảng interval quá lớn
    // so với zoom hiện tại) — bước đều theo MIN_GAP_X để trục không bao giờ trống.
    final int step = math.max(1, (kMinGapX / barSpacing).ceil());
    for (int i = 0; i < candles.length; i += step) {
      candidates.add(_Candidate(i, absX(i), candles[i].tickWeight ?? kMinor));
    }
  }

  candidates.sort((a, b) {
    final int byWeight = b.weight.compareTo(a.weight); // DESC
    return byWeight != 0 ? byWeight : a.index.compareTo(b.index); // ASC
  });

  final Map<int, List<double>> buckets = {};
  final List<_Candidate> accepted = [];
  for (final c in candidates) {
    final int b = (c.absX / kMinGapX).floor();
    bool clash = false;
    for (final nb in [b - 1, b, b + 1]) {
      final list = buckets[nb];
      if (list == null) continue;
      for (final ax in list) {
        if ((c.absX - ax).abs() < kMinGapX) {
          clash = true;
          break;
        }
      }
      if (clash) break;
    }
    if (clash) continue;
    buckets.putIfAbsent(b, () => []).add(c.absX);
    accepted.add(c);
  }

  accepted.sort((a, b) => a.absX.compareTo(b.absX));

  return accepted
      .map(
        (c) => TimeTick(
          index: c.index,
          weight: c.weight,
          label: _labelFor(
            DateTime.fromMillisecondsSinceEpoch(candles[c.index].time ?? 0),
            c.weight,
            forcedFormat,
          ),
        ),
      )
      .toList();
}

/// Cache kế hoạch tick giữa các frame — CHỈ build lại khi
/// `(candles, barSpacing, interval, forcedFormat)` đổi thật sự, tái dùng
/// nguyên vẹn khi pan (§5.2: "rebuild on zoom or data change; reuse unchanged
/// across every pan frame").
///
/// **Instance, KHÔNG `static`** — sở hữu bởi `_KChartWidgetState` (field bền
/// qua các lần `build()`, giống `mScaleX`/`mScrollX`), truyền xuống painter
/// qua constructor. Trước đây dùng `static` để "sống sót" qua việc
/// `ChartPainter` bị tạo mới mỗi build, nhưng static nghĩa là TOÀN PROCESS
/// dùng chung 1 cache — 2 `KChartWidget` vẽ đồng thời (watchlist mini-chart,
/// so sánh nhiều symbol) sẽ tranh chấp/rò rỉ tick-plan vào nhau. Instance vẫn
/// giữ được lợi ích "không rebuild mỗi frame pan" (mỗi widget tự có
/// `TimeTickPlanner` riêng, sống cùng vòng đời `State`), chỉ khác chỗ sở hữu.
///
/// **Cache key gồm cả identity của [candles]** (`identityHashCode`, không chỉ
/// `length`) — nếu không, đổi symbol/timeframe sang dataset trùng
/// `(length, interval)` với lần trước sẽ tái dùng NHẦM plan cũ (nhãn ngày sai
/// dữ liệu) cho tới khi zoom (đổi `barSpacing`) mới tự sửa.
///
/// **`barSpacing` làm tròn về px nguyên trong key** (giá trị CHÍNH XÁC vẫn
/// dùng để build plan khi thật sự rebuild) — trong lúc pinch-zoom,
/// `onScaleUpdate` bắn liên tục với `barSpacing` khác nhau từng phần lẻ mỗi
/// frame, khiến cache-miss gần như mỗi frame và rebuild lại TOÀN BỘ dataset
/// (kèm 1 `DateTime` alloc/nến trong `_assignTickWeights`) — rất tốn trong
/// đúng lúc cần mượt nhất. Sai lệch dưới 1px không đổi kết quả chọn tick
/// trong thực tế (`SURPLUS=4` ở threshold đã chừa biên an toàn, không nhạy
/// với sai số nhỏ cỡ này).
class TimeTickPlanner {
  List<TimeTick>? _cachedPlan;
  (int, int, int, int, String)? _cachedKey;

  List<TimeTick> getOrBuild({
    required List<KLineEntity> candles,
    required double barSpacing,
    required int intervalMs,
    List<String>? forcedFormat,
  }) {
    final key = (
      identityHashCode(candles),
      candles.length,
      barSpacing.round(),
      intervalMs,
      forcedFormat?.join('|') ?? '',
    );
    if (key == _cachedKey && _cachedPlan != null) {
      return _cachedPlan!;
    }
    final plan = buildTimeTickPlan(
      candles: candles,
      barSpacing: barSpacing,
      intervalMs: intervalMs,
      forcedFormat: forcedFormat,
    );
    _cachedKey = key;
    _cachedPlan = plan;
    return plan;
  }
}
