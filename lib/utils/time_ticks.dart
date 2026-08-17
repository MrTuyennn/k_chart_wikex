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

/// Số tick tối thiểu MUỐN thấy trong 1 khung nhìn rộng `viewportWidth` —
/// dùng làm default cho [buildTimeTickPlan]/[TimeTickPlanner.getOrBuild]
/// tham số `minVisibleTicks`. Đây là target, không phải hằng cứng — chart
/// hẹp hơn `kMinVisibleAxisTicks * kMinGapX` px thì không thể đạt đúng số
/// này mà không phá `kMinGapX` (xem giải thích ở `buildTimeTickPlan`).
const int kMinVisibleAxisTicks = 5;

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

/// 3 pattern cố định dùng cho nhãn TRỤC X mặc định (không custom
/// `timeFormat`/`dateTimeFormat`) — mịn nhất tới thô nhất.
const List<String> kAxisFormatMinute = [hour24Padded, ':', nn];
const List<String> kAxisFormatHour = [mm, '-', dd, ' ', hour24Padded, ':', nn];
const List<String> kAxisFormatDay = [yy, '-', mm, '-', dd];

/// Biến thể RÚT GỌN của [kAxisFormatHour] — bỏ hẳn phần giờ:phút, dùng CHỈ
/// khi 1 tick cụ thể rơi ĐÚNG nửa đêm local (`local.hour == 0 && local.
/// minute == 0`) trong khi format đang hoạt động vẫn là tier "MM-dd HH:mm"
/// (chưa đủ thưa để cả trục chuyển hẳn sang [kAxisFormatDay]). Xem
/// [_labelFor] cho điều kiện áp dụng + lý do an toàn (không gây trùng nhãn).
const List<String> kAxisFormatHourTrimmed = [mm, '-', dd];

