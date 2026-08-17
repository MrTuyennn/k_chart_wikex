import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';

import '../test_data.dart';

void main() {
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

/// Transcribe độc lập StochRSI (RSI Wilder nội bộ -> Stoch trên chuỗi RSI ->
/// SMA %K -> SMA %D) từ mô tả `indicator.md` §2 StochRSI — dùng làm oracle.
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
