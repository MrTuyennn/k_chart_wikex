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
