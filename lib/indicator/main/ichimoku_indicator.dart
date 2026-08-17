part of '../indicator_template.dart';

class Ichimoku {
  double? tenkan;
  double? kijun;

  /// Giá trị TẠI index gốc (không dịch) — `IchimokuIndicator.drawChart` tự
  /// dịch tới trước `shift` nến khi vẽ (xem `IchimokuIndicator.shift`).
  double? spanA;
  double? spanB;
}

class IchimokuIndicator extends MainIndicator<CandleEntity, IchimokuStyle> {
  late final Paint _linePaint;
  late final Paint _fillPaint;

  /// Khoảng cách tâm 2 nến (logical px) — dùng để quy đổi `shift` (số nến)
  /// sang px khi dịch Span A/B/Chikou. Mặc định khớp hằng số cố định
  /// `KChartStyle.pointWidth` (11.0) — `KChartStyle` là `final class` nên
  /// giá trị này được đảm bảo không đổi ở mọi instance, không thể subclass
  /// để ghi đè, tránh 2 hằng số lệch nhau âm thầm.
  final double pointWidth;

  IchimokuIndicator({
    super.calcParams = const [9, 26, 52],
    IchimokuStyle? indicatorStyle,
    this.pointWidth = 11.0,
  }) : super(
         name: 'ichimokuKinkoHyo',
         shortName: 'ICHIMOKU',
         indicatorStyle: indicatorStyle ?? const IchimokuStyle(),
         isDefaultStyle: indicatorStyle == null,
       ) {
    _linePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = this.indicatorStyle.lineWidth;
    _fillPaint = Paint()..style = PaintingStyle.fill;
  }

  /// Shift luôn bằng Kijun period — KHÔNG hardcode, đổi `calcParams[1]` thì
  /// shift đổi theo (xem mục Ichimoku ở `indicator.md`, root repo).
  int get shift => calcParams[1];

  /// Báo cho painter chừa `shift` slot tương lai bên phải nến cuối để mây
  /// (Span A/B dịch tới trước) không bị cắt cụt.
  @override
  int get futureShift => shift;

  @override
  (double, double) getMaxMinValue(
    KLineEntity entity,
    double minV,
    double maxV,
  ) {
    final v = entity.ichimoku;
    if (v == null) return (minV, maxV);
    double minValue = minV;
    double maxValue = maxV;
    for (final val in [v.tenkan, v.kijun, v.spanA, v.spanB]) {
      if (val == null) continue;
      minValue = min(minValue, val);
      maxValue = max(maxValue, val);
    }
    return (minValue, maxValue);
  }

  @override
  TextSpan? drawFigure(
    CandleEntity entity,
    int precision,
    KChartColors chartColors,
  ) {
    final v = entity.ichimoku;
    if (v == null) return null;
    return TextSpan(
      children: [
        if (v.tenkan != null)
          TextSpan(
            text: "Tenkan:${formatNumber(v.tenkan!, precision)}  ",
            style: getTextStyle(
              indicatorStyle.tenkanColor,
              base: indicatorStyle.textStyle,
              forceColor: true,
            ),
          ),
        if (v.kijun != null)
          TextSpan(
            text: "Kijun:${formatNumber(v.kijun!, precision)}  ",
            style: getTextStyle(
              indicatorStyle.kijunColor,
              base: indicatorStyle.textStyle,
              forceColor: true,
            ),
          ),
        if (v.spanA != null)
          TextSpan(
            text: "SpanA:${formatNumber(v.spanA!, precision)}  ",
            style: getTextStyle(
              indicatorStyle.spanAColor,
              base: indicatorStyle.textStyle,
              forceColor: true,
            ),
          ),
        if (v.spanB != null)
          TextSpan(
            text: "SpanB:${formatNumber(v.spanB!, precision)}",
            style: getTextStyle(
              indicatorStyle.spanBColor,
              base: indicatorStyle.textStyle,
              forceColor: true,
            ),
          ),
      ],
    );
  }

  @override
  void drawChart(
    CandleEntity lastPoint,
    CandleEntity curPoint,
    double lastX,
    double curX,
    GetYFunction getY,
    Canvas canvas,
    KChartColors chartColors,
  ) {
    final last = lastPoint.ichimoku;
    final cur = curPoint.ichimoku;
    if (last == null || cur == null) return;

    final shiftPx = shift * pointWidth;

    if (last.tenkan != null && cur.tenkan != null) {
      canvas.drawLine(
        Offset(lastX, getY(last.tenkan!)),
        Offset(curX, getY(cur.tenkan!)),
        _linePaint..color = indicatorStyle.tenkanColor,
      );
    }

    if (last.kijun != null && cur.kijun != null) {
      canvas.drawLine(
        Offset(lastX, getY(last.kijun!)),
        Offset(curX, getY(cur.kijun!)),
        _linePaint..color = indicatorStyle.kijunColor,
      );
    }

    // Chikou = close, dịch LÙI `shift` nến — luôn có giá trị, không cần
    // warm-up riêng (tự bị cắt cụt ở mép phải vì không có nến i>n-1).
    canvas.drawLine(
      Offset(lastX - shiftPx, getY(lastPoint.close)),
      Offset(curX - shiftPx, getY(curPoint.close)),
      _linePaint..color = indicatorStyle.chikouColor,
    );

    final hasCloud =
        last.spanA != null &&
        last.spanB != null &&
        cur.spanA != null &&
        cur.spanB != null;
    if (!hasCloud) return;

    // Span A/B dịch TỚI TRƯỚC `shift` nến.
    final lastCx = lastX + shiftPx;
    final curCx = curX + shiftPx;
    final lastAY = getY(last.spanA!);
    final curAY = getY(cur.spanA!);
    final lastBY = getY(last.spanB!);
    final curBY = getY(cur.spanB!);

    canvas.drawLine(
      Offset(lastCx, lastAY),
      Offset(curCx, curAY),
      _linePaint..color = indicatorStyle.spanAColor,
    );
    canvas.drawLine(
      Offset(lastCx, lastBY),
      Offset(curCx, curBY),
      _linePaint..color = indicatorStyle.spanBColor,
    );

    _drawCloud(
      canvas,
      lastCx,
      curCx,
      lastAY,
      curAY,
      lastBY,
      curBY,
      last.spanA! - last.spanB!,
      cur.spanA! - cur.spanB!,
    );
  }

