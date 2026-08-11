import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
  group('OBVIndicator', () {
    test('hand-trace 5 nến: obv tích lũy theo dấu close, signal = SMA5', () {
      final closes = [10.0, 12.0, 11.0, 11.0, 15.0];
      final vols = [100.0, 200.0, 150.0, 50.0, 300.0];
      final data = buildKLinesFromCloses(closes, vols: vols);
      OBVIndicator().calc(data); // calcParams mặc định [5]

      expect(data[0].obv, 100.0);
      expect(data[1].obv, 300.0); // 12 > 10 -> +200
      expect(data[2].obv, 150.0); // 11 < 12 -> -150
      expect(data[3].obv, 150.0); // 11 == 11 -> giữ nguyên
      expect(data[4].obv, 450.0); // 15 > 11 -> +300

      expect(data[0].obvSignal, isNull);
      expect(data[3].obvSignal, isNull);
      expect(data[4].obvSignal, closeTo((100 + 300 + 150 + 150 + 450) / 5, 1e-9));
    });

    test('oracle transcribe độc lập khớp toàn bộ chuỗi tổng hợp', () {
      final data = buildKLines(60);
      const period = 5;
      OBVIndicator().calc(data);

      double obv = data[0].vol;
      final obvList = [obv];
      for (int i = 1; i < data.length; i++) {
        if (data[i].close > data[i - 1].close) {
          obv += data[i].vol;
        } else if (data[i].close < data[i - 1].close) {
          obv -= data[i].vol;
        }
        obvList.add(obv);
      }
      for (int i = 0; i < data.length; i++) {
        expect(data[i].obv, closeTo(obvList[i], 1e-9), reason: 'i=$i obv');
        if (i >= period - 1) {
          final window = obvList.sublist(i - period + 1, i + 1);
          final expectedSignal = window.reduce((a, b) => a + b) / period;
          expect(data[i].obvSignal, closeTo(expectedSignal, 1e-9), reason: 'i=$i signal');
        } else {
          expect(data[i].obvSignal, isNull, reason: 'i=$i signal warm-up');
        }
      }
    });
  });

  group('TRIXIndicator', () {
    test('trix[0] luôn null (chưa có prevEma3), trixMa null cho tới khi đủ m trix', () {
      final data = buildKLines(60);
      TRIXIndicator().calc(data); // calcParams mặc định [12, 20]
      expect(data[0].trix, isNull);
      for (int i = 0; i < 20; i++) {
        expect(data[i].trixMa, isNull, reason: 'i=$i chưa đủ 20 giá trị trix (trix có từ i=1)');
      }
      expect(data[20].trixMa, isNotNull);
    });

    test('oracle transcribe độc lập (EMA×3 nối tiếp, seed=close[0]) khớp toàn bộ chuỗi', () {
      final data = buildKLines(60);
      const n = 12, m = 20;
      TRIXIndicator().calc(data);

      final multiplier = 2 / (n + 1);
      double ema1 = 0, ema2 = 0, ema3 = 0;
      double? prevEma3;
      final trixList = <double?>[];
      for (int i = 0; i < data.length; i++) {
        final close = data[i].close;
        if (i == 0) {
          ema1 = close;
          ema2 = ema1;
          ema3 = ema2;
        } else {
          ema1 = (close - ema1) * multiplier + ema1;
          ema2 = (ema1 - ema2) * multiplier + ema2;
          ema3 = (ema2 - ema3) * multiplier + ema3;
        }
        double? trix;
        if (prevEma3 != null && prevEma3 != 0) {
          trix = (ema3 - prevEma3) / prevEma3 * 100;
        }
        prevEma3 = ema3;
        trixList.add(trix);
        expect(data[i].trix, trix == null ? isNull : closeTo(trix, 1e-6), reason: 'i=$i trix');
      }
      for (int i = 0; i < data.length; i++) {
        final window = trixList.sublist((i - m + 1).clamp(0, i + 1), i + 1);
        if (window.length == m && window.every((v) => v != null)) {
          final expected = window.cast<double>().reduce((a, b) => a + b) / m;
          expect(data[i].trixMa, closeTo(expected, 1e-6), reason: 'i=$i trixMa');
        }
      }
    });
  });

  group('MTMIndicator', () {
    test('hand-trace: dãy cấp số cộng bước 1, calcParams mặc định [12,6] -> MTM luôn = 12', () {
      // MTMIndicator không cho constructor tự truyền calcParams (hard-code [12, 6]).
      final closes = List.generate(30, (i) => (i + 1).toDouble()); // 1..30
      final data = buildKLinesFromCloses(closes);
      MTMIndicator().calc(data);
      for (int i = 0; i < 12; i++) {
        expect(data[i].mtm, isNull, reason: 'i=$i warm-up');
      }
      for (int i = 12; i < data.length; i++) {
        expect(data[i].mtm, closeTo(12.0, 1e-9), reason: 'i=$i');
      }
      // mtmMa cần đủ m=6 giá trị mtm liên tiếp -> có từ i = n + m - 1 = 17
      expect(data[16].mtmMa, isNull);
      expect(data[17].mtmMa, closeTo(12.0, 1e-9));
    });

    test('oracle công thức trực tiếp MTM = close - close[i-n], MTMMA = MA(MTM,m)', () {
      final data = buildKLines(60);
      const n = 12, m = 6;
      MTMIndicator().calc(data); // calcParams mặc định [12, 6]

      final mtmList = List<double?>.filled(data.length, null);
      for (int i = 0; i < data.length; i++) {
        if (i < n) {
          expect(data[i].mtm, isNull, reason: 'i=$i');
          continue;
        }
        final expected = data[i].close - data[i - n].close;
        mtmList[i] = expected;
        expect(data[i].mtm, closeTo(expected, 1e-9), reason: 'i=$i');
      }
      for (int i = n + m - 1; i < data.length; i++) {
        final window = mtmList.sublist(i - m + 1, i + 1).cast<double>();
        final expected = window.reduce((a, b) => a + b) / m;
        expect(data[i].mtmMa, closeTo(expected, 1e-6), reason: 'i=$i');
      }
    });
  });

  group('StochRSIIndicator', () {
    test('referenceValues = [20, 80] (mốc quá mua/quá bán vẽ nét đứt)', () {
      expect(StochRSIIndicator().referenceValues, const [20.0, 80.0]);
    });

    test('%K/%D luôn nằm trong [0, 100] khi có giá trị', () {
      final data = buildKLines(80);
      StochRSIIndicator().calc(data); // calcParams mặc định [14, 14, 3, 3]
      const eps = 1e-9; // dung sai làm tròn dấu phẩy động quanh biên 0/100
      for (final e in data) {
        if (e.stochRsiK != null) expect(e.stochRsiK!, inInclusiveRange(0 - eps, 100 + eps));
        if (e.stochRsiD != null) expect(e.stochRsiD!, inInclusiveRange(0 - eps, 100 + eps));
      }
    });

    test('oracle transcribe độc lập (RSI Wilder nội bộ -> Stoch -> SMA %K -> SMA %D) khớp toàn bộ chuỗi', () {
      final data = buildKLines(80);
      const n1 = 14, n2 = 14, m1 = 3, m2 = 3;
      StochRSIIndicator().calc(data);

      final oracle = _stochRsiOracle(data, n1, n2, m1, m2);
      for (int i = 0; i < data.length; i++) {
        expect(data[i].stochRsiK, oracle.$1[i] == null ? isNull : closeTo(oracle.$1[i]!, 1e-6), reason: 'i=$i k');
        expect(data[i].stochRsiD, oracle.$2[i] == null ? isNull : closeTo(oracle.$2[i]!, 1e-6), reason: 'i=$i d');
      }
    });
  });
}

