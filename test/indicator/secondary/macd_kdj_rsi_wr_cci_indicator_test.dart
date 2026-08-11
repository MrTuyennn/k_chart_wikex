import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('MACDIndicator', () {
    test('DIF/DEA/MACD khớp oracle transcribe độc lập (EMA seed = SMA, không seed = close[0])', () {
      final data = buildKLines(80);
      MACDIndicator().calc(data); // calcParams mặc định [12, 26, 9]
      final oracle = _macdOracle(data, 12, 26, 9);
      for (int i = 0; i < data.length; i++) {
        expect(data[i].dif, oracle.dif[i] == null ? isNull : closeTo(oracle.dif[i]!, 1e-6), reason: 'i=$i dif');
        expect(data[i].dea, oracle.dea[i] == null ? isNull : closeTo(oracle.dea[i]!, 1e-6), reason: 'i=$i dea');
        expect(data[i].macd, oracle.macd[i] == null ? isNull : closeTo(oracle.macd[i]!, 1e-6), reason: 'i=$i macd');
      }
    });

    test('macd = (dif - dea) * 2 luôn đúng ở mọi điểm có giá trị', () {
      final data = buildKLines(60);
      MACDIndicator().calc(data);
      for (final e in data) {
        if (e.macd == null) continue;
        expect(e.macd, closeTo((e.dif! - e.dea!) * 2, 1e-9));
      }
    });

    test('dataList rỗng không crash', () {
      expect(() => MACDIndicator().calc(<KLineEntity>[]), returnsNormally);
    });
  });

  group('KDJIndicator', () {
    test('nến đầu tiên luôn chốt K=D=J=50 (seed cố định trong calc())', () {
      final data = buildKLines(40);
      KDJIndicator().calc(data);
      expect(data[0].k, 50.0);
      expect(data[0].d, 50.0);
      expect(data[0].j, 50.0);
    });

    test('J = 3K - 2D tại mọi điểm', () {
      final data = buildKLines(60);
      KDJIndicator().calc(data);
      for (final e in data) {
        expect(e.j, closeTo(3 * e.k! - 2 * e.d!, 1e-9));
      }
    });

    test('oracle transcribe độc lập (RSV cửa sổ 9 nến, K/D smoothing 1/3-2/3) khớp toàn bộ chuỗi', () {
      final data = buildKLines(60);
      KDJIndicator().calc(data);
      final oracle = _kdjOracle(data);
      for (int i = 0; i < data.length; i++) {
        expect(data[i].k, closeTo(oracle.$1[i], 1e-9), reason: 'i=$i k');
        expect(data[i].d, closeTo(oracle.$2[i], 1e-9), reason: 'i=$i d');
      }
    });
  });

  group('RSIIndicator', () {
    test('chuỗi tăng liên tục tuyệt đối -> RSI = 100 chính xác từ nến 14 trở đi', () {
      final closes = List.generate(30, (i) => 100.0 + i); // luôn tăng, avgLoss luôn = 0
      final data = buildKLinesFromCloses(closes);
      RSIIndicator().calc(data);
      for (int i = 0; i < 13; i++) {
        expect(data[i].rsi, isNull, reason: 'i=$i warm-up');
      }
      for (int i = 13; i < data.length; i++) {
        expect(data[i].rsi, closeTo(100, 1e-9), reason: 'i=$i');
      }
    });

    test('chuỗi giảm liên tục tuyệt đối -> RSI = 0 chính xác từ nến 14 trở đi', () {
      final closes = List.generate(30, (i) => 200.0 - i); // luôn giảm, avgGain luôn = 0
      final data = buildKLinesFromCloses(closes);
      RSIIndicator().calc(data);
      for (int i = 13; i < data.length; i++) {
        expect(data[i].rsi, closeTo(0, 1e-9), reason: 'i=$i');
      }
    });

    test('RSI luôn nằm trong [0, 100] trên dữ liệu tổng hợp', () {
      final data = buildKLines(60);
      RSIIndicator().calc(data);
      for (final e in data) {
        if (e.rsi == null) continue;
        expect(e.rsi!, inInclusiveRange(0, 100));
      }
    });

    test('calcParams mặc định [6,12,24] khai báo nhưng KHÔNG dùng trong calc() — luôn hard-code 14', () {
      // RSIIndicator không cho constructor tự truyền calcParams (period 14 bị
      // hard-code trong calc(), không đọc từ calcParams) — xem indicator.md §2 RSI.
      expect(RSIIndicator().calcParams, const [6, 12, 24]);
    });
  });

  group('WRIndicator', () {
    test('sentinel -10 khi i < 13, sau đó luôn trong [-100, 0]', () {
      final data = buildKLines(50);
      WRIndicator().calc(data);
      for (int i = 0; i < 13; i++) {
        expect(data[i].r, -10.0, reason: 'i=$i');
      }
      for (int i = 13; i < data.length; i++) {
        if (data[i].r == null) continue; // NaN-guard branch (max==min)
        expect(data[i].r!, inInclusiveRange(-100, 0), reason: 'i=$i');
      }
    });

    test('oracle transcribe độc lập (cửa sổ [max(0,i-14), i]) khớp toàn bộ chuỗi', () {
      final data = buildKLines(50);
      WRIndicator().calc(data);
      for (int i = 13; i < data.length; i++) {
        final start = max(0, i - 14);
        final window = data.sublist(start, i + 1);
        final max14 = window.map((e) => e.high).reduce(max);
        final min14 = window.map((e) => e.low).reduce(min);
        final expected = -100 * (max14 - data[i].close) / (max14 - min14);
        expect(data[i].r, closeTo(expected, 1e-9), reason: 'i=$i');
      }
    });
  });

  group('CCIIndicator', () {
    test('oracle transcribe độc lập (naive O(n*period), TP=(H+L+C)/3) khớp toàn bộ chuỗi', () {
      final data = buildKLines(60);
      const periods = 20;
      CCIIndicator().calc(data); // calcParams mặc định [20]

      for (int i = 0; i < data.length; i++) {
        if (i < periods - 1) {
          expect(data[i].cci, isNull, reason: 'i=$i warm-up');
          continue;
        }
        final window = data.sublist(i - periods + 1, i + 1);
        final tps = window.map((e) => (e.high + e.low + e.close) / 3).toList();
        final tp = tps.last;
        final maTp = tps.reduce((a, b) => a + b) / periods;
        final md = tps.map((v) => (v - maTp).abs()).reduce((a, b) => a + b) / periods;
        final expected = md != 0 ? (tp - maTp) / md / 0.015 : 0.0;
        expect(data[i].cci, closeTo(expected, 1e-6), reason: 'i=$i');
      }
    });

    test('dataList rỗng không crash', () {
      expect(() => CCIIndicator().calc(<KLineEntity>[]), returnsNormally);
    });
  });
}