  /// Tô mây giữa Span A/B — tách polygon tại điểm giao (nội suy tuyến tính)
  /// để đổi màu đúng giữa đoạn tăng/giảm, không tô sai màu cả đoạn khi 2
  /// đường cắt nhau giữa `lastX`..`curX` (xem mục Ichimoku ở `indicator.md`,
  /// root repo).
  void _drawCloud(
    Canvas canvas,
    double lastX,
    double curX,
    double lastAY,
    double curAY,
    double lastBY,
    double curBY,
    double lastDiff,
    double curDiff,
  ) {
    final crosses =
        (lastDiff > 0 && curDiff < 0) || (lastDiff < 0 && curDiff > 0);
    if (!crosses) {
      final color = (lastDiff + curDiff) >= 0
          ? indicatorStyle.cloudUpColor
          : indicatorStyle.cloudDownColor;
      _fillQuad(canvas, lastX, curX, lastAY, curAY, lastBY, curBY, color);
      return;
    }

    final t = lastDiff / (lastDiff - curDiff);
    final crossX = lastX + t * (curX - lastX);
    final crossY = lastAY + t * (curAY - lastAY);

    _fillQuad(
      canvas,
      lastX,
      crossX,
      lastAY,
      crossY,
      lastBY,
      crossY,
      lastDiff >= 0 ? indicatorStyle.cloudUpColor : indicatorStyle.cloudDownColor,
    );
    _fillQuad(
      canvas,
      crossX,
      curX,
      crossY,
      curAY,
      crossY,
      curBY,
      curDiff >= 0 ? indicatorStyle.cloudUpColor : indicatorStyle.cloudDownColor,
    );
  }

  void _fillQuad(
    Canvas canvas,
    double x1,
    double x2,
    double aY1,
    double aY2,
    double bY1,
    double bY2,
    Color color,
  ) {
    final path = Path()
      ..moveTo(x1, aY1)
      ..lineTo(x2, aY2)
      ..lineTo(x2, bY2)
      ..lineTo(x1, bY1)
      ..close();
    canvas.drawPath(path, _fillPaint..color = color);
  }

  @override
  void calc(List<KLineEntity> dataList) {
    final n = dataList.length;
    final tenkanP = calcParams[0];
    final kijunP = calcParams[1];
    final spanBP = calcParams[2];

    final highs = List<double>.generate(n, (i) => dataList[i].high);
    final lows = List<double>.generate(n, (i) => dataList[i].low);

    final tenkanMax = _slidingMax(highs, tenkanP);
    final tenkanMin = _slidingMin(lows, tenkanP);
    final kijunMax = _slidingMax(highs, kijunP);
    final kijunMin = _slidingMin(lows, kijunP);
    final spanBMax = _slidingMax(highs, spanBP);
    final spanBMin = _slidingMin(lows, spanBP);

    for (int i = 0; i < n; i++) {
      final v = Ichimoku();
      final tenkan = (tenkanMax[i] != null && tenkanMin[i] != null)
          ? (tenkanMax[i]! + tenkanMin[i]!) / 2
          : null;
      final kijun = (kijunMax[i] != null && kijunMin[i] != null)
          ? (kijunMax[i]! + kijunMin[i]!) / 2
          : null;
      v.tenkan = tenkan;
      v.kijun = kijun;
      v.spanA = (tenkan != null && kijun != null) ? (tenkan + kijun) / 2 : null;
      v.spanB = (spanBMax[i] != null && spanBMin[i] != null)
          ? (spanBMax[i]! + spanBMin[i]!) / 2
          : null;
      dataList[i].ichimoku = v;
    }
  }

  /// Sliding-window max, O(n) qua monotonic deque (giảm dần) — tránh
  /// O(n×period) của vòng lặp naive (xem mục Ichimoku ở `indicator.md`,
  /// root repo). `null` cho tới khi đủ `period` phần tử (warm-up).
  static List<double?> _slidingMax(List<double> values, int period) {
    final n = values.length;
    final out = List<double?>.filled(n, null);
    final deque = Queue<int>(); // index, values[deque] giảm dần
    for (int i = 0; i < n; i++) {
      while (deque.isNotEmpty && values[deque.last] <= values[i]) {
        deque.removeLast();
      }
      deque.addLast(i);
      if (deque.first <= i - period) deque.removeFirst();
      if (i >= period - 1) out[i] = values[deque.first];
    }
    return out;
  }

  /// Sliding-window min, O(n) — đối xứng với [_slidingMax].
  static List<double?> _slidingMin(List<double> values, int period) {
    final n = values.length;
    final out = List<double?>.filled(n, null);
    final deque = Queue<int>(); // index, values[deque] tăng dần
    for (int i = 0; i < n; i++) {
      while (deque.isNotEmpty && values[deque.last] >= values[i]) {
        deque.removeLast();
      }
      deque.addLast(i);
      if (deque.first <= i - period) deque.removeFirst();
      if (i >= period - 1) out[i] = values[deque.first];
    }
    return out;
  }
}
