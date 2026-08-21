import 'package:flutter/material.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';
import '../entity/candle_entity.dart';
import '../utils/number_util.dart';
import '../utils/price_ticks.dart';
import 'base_chart_renderer.dart';

enum VerticalTextAlignment { left, right }

//For TrendLine
double? trendLineMax;
double? trendLineScale;
double? trendLineContentRec;

class MainRenderer extends BaseChartRenderer<CandleEntity> {
  late double mCandleWidth;
  late double mCandleLineWidth;
  List<MainIndicator> indicatorLi;
  bool isLine;

  //绘制的内容区域
  late Rect _contentRect;
  final double _contentPadding = 5.0;
  final KChartStyle chartStyle;
  final KChartColors chartColors;
  final double mLineStrokeWidth = 1.0;
  double scaleX;
  late Paint mLinePaint;
  /// Vẽ VIỀN thân nến rỗng (`CandleBodyStyle` khác `solid`) — Paint RIÊNG,
  /// luôn giữ `PaintingStyle.stroke`, chỉ mutate `.color` mỗi nến. Trước đây
  /// dùng chung `chartPaint` (mặc định fill, dùng cho mọi draw khác của
  /// renderer này) rồi toggle style/strokeWidth sang stroke + reset lại sau
  /// mỗi nến rỗng — tốn thêm 2 lần mutate Paint state/nến so với dùng Paint
  /// riêng, không cần thiết.
  ///
  /// LAZY (nullable, không tạo trong constructor) — `MainRenderer` được
  /// dựng lại MỖI FRAME (`ChartPainter.initChartRenderer`), nên tạo `Paint()`
  /// vô điều kiện ở đây tốn 1 allocation/frame kể cả khi `bodyStyle` đang là
  /// `solid` (mặc định — style hollow không hề dùng paint này). Chỉ cấp phát
  /// lần đầu thực sự vẽ 1 nến hollow.
  Paint? _hollowBorderPaint;

  /// Path tái dùng cho 2 đoạn râu nhô ra ngoài thân khi nến hollow — gộp
  /// thành 1 `canvas.drawPath` thay vì 2 `canvas.drawRect` riêng (giảm số
  /// draw call/nến từ 3 xuống 2, ngang bằng nến solid — chi phí vượt biên
  /// sang canvas/Skia của mỗi lệnh vẽ thường đáng kể hơn hình học đơn giản
  /// như 1 rect). Field cấp 1 lần/frame, `reset()` + `addRect` lại cho từng
  /// nến hollow thay vì tạo `Path()` mới mỗi nến.
  final Path _hollowWickPath = Path();
  final VerticalTextAlignment verticalTextAlignment;
  final double mBottomPadding;
  final double externalScaleY;
  final double scaleCenterY;
  final double offsetY;
  MainRenderer(
    Rect mainRect,
    Rect priceAxisRect,
    double maxValue,
    double minValue,
    double topPadding,
    this.indicatorLi,
    this.isLine,
    int fixedLength,
    this.chartStyle,
    this.chartColors,
    this.scaleX,
    this.verticalTextAlignment,
    this.mBottomPadding,
    this.externalScaleY,
    this.scaleCenterY,
    this.offsetY,
  ) : super(
        chartRect: mainRect,
        priceAxisRect: priceAxisRect,
        maxValue: maxValue,
        minValue: minValue,
        topPadding: topPadding,
        fixedLength: fixedLength,
        gridColor: chartColors.gridColor,
      ) {
    mCandleWidth = chartStyle.candleWidth;
    mCandleLineWidth = chartStyle.candleLineWidth;
    mLinePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = mLineStrokeWidth
      ..color = chartColors.candleStyle.kLineColor;
    _contentRect = Rect.fromLTRB(
      chartRect.left,
      chartRect.top + _contentPadding,
      chartRect.right,
      chartRect.bottom - _contentPadding,
    );
    if (maxValue == minValue) {
      maxValue *= 1.5;
      minValue /= 2;
    }
    scaleY = _contentRect.height / (this.maxValue - this.minValue);

    // Range giá THỰC SỰ đang hiển thị sau gesture zoom/pan dọc (externalScaleY/
    // offsetY) — KHÔNG dùng thẳng minValue/maxValue gốc (auto-scale theo data),
    // nếu không khi user kéo dọc thu nhỏ, tick cũ (tính từ range gốc, rộng hơn)
    // dạt gần hết ra ngoài view, chỉ còn 1-2 label lọt lại. Tick "ảo" (nice-
    // number, không nhất thiết trùng giá nến thật) tính lại theo range đang
    // thấy thì luôn lấp đầy trục dù zoom tới đâu.
    final double effectiveMaxPrice = _priceAtScreenY(chartRect.top);
    final double effectiveMinPrice = _priceAtScreenY(chartRect.bottom);

    // Nice-number price ticks (CHART_AXES.md §6.3) — thay cho việc chia đều
    // pixel rồi suy ngược ra giá trị (label không tròn số). Renderer này được
    // tạo mới mỗi frame (`ChartPainter.initChartRenderer`) nên tự nhiên thoả
    // yêu cầu "Y rebuilt every frame" của spec, không cần cache riêng.
    _priceTicks = priceTicks(
      minPrice: effectiveMinPrice < effectiveMaxPrice
          ? effectiveMinPrice
          : effectiveMaxPrice,
      maxPrice: effectiveMinPrice < effectiveMaxPrice
          ? effectiveMaxPrice
          : effectiveMinPrice,
      height: _contentRect.height,
      targetTicks: _kTargetPriceTicks,
    );
  }

