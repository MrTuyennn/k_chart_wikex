import 'dart:math' as math;

import 'package:k_chart_jk/k_chart_plus.dart';

import '../market/market_kline.dart';

/// Gộp 1 bar WS vào series nến — theo `trade_candle_chart_data_flow.md` §3,
/// đối chiếu từ 1 app production khác dùng `k_chart_jk`
/// (`KlineSeriesReducer.apply`/`applyLiveUpdate`). Trùng nến ĐANG CHẠY (xem
/// [_isSameCandle]) → merge có chọn lọc vào đó (xem [mergeIntoRunningCandle],
/// KHÔNG thay thế toàn bộ); mới hơn hẳn 1 interval → append; còn lại → insert
/// đúng vị trí (case REST refetch/historical backfill lẫn vào series đang
/// có). Luôn trả list MỚI — không sửa in-place, để `KChartWidget` thấy
/// reference đổi mà repaint.
///
/// [intervalMs]: độ dài 1 nến theo timeframe đang chọn (`ChartTimeframe.
/// interval.inMilliseconds`) — cần để [_isSameCandle] chấp nhận cả 2 cách
/// đọc timestamp WS (xem doc ở đó).
List<KLineEntity> mergeKlineBar(
  List<KLineEntity> series,
  MarketKline bar, {
  required int intervalMs,
}) {
  final int t = bar.barCloseTime.millisecondsSinceEpoch;
  if (series.isEmpty) return [bar.toEntity()];
  if (_isSameCandle(t, series.last.time!, intervalMs)) {
    return [...series]
      ..[series.length - 1] = mergeIntoRunningCandle(series.last, bar);
  }
  if (t > series.last.time! + intervalMs) return [...series, bar.toEntity()];
  for (var i = series.length - 1; i >= 0; i--) {
    final int ti = series[i].time!;
    if (_isSameCandle(t, ti, intervalMs)) {
      return [...series]..[i] = mergeIntoRunningCandle(series[i], bar);
    }
    if (ti < t) return [...series]..insert(i + 1, bar.toEntity());
  }
  return [bar.toEntity(), ...series];
}

/// True nếu timestamp WS [wsTime] và timestamp đã lưu [existingTime] (LUÔN
/// là open-time — xem doc [mergeIntoRunningCandle]) đại diện CÙNG 1 nến.
///
/// **Không giả định cứng** WS gửi `time` theo open hay close time — 2 quy
/// ước này khác nhau tuỳ sàn/endpoint, và REST (`market_history_api.dart`)
/// đã verify thực tế là open-time trong khi WS chưa verify được (không có
/// công cụ snoop socket ở môi trường phát triển) — nếu WS thật ra gửi
/// close-time (= open-time + `intervalMs`), so khớp CỨNG theo `==` sẽ khiến
/// tick WS đầu tiên của 1 nến KHÔNG match được nến đang có (lệch đúng
/// 1 interval), rơi vào nhánh "nến mới" và tạo ra 1 entry TRÙNG nến nhưng
/// timestamp tương lai — đúng triệu chứng "label hiện giờ chưa tới, cả nến
/// cũ cũng sai" đã gặp. Chấp nhận cả 2 cách đọc ở đây an toàn dù giả thuyết
/// đúng hay sai (không làm hỏng trường hợp WS thật sự gửi open-time).
bool _isSameCandle(int wsTime, int existingTime, int intervalMs) =>
    wsTime == existingTime || wsTime == existingTime + intervalMs;

/// Công thức merge 1 tick WS vào nến ĐANG CHẠY (trùng `barCloseTime` với nến
/// cuối/đang có) — theo `trade_candle_chart_data_flow.md` §3.2. KHÔNG thay
/// thế toàn bộ nến bằng entity WS mới — mỗi tick WS chỉ phản ánh state TẠI
/// THỜI ĐIỂM ĐÓ, không chắc đã bao trọn toàn bộ range/đã ổn định `open` của
/// cả nến:
///  - `open`  : GIỮ nguyên từ [existing] (REST/tick trước) — KHÔNG lấy từ
///    WS, vì tick đầu tiên đến sau khi nến đã chạy 1 lúc sẽ làm mất phần đầu
///    nến nếu lấy `open` từ đó.
///  - `high`/`low` : ENVELOPE (`max`/`min` với giá trị đã có) — 1 tick WS
///    riêng lẻ không chắc đã thấy hết biên độ giá của cả nến.
///  - `close`/`vol`/`amount` : LUÔN lấy giá trị WS mới nhất — sàn trả
///    cumulative-trong-nến (không phải delta từng tick), gán trực tiếp là
///    đúng; cộng dồn tay ở đây sẽ double-count.
///  - `time`  : GIỮ nguyên từ [existing], KHÔNG bao giờ lấy từ WS — cùng lý
///    do như `open`: nếu WS gửi close-time (xem [_isSameCandle]) mà lấy
///    thẳng giá trị đó, timestamp của nến sẽ nhảy thành open-time + 1
///    interval, tức "tương lai" so với open-time thật của nến.
KLineEntity mergeIntoRunningCandle(
  KLineEntity existing,
  MarketKline incoming,
) {
  return KLineEntity.fromCustom(
    time: existing.time,
    open: existing.open,
    high: math.max(existing.high, incoming.high.toDouble()),
    low: math.min(existing.low, incoming.low.toDouble()),
    close: incoming.close.toDouble(),
    vol: incoming.volume.toDouble(),
    amount: incoming.turnover.toDouble(),
  );
}