/// Chọn 1 trong 3 pattern trên cho nhãn trục X mặc định — kết hợp 3 ràng
/// buộc ĐỘC LẬP, lấy tầng THÔ HƠN giữa các bên:
///
/// - **Tầng "tự nhiên"** suy từ chính `intervalMs`: nến >= 1 ngày (`kDay`
///   trở lên trên trục thời gian thực) không bao giờ có lý do hợp lệ để
///   hiện giờ:phút (luôn rơi đúng 00:00 local do bản chất nến ngày) — LUÔN
///   `yy-MM-dd` bất kể zoom; nến khung giờ (`>= 1h, < 1d`) tối thiểu phải
///   kèm ngày (`MM-dd HH:mm`) để tránh đụng nhãn giữa các NGÀY khác nhau có
///   cùng giờ-trong-ngày; nến khung phút (`< 1h`) không cần ràng buộc gì
///   thêm, mịn nhất `HH:mm` cũng đủ.
/// - **Tầng "theo zoom" (từ threshold)** suy từ [thresholdRung] — cùng hàm
///   quyết định tick nào ĐỦ ĐIỀU KIỆN làm ứng viên (TRƯỚC khi đóng gói theo
///   `kMinGapX`). Zoom càng ra xa, ngưỡng weight cần thiết càng cao — khi nó
///   chạm mốc [kDay] trở lên, format tự đổi sang `yy-MM-dd`.
/// - **Tầng "theo zoom" (từ mật độ ngày)** — bổ sung RIÊNG cho tier2, xem
///   chi tiết + lý do cần thiết ngay trong thân hàm bên dưới (đo TRỰC TIẾP
///   xem 1 ngày lịch có chiếm đủ `kMinGapX` px để 2 tick cùng ngày có thể
///   cùng sống sót qua đóng gói hay không — không phụ thuộc `threshold`).
///
/// **Vì sao cần CẢ HAI, không chỉ 1 trong 2:**
///  - Chỉ dùng tầng theo zoom: nến 30 phút/4h zoom ra xa mà format vẫn cho
///    phép `HH:mm` (chưa chạm ngưỡng) thì tick đầu-ngày (00:00 local) vẫn có
///    thể bị chọn cùng lúc với tick giữa-ngày khác giờ — hoạ hiếm, nhưng
///    tầng tự nhiên xử lý sẵn nên không cần lo riêng.
///  - Chỉ dùng tầng tự nhiên: sẽ KHÔNG bao giờ tự đổi sang `yy-MM-dd` khi
///    zoom ra xa với nến khung phút/giờ (30m/4h) — đúng bug đã gặp: format
///    khoá cứng theo interval GỐC khiến tick đầu-ngày vẫn hiện `HH:mm`/
///    `MM-dd HH:mm` → nhiều tick cùng lúc trông như lặp lại "00:00".
///  - Chỉ dùng tầng theo zoom, THIẾU tầng tự nhiên: với nến interval đã
///    `>= 1 ngày` (1D trở lên), `thresholdRung` gần như LUÔN kẹt ở mức tối
///    thiểu bất kể `barSpacing` — vì `period = max(rung.nominalPeriodMs,
///    intervalMs)` trong `thresholdRung` bị chính `intervalMs` (rất lớn) áp
///    trần từ bậc thấp nhất của ladder, khiến `required` hầu như luôn nhỏ
///    hơn. Xác nhận bằng cách tính tay cho interval=86400000 ở dải
///    `barSpacing` thực tế (2.2–24.2px, `pointWidth(11) *
///    [minScale(0.2)..maxScale(2.2)]` mặc định) — `threshold` luôn dưới
///    `kHour1`. Nếu chỉ dùng tầng theo zoom, nến 1D sẽ bị hiện `HH:mm` (in
///    "00:00" lặp lại MỌI tick) kể cả khi zoom vào GẦN, không chỉ lúc zoom
///    xa — nặng hơn cả bug gốc.
List<String> axisFormatFor(double barSpacing, int intervalMs) {
  final int naturalTier = intervalMs >= 24 * 60 * 60 * 1000
      ? 2
      : intervalMs >= 60 * 60 * 1000
      ? 1
      : 0;

  final int threshold = thresholdRung(barSpacing, intervalMs);
  final int zoomTierFromThreshold = threshold >= kDay
      ? 2
      : (threshold >= kHour1 ? 1 : 0);

  // Bổ sung 1 điều kiện AN TOÀN riêng cho tier2, ĐỘC LẬP với `threshold`:
  // nếu 1 ngày lịch chiếm ÍT HƠN `kMinGapX` px ở `barSpacing` này thì 2 tick
  // BẤT KỲ (thật hay filler — không quan trọng) cùng ngày chắc chắn cách
  // nhau < kMinGapX, nên bước đóng gói `kMinGapX` (áp dụng đều cho MỌI ứng
  // viên, xem bucket-packing trong `buildTimeTickPlan`) TỰ ĐỘNG đảm bảo tối
  // đa 1 tick sống sót/ngày — an toàn tuyệt đối để hiện `yy-MM-dd` mà không
  // cần biết cụ thể tick nào thật/filler.
  //
  // **Vì sao cần thêm điều kiện này — chỉ `threshold` không đủ:** `threshold`
  // là ngưỡng để 1 nến được coi là ỨNG VIÊN, tính TRƯỚC bước đóng gói — với
  // nến 1H ở `barSpacing≈2.2` (zoom hết cỡ, `minScale=0.2` mặc định),
  // `threshold` chỉ đạt `kHour12`, KHÔNG đạt `kDay`, dù 2 ứng viên cùng ngày
  // gần nhất (00:00 và 12:00, cách nhau 12 nến × 2.2px ≈ 26.4px) chắc chắn
  // đụng nhau khi đóng gói (< kMinGapX=64px) — plan CUỐI CÙNG trên thực tế
  // đã tự nhiên ≤1 tick/ngày, chỉ là `threshold` (đo TRƯỚC đóng gói) đánh giá
  // sai là "chưa đủ thưa". Hệ quả nếu thiếu điều kiện này: nến 5m/15m/30m/1H
  // KẸT VĨNH VIỄN ở tier "MM-dd HH:mm", không bao giờ lên được `yy-MM-dd` dù
  // zoom tới đúng `minScale` — bug thực tế đã gặp, xác nhận bằng cách tính
  // tay `threshold` cho từng khung ở `barSpacing=2.2`: 5m/15m/30m/1H chỉ đạt
  // 20–23, thiếu hẳn so với `kDay=30`.
  //
  // Dùng `<` (không phải `<=`) — tại đúng `pixelsPerDay == kMinGapX`, 2 nến
  // ở 2 MÉP xa nhau nhất trong cùng 1 ngày cách nhau ĐÚNG `kMinGapX`, không
  // đụng theo điều kiện `< kMinGapX` của bucket-packing — cần dư ra 1 chút
  // mới chắc chắn.
  final double pixelsPerDay =
      (24 * 60 * 60 * 1000 / intervalMs) * barSpacing;
  final int zoomTierFromDayDensity = pixelsPerDay < kMinGapX ? 2 : 0;

  final int zoomTier = zoomTierFromThreshold > zoomTierFromDayDensity
      ? zoomTierFromThreshold
      : zoomTierFromDayDensity;
  final int tier = naturalTier > zoomTier ? naturalTier : zoomTier;
  if (tier >= 2) return kAxisFormatDay;
  if (tier >= 1) return kAxisFormatHour;
  return kAxisFormatMinute;
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
///
/// [allowMidnightTrim]: xem giải thích đầy đủ ở [_shouldTrimMidnight] —
/// TUYỆT ĐỐI không suy từ nội dung `forcedFormat` (vd so `identical` với
/// [kAxisFormatHour]), phải do NGƯỜI GỌI (biết chắc nguồn gốc format) truyền
/// vào tường minh. Mặc định `false` (an toàn — không trim) cho ai gọi hàm
/// này trực tiếp mà không cân nhắc; `BaseChartPainter._updateTimeTicks` là
/// nơi DUY NHẤT được phép truyền `true`, và chỉ khi chắc chắn format đến từ
/// chính [axisFormatFor] (không phải override của consumer).
String labelForCandle(
  KLineEntity candle, {
  List<String>? forcedFormat,
  bool allowMidnightTrim = false,
}) {
  final local = DateTime.fromMillisecondsSinceEpoch(candle.time ?? 0);
  return _labelFor(local, candle.tickWeight ?? kMinor, forcedFormat, allowMidnightTrim);
}

/// [_labelFor] dùng cho 1 tick ĐƠN LẺ, không có tick nào khác để so — chỉ
/// dùng cho Fallback B ([labelForCandle]). Với trim nửa đêm ở
/// [kAxisFormatHour], vì không biết tick kế tiếp (nếu có) có cùng ngày hay
/// không, cứ trim khi rơi đúng nửa đêm — hợp lý vì đây là tick DUY NHẤT đang
/// hiển thị, không có tick nào khác cùng ngày để cần phân biệt.
String _labelFor(
  DateTime local,
  int weight,
  List<String>? forcedFormat,
  bool allowMidnightTrim,
) {
  if (forcedFormat != null) {
    if (_shouldTrimMidnight(forcedFormat, local, allowMidnightTrim)) {
      return dateFormat(local, kAxisFormatHourTrimmed);
    }
    return dateFormat(local, forcedFormat);
  }
  return _weightEscalatedLabel(local, weight);
}

/// Quyết định có trim giờ:phút cho 1 tick nửa đêm hay không.
///
/// **[allowMidnightTrim] là NGUỒN SỰ THẬT DUY NHẤT — không được suy ra từ
/// `identical(forcedFormat, kAxisFormatHour)`.** Từng dùng `identical()` làm
/// tín hiệu "format này là do lib tự chọn, an toàn để trim" — SAI, vì
/// [kAxisFormatHour] là const PUBLIC (export qua `utils/index.dart` →
/// `k_chart_plus.dart`): consumer hoàn toàn có thể tự import rồi truyền
/// thẳng `timeFormat: kAxisFormatHour` để ÉP CỐ ĐỊNH "luôn hiện đủ giờ:phút,
/// bất kể zoom" (đúng cam kết "Force ... regardless of zoom" trong README)
/// — khi đó `forcedFormat` VẪN `identical` với [kAxisFormatHour] (cùng
/// object reference), nên logic cũ vẫn tự ý trim, ÂM THẦM phá cam kết
/// "force" của chính consumer. Phát hiện qua `/code-review`, xác nhận bằng
/// cách gọi trực tiếp `buildTimeTickPlan(forcedFormat: kAxisFormatHour,...)`
/// — nến nửa đêm bị trim dù đã "force" tường minh.
///
/// Sửa: CHỈ nơi gọi (`BaseChartPainter._updateTimeTicks`, nơi DUY NHẤT biết
/// chắc format có phải do [axisFormatFor] tự chọn hay do `chartStyle.
/// dateTimeFormat` của consumer) mới được quyết định `allowMidnightTrim` —
/// `chartStyle.dateTimeFormat == null` (không custom) mới truyền `true`.
bool _shouldTrimMidnight(
  List<String> forcedFormat,
  DateTime local,
  bool allowMidnightTrim,
) =>
    allowMidnightTrim &&
    identical(forcedFormat, kAxisFormatHour) &&
    local.hour == 0 &&
    local.minute == 0;

String _weightEscalatedLabel(DateTime local, int weight) {
  if (weight >= kYear) return dateFormat(local, const [yyyy]);
  if (weight >= kMonth) return dateFormat(local, const [M]);
  if (weight >= kDay) return dateFormat(local, const [d]);
  return dateFormat(local, const [hour24Padded, ':', nn]);
}

/// Gán label cho TOÀN BỘ [accepted] (đã sort theo `absX`) — khác [_labelFor]
/// ở chỗ CÓ xét tick KẾ TIẾP trong cùng danh sách để quyết định có trim
/// nửa đêm hay không:
///
/// - Nếu tick kế tiếp rơi CÙNG NGÀY lịch (vd `08-13 00:00` rồi `08-13
///   12:00`) — GIỮ NGUYÊN đầy đủ "MM-dd HH:mm" cho tick nửa đêm, vì trong
///   ngày đó còn tick khác cần giờ:phút để phân biệt; trim riêng 1 mình tick
///   nửa đêm trong khi tick kế bên vẫn đủ giờ:phút sẽ trông LỆCH KIỂU (1 có
///   giờ, 1 không) dù cùng 1 ngày.
/// - Nếu tick kế tiếp đã sang NGÀY KHÁC (hoặc không còn tick nào sau) — vd
///   `08-13 00:00`, `08-14 00:00`, `08-15 00:00` — trim CẢ CHUỖI, vì không
///   tick nào trong đó có "hàng xóm cùng ngày" cần phân biệt bằng giờ:phút.
///
/// Nửa đêm chỉ xảy ra ĐÚNG 1 lần/ngày nên tick kế tiếp KHÔNG BAO GIỜ có thể
/// vừa cùng ngày vừa cũng là nửa đêm (2 tick khác nhau cùng ngày thì tối đa
/// 1 trong 2 là nửa đêm) — điều kiện "cùng ngày" ở trên luôn ứng với đúng 1
/// cặp (nửa đêm, giờ khác) chứ không bao giờ (nửa đêm, nửa đêm) trùng.
List<TimeTick> _labelAccepted(
  List<_Candidate> accepted,
  List<KLineEntity> candles,
  List<String>? forcedFormat,
  bool allowMidnightTrim,
) {
  final locals = List<DateTime>.generate(
    accepted.length,
    (i) => DateTime.fromMillisecondsSinceEpoch(
      candles[accepted[i].index].time ?? 0,
    ),
  );

  return List<TimeTick>.generate(accepted.length, (i) {
    final c = accepted[i];
    final local = locals[i];
    String label;
    if (forcedFormat != null) {
      final bool nextIsSameDay =
          i + 1 < locals.length &&
          locals[i + 1].year == local.year &&
          locals[i + 1].month == local.month &&
          locals[i + 1].day == local.day;
      if (!nextIsSameDay &&
          _shouldTrimMidnight(forcedFormat, local, allowMidnightTrim)) {
        label = dateFormat(local, kAxisFormatHourTrimmed);
      } else {
        label = dateFormat(local, forcedFormat);
      }
    } else {
      label = _weightEscalatedLabel(local, c.weight);
    }
    return TimeTick(index: c.index, weight: c.weight, label: label);
  });
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
/// theo MIN_GAP_X) đảm bảo điều này (§5.2, T1). Đó chỉ là cam kết "≥1 tick,
/// không bao giờ trống" — KHÔNG cam kết đủ MẬT ĐỘ theo bề rộng màn hình:
/// interval lớn (vd nến 4h) zoom rất sâu có thể khiến ngưỡng weight nhảy
/// thẳng lên hẳn 1 bậc rất thưa (DAY → MONTH, cách nhau ~30 lần) trong khi
/// ngay bên dưới đã có Fallback B chỉ hiện ĐÚNG 1 tick giữa màn hình, dù
/// viewport còn thừa chỗ cho nhiều nhãn hơn. `viewportWidth`/`minVisibleTicks`
/// (mặc định [kMinVisibleAxisTicks]) xử lý đúng trường hợp này — xem đoạn
/// "đảm bảo mật độ tối thiểu" bên dưới.
List<TimeTick> buildTimeTickPlan({
  required List<KLineEntity> candles,
  required double barSpacing,
  required int intervalMs,
  List<String>? forcedFormat,
  double viewportWidth = 0,
  int minVisibleTicks = kMinVisibleAxisTicks,
  bool allowMidnightTrim = false,
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

  // Đảm bảo mật độ tối thiểu (§5.2-ext, KHÁC Fallback A ở trên — Fallback A
  // chỉ kích hoạt khi `candidates` RỖNG hoàn toàn; đây áp dụng LUÔN, kể cả
  // khi weight-ladder đã cho vài tick nhưng chúng THƯA hơn
  // `viewportWidth/minVisibleTicks` — đúng trường hợp nến 4h zoom sâu). Chạy
  // SAU khi đóng gói MIN_GAP_X xong (không trộn vào `candidates` trước đó —
  // đã thử, 1 tick THẬT nằm giữa 2 tick lưới-đều có thể loại CẢ HAI nếu cả
  // hai cùng trong bán kính `kMinGapX`, làm khoảng trống PHÌNH to hơn dự
  // kiến thay vì thu hẹp; xác nhận bằng test — quan sát gap 132px dù target
  // chỉ 79px). Ở đây lấp trực tiếp từng khoảng trống > `maxGap` trong
  // [accepted] đã ổn định, không đụng vào tick nào đã có.
  if (viewportWidth > 0 && minVisibleTicks > 1) {
    _fillDensityGaps(
      accepted: accepted,
      candles: candles,
      barSpacing: barSpacing,
      viewportWidth: viewportWidth,
      minVisibleTicks: minVisibleTicks,
    );
  }

  return _labelAccepted(accepted, candles, forcedFormat, allowMidnightTrim);
}

/// Lấp các đoạn TRỐNG quá rộng trong [accepted] (đã sort theo `absX`, sau
/// bước đóng gói `kMinGapX`) để bất kỳ cửa sổ rộng [viewportWidth] nào cũng
/// thấy ≥ [minVisibleTicks] tick, mutate `accepted` in-place rồi sort lại.
///
/// `maxGap = max(kMinGapX, viewportWidth / minVisibleTicks)` — chia cho N
/// (không phải N-1): 1 cửa sổ rộng W chứa các điểm cách đều `g` luôn có ít
/// nhất `floor(W/g)` điểm ở VỊ TRÍ CUỘN XẤU NHẤT (cửa sổ lệch pha so với
/// lưới điểm); cần `g <= W/N` mới chắc chắn `floor(W/g) >= N` ở MỌI vị trí
/// — đã verify bằng cách quét toàn bộ vị trí cửa sổ có thể (`g <= W/(N-1)`
/// cho kết quả tệ nhất chỉ N-2 tick, không đạt N).
///
/// Mỗi đoạn `[left, right]` (kể cả 2 mép — trước tick đầu tiên/sau tick cuối
/// cùng đã chọn, tới đúng mép dữ liệu) rộng hơn `maxGap` được CHIA ĐỀU theo
/// đúng chiều dài ĐOẠN ĐÓ (không phải theo 1 lưới chỉ số cố định toàn cục —
/// đã thử, lưới cố định không thích ứng theo độ dài từng đoạn cụ thể nên
/// luôn để lại 1 "đuôi" thừa/thiếu ở mép nối với tick thật, có lúc để hở gap
/// 92px dù target chỉ 80px, xác nhận bằng test — 1 đoạn dài 409px lẽ ra cần
/// đúng 5 điểm chèn (409/6≈68px/mảnh) nhưng lưới cố định step=79px chỉ chèn
/// vừa 4 điểm rồi bó tay ở phần dư). Số mảnh chọn theo `idealPieces =
/// ceil(gap / (maxGap - barSpacing))` — trừ đi 1 `barSpacing` làm biên an
/// toàn cho sai số làm tròn khi quy đổi vị trí phân số về chỉ số nến gần
/// nhất (mỗi điểm có thể lệch tới `barSpacing/2`, 2 điểm liền kề cộng dồn
/// tối đa `barSpacing`) — không trừ biên này từng cho gap thực tế 77px dù
/// target 72px, xác nhận bằng test. Đồng thời KHÔNG được chia dày hơn mức
/// mỗi mảnh ≥ `kMinGapX` (đọc được, ưu tiên hơn target N khi 2 điều kiện
/// xung đột — viewport quá hẹp so với `minVisibleTicks`) — chốt bằng
/// `pieces = min(idealPieces, maxPieces)`.
///
/// Chạy 1 lần khi build plan (không phụ thuộc `scrollOffset`) nên an toàn
/// với I4 — chỉ đổi khi `barSpacing`/`interval`/`candles.length`/
/// `viewportWidth` đổi, đúng lúc plan được rebuild theo cache key ở
/// [TimeTickPlanner].
void _fillDensityGaps({
  required List<_Candidate> accepted,
  required List<KLineEntity> candles,
  required double barSpacing,
  required double viewportWidth,
  required int minVisibleTicks,
}) {
  final double maxGap = math.max(kMinGapX, viewportWidth / minVisibleTicks);
  // Biên an toàn cho sai số làm tròn — xem giải thích ở doc comment trên.
  final double marginedMaxGap = math.max(barSpacing, maxGap - barSpacing);
  final int lastIndex = candles.length - 1;
  double absX(int i) => i * barSpacing + barSpacing / 2;

  final List<double> boundary = [
    absX(0),
    for (final c in accepted) c.absX,
    absX(lastIndex),
  ];

  final List<_Candidate> inserted = [];
  for (int seg = 0; seg < boundary.length - 1; seg++) {
    final double left = boundary[seg];
    final double right = boundary[seg + 1];
    final double gap = right - left;
    if (gap <= maxGap) continue;

    final int idealPieces = (gap / marginedMaxGap).ceil();
    final int maxPieces = math.max(1, (gap / kMinGapX).floor());
    final int pieces = math.min(idealPieces, maxPieces);
    if (pieces <= 1) continue;

    double prevX = left;
    for (int k = 1; k <= pieces - 1; k++) {
      final double targetX = left + gap * k / pieces;
      final int idx = ((targetX - barSpacing / 2) / barSpacing)
          .round()
          .clamp(0, lastIndex);
      final double x = absX(idx);
      // Backstop cho sai số làm tròn còn sót — `pieces` đã tính để mỗi mảnh
      // ≥ kMinGapX + biên an toàn ở trên, hiếm khi kích hoạt nhánh này.
      if (x - prevX < kMinGapX || right - x < kMinGapX) continue;
      inserted.add(_Candidate(idx, x, candles[idx].tickWeight ?? kMinor));
      prevX = x;
    }
  }

  accepted.addAll(inserted);
  accepted.sort((a, b) => a.absX.compareTo(b.absX));
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
  (int, int, int, int, String, int, int, bool)? _cachedKey;

  List<TimeTick> getOrBuild({
    required List<KLineEntity> candles,
    required double barSpacing,
    required int intervalMs,
    List<String>? forcedFormat,
    double viewportWidth = 0,
    int minVisibleTicks = kMinVisibleAxisTicks,
    bool allowMidnightTrim = false,
  }) {
    final key = (
      identityHashCode(candles),
      candles.length,
      barSpacing.round(),
      intervalMs,
      forcedFormat?.join('|') ?? '',
      // Làm tròn giống `barSpacing` — viewportWidth chỉ đổi khi resize/xoay
      // màn hình, không đổi khi pan/zoom, nhưng vẫn làm tròn cho nhất quán
      // và tránh cache-miss vì sai số dưới-px không ảnh hưởng kết quả chọn.
      viewportWidth.round(),
      minVisibleTicks,
      allowMidnightTrim,
    );
    if (key == _cachedKey && _cachedPlan != null) {
      return _cachedPlan!;
    }
    final plan = buildTimeTickPlan(
      candles: candles,
      barSpacing: barSpacing,
      intervalMs: intervalMs,
      forcedFormat: forcedFormat,
      viewportWidth: viewportWidth,
      minVisibleTicks: minVisibleTicks,
      allowMidnightTrim: allowMidnightTrim,
    );
    _cachedKey = key;
    _cachedPlan = plan;
    return plan;
  }
}