  /// Giá tại 1 toạ độ Y màn hình — nghịch đảo của [_priceToScreenY] (không
  /// kẹp, vì cần giá trị TẠI đúng biên `chartRect.top`/`bottom`, không phải
  /// giá trị đã bị kẹp vào trong panel). Công thức đảo NGUYÊN VẸN transform
  /// canvas thật `ChartPainter.drawChart` áp cho nến (`translate(0,
  /// centerY*(1-scaleY)+offsetY); scale(1.0, scaleY)`, neo tại `scaleCenterY`)
  /// — tick tính ra luôn khớp đúng vị trí nến đang hiển thị, không lệch.
  double _priceAtScreenY(double yScreen) {
    final double safeExternalScaleY = externalScaleY.abs() < 1e-9
        ? 1e-9
        : externalScaleY;
    final double yContent =
        scaleCenterY + (yScreen - offsetY - scaleCenterY) / safeExternalScaleY;
    // Nghịch đảo ĐÚNG của getY() (dùng _contentRect.top, KHÔNG phải
    // chartRect.top — lệch _contentPadding=5px nếu dùng nhầm, xem getY()).
    return maxValue - (yContent - _contentRect.top) / scaleY;
  }

  static const int _kTargetPriceTicks = 6;
  late final List<double> _priceTicks;

  /// Cache `TextPainter` đã `layout()` theo `(string, style)` — dùng chung
  /// TOÀN PROCESS an toàn (khác `PriceAxisWidthCache`/`TimeTickPlanner`: đây
  /// là hàm THUẦN của input, không mang state riêng của 1 chart nào — cùng
  /// chuỗi + cùng style ở bất kỳ chart nào cũng ra đúng 1 kết quả). Đúng
  /// khuyến nghị "Cache laid-out text by (string, colour, size, weight)" ở
  /// CHART_AXES.md §8 Performance checklist — trước đây `measureMaxLabelWidth`
  /// (gọi mỗi frame, kể cả khi chart đứng yên) và `drawVerticalText` đều tự
  /// dựng `TextPainter` mới mỗi lần, dù range giá/style không đổi giữa 2 frame.
  /// `TextPainter` không lưu vị trí (offset truyền riêng lúc `.paint()`) nên
  /// tái dùng object đã layout để vẽ ở toạ độ khác vẫn an toàn.
  static final Map<(String, TextStyle), TextPainter> _priceLabelCache = {};

  static TextPainter _cachedPriceLabel(String text, TextStyle style) {
    final key = (text, style);
    final cached = _priceLabelCache[key];
    if (cached != null) return cached;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    // Guard chống phình vô hạn — giá trị format khác nhau liên tục trong 1
    // phiên live dài (giá đổi mỗi tick) có thể tích luỹ rất nhiều key.
    if (_priceLabelCache.length > 500) _priceLabelCache.clear();
    _priceLabelCache[key] = tp;
    return tp;
  }

