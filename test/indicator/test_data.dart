import 'dart:math';

import 'package:k_chart_jk/entity/index.dart';

/// Dữ liệu nến tổng hợp, TẤT ĐỊNH (seed cố định) — dùng chung cho mọi test
/// indicator trong `test/indicator/`. Random walk quanh `startPrice`, OHLC
/// luôn hợp lệ (high >= max(open,close), low <= min(open,close)), vol/amount
/// luôn > 0 (không rơi vào nhánh fallback `(high+low+close)/3` của AVL).
///
/// Cùng seed luôn sinh ra cùng dữ liệu → test assertions ổn định giữa các lần
/// chạy, không cần lưu fixture riêng.
List<KLineEntity> buildKLines(int count, {int seed = 42, double startPrice = 100}) {
  final rnd = Random(seed);
  final list = <KLineEntity>[];
  double prevClose = startPrice;
  for (int i = 0; i < count; i++) {
    final open = prevClose;
    var close = open + (rnd.nextDouble() - 0.5) * 4;
    if (close <= 0) close = open * 0.99;
    final high = max(open, close) + rnd.nextDouble() * 1.5;
    var low = min(open, close) - rnd.nextDouble() * 1.5;
    if (low <= 0) low = min(open, close) * 0.5;
    final vol = 100 + rnd.nextDouble() * 900;
    final amount = vol * (open + close) / 2;
    list.add(
      KLineEntity.fromCustom(
        open: open,
        close: close,
        high: high,
        low: low,
        vol: vol,
        amount: amount,
        time: i * 60000,
      ),
    );
    prevClose = close;
  }
  return list;
}

/// Dựng nến trực tiếp từ 1 chuỗi giá đóng cửa cho trước — KHÔNG có bấc nến
/// (high = max(open,close), low = min(open,close)) — dùng cho test cần trace
/// tay bằng số tròn, dễ kiểm chứng độc lập (MA/EMA/BOLL/RSI/MACD/BIAS/PSY...).
/// `open[i] = close[i-1]` (open[0] = close[0]).
List<KLineEntity> buildKLinesFromCloses(List<double> closes, {List<double>? vols}) {
  final list = <KLineEntity>[];
  double prevClose = closes.first;
  for (int i = 0; i < closes.length; i++) {
    final close = closes[i];
    final open = i == 0 ? close : prevClose;
    final high = max(open, close);
    final low = min(open, close);
    final vol = vols != null ? vols[i] : 1.0;
    list.add(
      KLineEntity.fromCustom(
        open: open,
        close: close,
        high: high,
        low: low,
        vol: vol,
        amount: vol * close,
        time: i * 60000,
      ),
    );
    prevClose = close;
  }
  return list;
}

/// Dựng nến từ danh sách OHLCV tường minh — dùng cho test cần kiểm soát
/// high/low riêng biệt với open/close (SAR/KDJ/WR/CCI/BRAR/ATR/SuperTrend...).
/// Mỗi phần tử: (open, high, low, close, vol).
List<KLineEntity> buildKLinesFromOHLCV(List<(double, double, double, double, double)> rows) {
  final list = <KLineEntity>[];
  for (int i = 0; i < rows.length; i++) {
    final (open, high, low, close, vol) = rows[i];
    list.add(
      KLineEntity.fromCustom(
        open: open,
        close: close,
        high: high,
        low: low,
        vol: vol,
        amount: vol * close,
        time: i * 60000,
      ),
    );
  }
  return list;
}