/// Transcribe độc lập MACD (EMA short/long seed bằng SMA, DEA seed bằng SMA
/// của DIF) từ mô tả `indicator.md` §2 MACD — dùng làm oracle cross-check.
({List<double?> dif, List<double?> dea, List<double?> macd}) _macdOracle(
  List<KLineEntity> data,
  int shortP,
  int longP,
  int signalP,
) {
  final n = data.length;
  final dif = List<double?>.filled(n, null);
  final dea = List<double?>.filled(n, null);
  final macd = List<double?>.filled(n, null);
  double closeSum = 0;
  double emaShort = 0;
  double emaLong = 0;
  double difV = 0;
  double difSum = 0;
  double deaV = 0;
  final maxP = max(shortP, longP);

  for (int i = 0; i < n; i++) {
    final close = data[i].close;
    closeSum += close;
    if (i >= shortP - 1) {
      emaShort = i > shortP - 1 ? (2 * close + (shortP - 1) * emaShort) / (shortP + 1) : closeSum / shortP;
    }
    if (i >= longP - 1) {
      emaLong = i > longP - 1 ? (2 * close + (longP - 1) * emaLong) / (longP + 1) : closeSum / longP;
    }
    if (i >= maxP - 1) {
      difV = emaShort - emaLong;
      dif[i] = difV;
      difSum += difV;
      if (i >= maxP + signalP - 2) {
        deaV = i > maxP + signalP - 2 ? (difV * 2 + deaV * (signalP - 1)) / (signalP + 1) : difSum / signalP;
        macd[i] = (difV - deaV) * 2;
        dea[i] = deaV;
      }
    }
  }
  return (dif: dif, dea: dea, macd: macd);
}

/// Transcribe độc lập KDJ (RSV cửa sổ tối đa 9 nến, K/D smoothing 1/3-2/3,
/// seed 50) từ mô tả `indicator.md` §2 KDJ — dùng làm oracle cross-check.
(List<double>, List<double>, List<double>) _kdjOracle(List<KLineEntity> data) {
  final n = data.length;
  final k = List<double>.filled(n, 0);
  final d = List<double>.filled(n, 0);
  final j = List<double>.filled(n, 0);
  double preK = 50, preD = 50;
  k[0] = 50;
  d[0] = 50;
  j[0] = 50;
  for (int i = 1; i < n; i++) {
    final start = max(0, i - 8);
    var low = data[i].low;
    var high = data[i].high;
    for (int idx = start; idx < i; idx++) {
      if (data[idx].low < low) low = data[idx].low;
      if (data[idx].high > high) high = data[idx].high;
    }
    var rsv = (data[i].close - low) * 100.0 / (high - low);
    if (rsv.isNaN) rsv = 0;
    final kv = (2 * preK + rsv) / 3.0;
    final dv = (2 * preD + kv) / 3.0;
    k[i] = kv;
    d[i] = dv;
    j[i] = 3 * kv - 2 * dv;
    preK = kv;
    preD = dv;
  }
  return (k, d, j);
}