  /// Độ rộng label giá RỘNG NHẤT trong tick set hiện tại — input cho
  /// `BaseChartPainter.updatePriceAxisWidth()` (instance method, §7.6). Panel giá chính là
  /// nguồn quyết định chính (số thường dài/nhiều số thập phân nhất so với
  /// volume/secondary), nên strip giá đo theo panel này.
  double measureMaxLabelWidth(TextStyle textStyle) {
    if (_priceTicks.isEmpty) return 0;
    double maxWidth = 0;
    for (final price in _priceTicks) {
      final tp = _cachedPriceLabel(
        NumberUtil.formatFixed(price, fixedLength) ?? '',
        textStyle,
      );
      if (tp.width > maxWidth) maxWidth = tp.width;
    }
    return maxWidth;
  }

  /// Map 1 giá trị GIÁ sang y màn hình — chiều ngược của phép biến đổi thủ
  /// công `drawVerticalText` đang dùng để suy giá từ y (đảo canvas transform
  /// scaleY/offsetY, vì grid + label trục giá vẽ ở screen space chưa transform).
  double _priceToScreenY(double price) {
    final double yContent = getY(price);
    final double yScreen =
        scaleCenterY + (yContent - scaleCenterY) * externalScaleY + offsetY;
    return yScreen.clamp(chartRect.top, chartRect.bottom);
  }

