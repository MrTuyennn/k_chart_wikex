// Khoá lại đúng công thức merge ở trade_candle_chart_data_flow.md §3.2:
// open giữ từ nến đang có (KHÔNG lấy từ WS), high/low envelope, close/vol/
// turnover luôn lấy giá trị WS mới nhất.
import 'package:decimal/decimal.dart';
import 'package:example/bloc/kline_merge.dart';
import 'package:example/market/market_kline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/k_chart_plus.dart';

MarketKline _kline({
  required int closeTimeMs,
  required double open,
  required double high,
  required double low,
  required double close,
  required double volume,
  String period = '1hour',
}) {
  return MarketKline(
    symbol: 'BTC/USDT',
    period: period,
    open: Decimal.parse(open.toString()),
    high: Decimal.parse(high.toString()),
    low: Decimal.parse(low.toString()),
    close: Decimal.parse(close.toString()),
    volume: Decimal.parse(volume.toString()),
    turnover: Decimal.parse((close * volume).toString()),
    barCloseTime: DateTime.fromMillisecondsSinceEpoch(closeTimeMs, isUtc: true),
  );
}

void main() {
  group('mergeIntoRunningCandle', () {
    test('giữ open cũ, KHÔNG lấy open từ tick WS mới', () {
      final existing = KLineEntity.fromCustom(
        time: 1000,
        open: 100,
        high: 101,
        low: 99,
        close: 100.5,
        vol: 5,
      );
      final incoming = _kline(
        closeTimeMs: 1000,
        open: 999, // open "sai" từ WS — không được lấy giá trị này
        high: 101,
        low: 99,
        close: 100.5,
        volume: 5,
      );
      final merged = mergeIntoRunningCandle(existing, incoming);
      expect(merged.open, 100); // vẫn là open cũ, không phải 999
    });

    test('high/low envelope — không bị tick mới thu hẹp range đã thấy', () {
      final existing = KLineEntity.fromCustom(
        time: 1000,
        open: 100,
        high: 105, // range rộng hơn đã từng thấy
        low: 95,
        close: 100,
        vol: 5,
      );
      final incoming = _kline(
        closeTimeMs: 1000,
        open: 100,
        high: 102, // tick mới hẹp hơn — KHÔNG được ghi đè high đã rộng hơn
        low: 98,
        close: 101,
        volume: 6,
      );
      final merged = mergeIntoRunningCandle(existing, incoming);
      expect(merged.high, 105); // giữ nguyên, không bị 102 ghi đè
      expect(merged.low, 95); // giữ nguyên, không bị 98 ghi đè
    });

    test('high/low mở rộng khi tick mới vượt range cũ', () {
      final existing = KLineEntity.fromCustom(
        time: 1000,
        open: 100,
        high: 101,
        low: 99,
        close: 100,
        vol: 5,
      );
      final incoming = _kline(
        closeTimeMs: 1000,
        open: 100,
        high: 110, // vượt cao hơn hẳn
        low: 90, // thấp hơn hẳn
        close: 100,
        volume: 6,
      );
      final merged = mergeIntoRunningCandle(existing, incoming);
      expect(merged.high, 110);
      expect(merged.low, 90);
    });

    test('close/vol luôn lấy giá trị WS mới nhất (không cộng dồn)', () {
      final existing = KLineEntity.fromCustom(
        time: 1000,
        open: 100,
        high: 101,
        low: 99,
        close: 100,
        vol: 5,
      );
      final incoming = _kline(
        closeTimeMs: 1000,
        open: 100,
        high: 101,
        low: 99,
        close: 103.5,
        volume: 12, // cumulative-trong-nến, không phải delta
      );
      final merged = mergeIntoRunningCandle(existing, incoming);
      expect(merged.close, 103.5);
      expect(merged.vol, 12); // = giá trị WS, không phải 5+12
    });
  });

  group('mergeKlineBar', () {
    test('bar mới hơn nến cuối → append', () {
      final series = [
        KLineEntity.fromCustom(time: 1000, open: 1, high: 1, low: 1, close: 1, vol: 1),
      ];
      // closeTimeMs cách nến cuối HẲN 2 interval — không rơi vào biên mập mờ
      // open-time/close-time (existing.time + intervalMs), chắc chắn là nến
      // mới.
      final result = mergeKlineBar(
        series,
        _kline(closeTimeMs: 3000, open: 2, high: 2, low: 2, close: 2, volume: 2),
        intervalMs: 1000,
      );
      expect(result.length, 2);
      expect(result.last.time, 3000);
    });

    test('bar trùng barCloseTime với nến cuối → merge vào nến đang chạy, không append', () {
      final series = [
        KLineEntity.fromCustom(time: 1000, open: 100, high: 101, low: 99, close: 100, vol: 5),
      ];
      final result = mergeKlineBar(
        series,
        _kline(closeTimeMs: 1000, open: 999, high: 102, low: 98, close: 101, volume: 6),
        intervalMs: 1000,
      );
      expect(result.length, 1); // không tạo thêm phần tử
      expect(result.single.open, 100); // giữ open cũ
      expect(result.single.close, 101); // close mới
      expect(result.single.time, 1000); // time giữ nguyên, không lấy từ WS
    });

    test(
      'barCloseTime = existing.time + intervalMs, wall-clock CÒN trong nến cũ '
      '(WS gửi close-time) → phân xử là CÙNG nến, merge, không tạo nến trùng tương lai',
      () {
        // Nến đang chạy: open-time=1000, interval=1000ms. WS gửi
        // barCloseTime=2000 (= 1000+1000, mập mờ giữa "open-time nến MỚI" và
        // "close-time nến CŨ"). Đồng hồ tường "bây giờ" = 1500 — vẫn nằm
        // trong [1000, 2000) của nến cũ → phải hiểu là close-time, merge vào
        // nến đang có, KHÔNG tạo nến mới với timestamp "tương lai" (đúng bug
        // gốc đã gặp).
        final series = [
          KLineEntity.fromCustom(time: 1000, open: 100, high: 101, low: 99, close: 100, vol: 5),
        ];
        final result = mergeKlineBar(
          series,
          _kline(closeTimeMs: 2000, open: 999, high: 102, low: 98, close: 101, volume: 6),
          intervalMs: 1000,
          now: DateTime.fromMillisecondsSinceEpoch(1500, isUtc: true),
        );
        expect(result.length, 1); // merge vào nến đang có, KHÔNG append mới
        expect(result.single.time, 1000); // timestamp giữ nguyên open-time cũ
        expect(result.single.open, 100); // giữ open cũ
        expect(result.single.close, 101); // close mới từ WS
      },
    );

    test(
      'barCloseTime = existing.time + intervalMs, wall-clock ĐÃ SANG nến mới '
      '(WS gửi open-time, nến MỚI thật sự) → phân xử là nến KHÁC, append — '
      'không bị merge nhầm vào nến cũ (lỗ hổng phát hiện qua /code-review, '
      'trước đây "||" ambiguous sẽ merge nhầm ở đây và rớt mất nến)',
      () {
        // Cùng giá trị timestamp mập mờ (2000) như test trên, nhưng đồng hồ
        // tường đã sang 2200 — tức đã QUA ranh giới 2000, nến MỚI (open-
        // time=2000) đang thực sự chạy. Đây chính là tick ĐẦU TIÊN của nến
        // mới đọc theo open-time thật — phải append, không phải merge.
        final series = [
          KLineEntity.fromCustom(time: 1000, open: 100, high: 101, low: 99, close: 100, vol: 5),
        ];
        final result = mergeKlineBar(
          series,
          _kline(closeTimeMs: 2000, open: 200, high: 205, low: 195, close: 202, volume: 3),
          intervalMs: 1000,
          now: DateTime.fromMillisecondsSinceEpoch(2200, isUtc: true),
        );
        expect(result.length, 2); // nến mới có slot RIÊNG, không bị gộp mất
        expect(result.first.time, 1000); // nến cũ giữ nguyên, không bị sửa
        expect(result.first.close, 100);
        expect(result.last.time, 2000); // nến mới đúng open-time của nó
      },
    );

    test('không sửa in-place — series gốc không đổi', () {
      final series = [
        KLineEntity.fromCustom(time: 1000, open: 100, high: 101, low: 99, close: 100, vol: 5),
      ];
      final result = mergeKlineBar(
        series,
        _kline(closeTimeMs: 1000, open: 100, high: 101, low: 99, close: 105, volume: 6),
        intervalMs: 1000,
      );
      expect(identical(result, series), isFalse);
      expect(series.single.close, 100); // list gốc không bị mutate
    });
  });
}
