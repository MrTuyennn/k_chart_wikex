/// Nice-number tick generation cho trục giá (Y) — theo CHART_AXES.md §6.3-§6.4.
///
/// Khác với cách chia đều pixel hiện có (label = giá suy ra ngược từ vị trí
/// pixel cố định, KHÔNG phải số tròn), 3 hàm ở đây sinh ra tập giá trị "đẹp"
/// (1/2/2.5/5/10 × 10^n) rồi mới map sang pixel — giống cách MEXC/Binance/
/// TradingView vẽ trục giá.
library;

import 'dart:math' as math;

/// Số bước lặp tối đa khi sinh tick — chặn vòng lặp vô hạn nếu `step` = 0 do
/// input suy biến (FAILURE MODE 5 trong spec: cộng dồn `p += step` có thể trôi
/// số, ở đây tránh hẳn bằng cách nhân chỉ số thay vì cộng dồn, nhưng vẫn giữ
/// guard phòng thân).
const int _kMaxTickIterations = 64;

/// Sinh "step" đẹp cho khoảng giá trị [range], nhắm tới khoảng [targetTicks]
/// mốc. Ladder `1 · 2 · 2.5 · 5 · 10` — xem §6.5 về caveat khi step chuyển từ
/// 2.5 xuống 2 (không nested hoàn toàn, chấp nhận được, đã document trong spec).
double niceStep(double range, int targetTicks) {
  final double safeRange = range <= 0 ? 1e-9 : range;
  final int safeTarget = targetTicks < 1 ? 1 : targetTicks;
  final double raw = safeRange / safeTarget;
  final double mag = math.pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  final double n = raw / mag;
  final double multiplier = n <= 1
      ? 1
      : n <= 2
          ? 2
          : n <= 2.5
              ? 2.5
              : n <= 5
                  ? 5
                  : 10;
  return mag * multiplier;
}

/// Số chữ số thập phân cần thiết để hiển thị [step] không mất thông tin.
///
/// KHÔNG suy từ magnitude (`step >= 1 ? 0 : -floor(log10(step))`) — sai với
/// họ step `2.5` (FAILURE MODE 6): `2.5/5.0/7.5` sẽ hiện thành `2/5/8`. Thay
/// vào đó nhân 10 lặp tới khi giá trị làm tròn về số nguyên.
int decimalsFor(double step) {
  int d = 0;
  double s = step;
  while (d < 8 && (s - s.roundToDouble()).abs() > 1e-9) {
    s *= 10;
    d++;
  }
  return d;
}

/// Sinh danh sách giá trị tick "tròn" nằm trong `[minPrice, maxPrice]`.
///
/// `target` = `min(targetTicks, max(2, height ~/ minGapY))` — chart thấp thì
/// tự giảm số tick để không đè label lên nhau (§6.3).
///
/// Giá trị tick tính bằng `(firstIndex + k) * step` (nhân chỉ số, không cộng
/// dồn) để tránh trôi số dấu phẩy động sau vài chục vòng lặp (FAILURE MODE 5).
List<double> priceTicks({
  required double minPrice,
  required double maxPrice,
  required double height,
  int targetTicks = 6,
  double minGapY = 32.0,
}) {
  if (maxPrice <= minPrice || height <= 0) return const [];

  final double range = maxPrice - minPrice;
  final int target = math.min(
    targetTicks,
    math.max(2, (height / minGapY).floor()),
  );
  final double step = niceStep(range, target);
  if (step <= 0) return const [];

  final int firstIndex = (minPrice / step).ceil();
  final List<double> ticks = [];
  for (int k = 0; k < _kMaxTickIterations; k++) {
    final double p = (firstIndex + k) * step;
    if (p > maxPrice) break;
    if (p >= minPrice) ticks.add(p);
  }
  return ticks;
}
