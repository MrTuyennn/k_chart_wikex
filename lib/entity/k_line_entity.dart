import '../entity/k_entity.dart';

class KLineEntity extends KEntity {
  late double? amount;
  // late double? turnover;
  double? change;
  double? ratio;
  int? time;

  /// Cache nội bộ cho time-tick planner (`lib/utils/time_ticks.dart`) — mức độ
  /// "đáng chú ý theo lịch" của nến này (đầu giờ/ngày/tháng/năm), tính 1 lần
  /// rồi giữ nguyên, không tính lại mỗi frame. `null` = chưa tính. Không dùng
  /// cho mục đích nào khác ngoài vẽ trục thời gian.
  int? tickWeight;

  KLineEntity.fromCustom({
    this.amount,
    required double open,
    required double close,
    this.change,
    this.ratio,
    required this.time,
    required double high,
    required double low,
    required double vol,
  }) {
    this.open = open;
    this.close = close;
    this.high = high;
    this.low = low;
    this.vol = vol;
  }

  KLineEntity.fromJson(Map<String, dynamic> json) {
    open = json['open']?.toDouble() ?? 0;
    high = json['high']?.toDouble() ?? 0;
    low = json['low']?.toDouble() ?? 0;
    close = json['close']?.toDouble() ?? 0;
    vol = json['vol']?.toDouble() ?? 0;
    amount = json['amount']?.toDouble();
    int? tempTime = json['time']?.toInt();
    //兼容火币数据
    if (tempTime == null) {
      tempTime = json['id']?.toInt() ?? 0;
      tempTime = tempTime! * 1000;
    }
    time = tempTime;
    ratio = json['ratio']?.toDouble();
    change = json['change']?.toDouble();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['time'] = time;
    data['open'] = open;
    data['close'] = close;
    data['high'] = high;
    data['low'] = low;
    data['vol'] = vol;
    data['amount'] = amount;
    data['ratio'] = ratio;
    data['change'] = change;
    return data;
  }

  @override
  String toString() {
    return 'MarketModel{open: $open, high: $high, low: $low, close: $close, vol: $vol, time: $time, amount: $amount, ratio: $ratio, change: $change}';
  }
}