  @override
  void drawText(Canvas canvas, CandleEntity data, double x) {
    if (isLine == true) return;
    double y = 2.0;
    for (int i = 0; i < indicatorLi.length; ++i) {
      TextSpan? span = indicatorLi[i].drawFigure(
        data,
        fixedLength,
        chartColors,
      );
      if (span == null) return;
      TextPainter tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      );
      tp.layout(minWidth: 0, maxWidth: chartRect.width - chartStyle.space);

      Offset offset = Offset(x, y);

      canvas.drawRect(
        Rect.fromLTRB(
          offset.dx - 2,
          offset.dy - 2,
          tp.width + offset.dx + 2,
          tp.height + offset.dy + 2,
        ),
        Paint()
          ..color = chartColors.bgColor
              .withValues(alpha: chartColors.bgColor.a * (80 / 255)),
      );

      tp.paint(canvas, offset);

      y = y + tp.height + 2.0; // update y
    }
  }

  @override
  void drawChart(
    CandleEntity lastPoint,
    CandleEntity curPoint,
    double lastX,
    double curX,
    Size size,
    Canvas canvas,
  ) {
    if (isLine) {
      drawPolyline(lastPoint.close, curPoint.close, canvas, lastX, curX);
    } else {
      drawCandle(curPoint, canvas, curX);

      /// draw chart main state
      for (int i = 0; i < indicatorLi.length; ++i) {
        indicatorLi[i].drawChart(
          lastPoint,
          curPoint,
          lastX,
          curX,
          getY,
          canvas,
          chartColors,
        );
      }
    }
  }

  Shader? mLineFillShader;
  Path? mLinePath, mLineFillPath;
  Paint mLineFillPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  //画折线图
  void drawPolyline(
    double lastPrice,
    double curPrice,
    Canvas canvas,
    double lastX,
    double curX,
  ) {
    mLinePath ??= Path();

    if (lastX == curX) lastX = 0; //起点位置填充
    mLinePath!.moveTo(lastX, getY(lastPrice));
    mLinePath!.cubicTo(
      (lastX + curX) / 2,
      getY(lastPrice),
      (lastX + curX) / 2,
      getY(curPrice),
      curX,
      getY(curPrice),
    );

    //画阴影
    mLineFillShader ??=
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          tileMode: TileMode.clamp,
          colors: chartColors.candleStyle.kLineFillColors,
        ).createShader(
          Rect.fromLTRB(
            chartRect.left,
            chartRect.top,
            chartRect.right,
            chartRect.bottom,
          ),
        );
    mLineFillPaint.shader = mLineFillShader;

    mLineFillPath ??= Path();

    mLineFillPath!.moveTo(lastX, chartRect.height + chartRect.top);
    mLineFillPath!.lineTo(lastX, getY(lastPrice));
    mLineFillPath!.cubicTo(
      (lastX + curX) / 2,
      getY(lastPrice),
      (lastX + curX) / 2,
      getY(curPrice),
      curX,
      getY(curPrice),
    );
    mLineFillPath!.lineTo(curX, chartRect.height + chartRect.top);
    mLineFillPath!.close();

    canvas.drawPath(mLineFillPath!, mLineFillPaint);
    mLineFillPath!.reset();

    canvas.drawPath(
      mLinePath!,
      mLinePaint..strokeWidth = (mLineStrokeWidth / scaleX).clamp(0.1, 1.0),
    );
    mLinePath!.reset();
  }

  void drawCandle(CandleEntity curPoint, Canvas canvas, double curX) {
    var high = getY(curPoint.high);
    var low = getY(curPoint.low);
    var open = getY(curPoint.open);
    var close = getY(curPoint.close);
    double r = mCandleWidth / 2;
    double lineR = mCandleLineWidth / 2;
    if (open >= close) {
      // 实体高度>= CandleLineWidth
      if (open - close < mCandleLineWidth) {
        open = close + mCandleLineWidth;
      }
      _drawCandleBody(
        canvas,
        color: chartColors.candleStyle.upColor,
        hollow: chartColors.candleStyle.bodyStyle.isHollow(rising: true),
        bodyRect: Rect.fromLTRB(curX - r, close, curX + r, open),
        curX: curX,
        lineR: lineR,
        high: high,
        low: low,
      );
    } else if (close > open) {
      // 实体高度>= CandleLineWidth
      if (close - open < mCandleLineWidth) {
        open = close - mCandleLineWidth;
      }
      _drawCandleBody(
        canvas,
        color: chartColors.candleStyle.dnColor,
        hollow: chartColors.candleStyle.bodyStyle.isHollow(rising: false),
        bodyRect: Rect.fromLTRB(curX - r, open, curX + r, close),
        curX: curX,
        lineR: lineR,
        high: high,
        low: low,
      );
    }
  }

  /// Vẽ 1 nến: bấc LUÔN tô đặc, vẽ trước; thân (`bodyRect`) tô đặc hoặc chỉ
  /// viền tùy [hollow].
  ///
  /// Khi [hollow]: bấc CHỈ vẽ 2 đoạn râu thò ra ngoài thân (`high` ->
  /// `bodyRect.top` và `bodyRect.bottom` -> `low`) — KHÔNG vẽ đoạn cắt ngang
  /// ruột thân, để thân thực sự rỗng (không có gạch xuyên giữa). 2 đoạn râu
  /// gộp vào 1 `_hollowWickPath` rồi vẽ bằng 1 `drawPath` (thay vì 2
  /// `drawRect` riêng) — tổng draw call/nến hollow còn 2 (bấc + viền thân),
  /// ngang bằng nến solid, thay vì 3 như trước.
  /// Khi solid: giữ nguyên 1 đoạn bấc liền `high` -> `low` như trước (không
  /// đổi hành vi cũ — thân tô đặc đã che hết phần bấc trùng vị trí).
  void _drawCandleBody(
    Canvas canvas, {
    required Color color,
    required bool hollow,
    required Rect bodyRect,
    required double curX,
    required double lineR,
    required double high,
    required double low,
  }) {
    // chartPaint luôn là fill trong renderer này (không nơi nào khác mutate
    // sang stroke — viền hollow dùng _hollowBorderPaint riêng) nên KHÔNG cần
    // set lại `.style` mỗi nến; chỉ `.color` thực sự đổi theo nến.
    chartPaint.color = color;
    if (hollow) {
      final bool hasTopWick = bodyRect.top > high;
      final bool hasBottomWick = low > bodyRect.bottom;
      if (hasTopWick || hasBottomWick) {
        _hollowWickPath.reset();
        if (hasTopWick) {
          _hollowWickPath.addRect(
            Rect.fromLTRB(curX - lineR, high, curX + lineR, bodyRect.top),
          );
        }
        if (hasBottomWick) {
          _hollowWickPath.addRect(
            Rect.fromLTRB(curX - lineR, bodyRect.bottom, curX + lineR, low),
          );
        }
        canvas.drawPath(_hollowWickPath, chartPaint);
      }
      // Paint RIÊNG (_hollowBorderPaint, luôn stroke) — không mutate
      // chartPaint (dùng chung, mặc định fill cho mọi draw khác của
      // renderer này) rồi phải reset lại sau mỗi nến rỗng. Cấp phát lần đầu
      // dùng tới (style hollow) — không tốn allocation ở style solid.
      canvas.drawRect(
        bodyRect,
        (_hollowBorderPaint ??= Paint()
              ..isAntiAlias = true
              ..filterQuality = FilterQuality.high
              ..style = PaintingStyle.stroke
              ..strokeWidth = mCandleLineWidth)
          ..color = color,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTRB(curX - lineR, high, curX + lineR, low),
        chartPaint,
      );
      canvas.drawRect(bodyRect, chartPaint);
    }
  }

  /// Vẽ nhãn giá tại các mốc "tròn số" đã tính trong constructor (§6.3), thay
  /// vì chia đều pixel rồi suy ngược ra giá (label khi đó không phải số tròn).
  /// Số chữ số thập phân dùng `fixedLength` (yêu cầu trực tiếp "axis Y cho
  /// giống liveprice") — KHÔNG còn tự suy theo `decimalsFor(step)` như trước
  /// (khác trước: `decimals` tăng/giảm theo độ zoom nên có thể lệch số thập
  /// phân so với badge live price ngay cạnh). Đánh đổi CHẤP NHẬN ĐƯỢC theo
  /// yêu cầu: symbol giá rất nhỏ (vd `0.00001234`) với `fixedLength` thấp
  /// (mặc định 2) có thể ra nhiều tick trùng nhãn `0.00` — do host app tự
  /// truyền `fixedLength` đúng theo precision thật của symbol để tránh.
  ///
  /// Vẽ vào [priceAxisRect] (strip riêng bên phải, §7) — KHÔNG đè lên
  /// `chartRect` (nến) như trước khi có strip.
  @override
  void drawVerticalText(Canvas canvas, TextStyle textStyle, int gridRows) {
    for (final price in _priceTicks) {
      final double y = _priceToScreenY(price);
      final TextPainter tp = _cachedPriceLabel(
        NumberUtil.formatFixed(price, fixedLength) ?? '',
        textStyle,
      );

      double offsetX;
      switch (verticalTextAlignment) {
        case VerticalTextAlignment.left:
          offsetX = priceAxisRect.left + chartStyle.space;
          break;
        case VerticalTextAlignment.right:
          offsetX = priceAxisRect.right - tp.width - chartStyle.space;
          break;
      }

      // Kẹp trong dải chartRect (chiều dọc panel này) để label không tràn ra
      // ngoài panel (§8) — strip giá dùng chung X nhưng mỗi panel vẫn giữ Y
      // riêng của mình.
      final double y2 = y.clamp(
        chartRect.top + tp.height / 2,
        chartRect.bottom - tp.height / 2,
      );
      tp.paint(canvas, Offset(offsetX, y2 - tp.height / 2));
    }
  }

  /// [verticalXs]: toạ độ x của tick thời gian đã chọn bởi time-tick planner —
  /// dùng chung với `drawVerticalText`/`drawDate` của `ChartPainter` (I6).
  /// Lưới ngang dùng lại đúng các mốc giá `_priceTicks` để lưới và label trục
  /// giá luôn khớp nhau, thay vì `gridRows` chia đều pixel như trước.
  @override
  void drawGrid(Canvas canvas, int gridRows, List<double> verticalXs) {
    for (final price in _priceTicks) {
      final double y = _priceToScreenY(price);
      canvas.drawLine(
        Offset(0, y),
        Offset(chartRect.width, y),
        gridPaint,
      );
    }
    for (final x in verticalXs) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, chartRect.bottom),
        gridPaint,
      );
    }

    /// draw top grid
    canvas.drawLine(Offset(0, 0), Offset(chartRect.width, 0), gridPaint..color);

    /// draw bottom grid
    // canvas.drawLine(
    //   Offset(0, chartRect.bottom + mBottomPadding),
    //   Offset(chartRect.width, chartRect.bottom + mBottomPadding),
    //   gridPaint..color,
    // );
  }

  @override
  double getY(double y) {
    //For TrendLine
    updateTrendLineData();
    return (maxValue - y) * scaleY + _contentRect.top;
  }

  void updateTrendLineData() {
    trendLineMax = maxValue;
    trendLineScale = scaleY;
    trendLineContentRec = _contentRect.top;
  }
}