(List<double?>, List<double?>) _stochRsiOracle(List<KLineEntity> data, int n1, int n2, int m1, int m2) {
  final n = data.length;
  final kOut = List<double?>.filled(n, null);
  final dOut = List<double?>.filled(n, null);

  double avgGain = 0, avgLoss = 0;
  final rsiWindow = <double>[];
  final kWindow = <double>[];
  double kSum = 0;
  final dWindow = <double>[];
  double dSum = 0;

  for (int i = 0; i < n; i++) {
    double? rsi;
    if (i > 0) {
      final change = data[i].close - data[i - 1].close;
      final gain = change > 0 ? change : 0.0;
      final loss = change < 0 ? -change : 0.0;
      if (i <= n1) {
        avgGain += gain / n1;
        avgLoss += loss / n1;
      } else {
        avgGain = (avgGain * (n1 - 1) + gain) / n1;
        avgLoss = (avgLoss * (n1 - 1) + loss) / n1;
      }
      if (i >= n1) {
        if (avgGain == 0 && avgLoss == 0) {
          rsi = 50;
        } else {
          rsi = avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss);
        }
      }
    }

    double? k;
    if (rsi != null) {
      rsiWindow.add(rsi);
      if (rsiWindow.length > n2) rsiWindow.removeAt(0);
      if (rsiWindow.length == n2) {
        final minRsi = rsiWindow.reduce((a, b) => a < b ? a : b);
        final maxRsi = rsiWindow.reduce((a, b) => a > b ? a : b);
        final range = maxRsi - minRsi;
        final stoch = range == 0 ? 0.0 : (rsi - minRsi) / range * 100;
        kWindow.add(stoch);
        kSum += stoch;
        if (kWindow.length > m1) kSum -= kWindow.removeAt(0);
        if (kWindow.length == m1) k = kSum / m1;
      }
    }

    double? d;
    if (k != null) {
      dWindow.add(k);
      dSum += k;
      if (dWindow.length > m2) dSum -= dWindow.removeAt(0);
      if (dWindow.length == m2) d = dSum / m2;
    }

    kOut[i] = k;
    dOut[i] = d;
  }
  return (kOut, dOut);
}
