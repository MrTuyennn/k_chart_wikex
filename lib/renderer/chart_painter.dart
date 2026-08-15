import 'dart:async' show StreamSink;
import 'package:flutter/material.dart';
import 'package:k_chart_jk/extension/canvas_extension.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';
import 'package:k_chart_jk/utils/index.dart';
import '../entity/info_window_entity.dart';
import '../entity/k_line_entity.dart';
import 'base_chart_painter.dart';
import 'base_chart_renderer.dart';
import 'main_renderer.dart';
import 'secondary_renderer.dart';
import 'vol_renderer.dart';

class TrendLine {
  final Offset p1;
  final Offset p2;
  final double maxHeight;
  final double scale;

  TrendLine(this.p1, this.p2, this.maxHeight, this.scale);
}

double? trendLineX;

double getTrendLineX() {
  return trendLineX ?? 0;
}

class ChartPainter extends BaseChartPainter {
  final List<TrendLine> lines; //For TrendLine
  final bool isTrendLine; //For TrendLine
  bool isrecordingCord = false; //For TrendLine
  final double selectY; //For TrendLine
  static double get maxScrollX => BaseChartPainter.maxScrollX;
  late BaseChartRenderer mMainRenderer;
  VolRenderer? mVolRenderer;
  Set<BaseChartRenderer> mSecondaryRendererList = {};
  StreamSink<InfoWindowEntity?> sink;
  Color? upColor, dnColor;
  Color? ma5Color, ma10Color, ma30Color;
  Color? volColor;
  Color? macdColor, difColor, deaColor, jColor;
  int fixedLength;
  final KChartColors chartColors;
  late Paint paintCross, selectPointPaint, selectorBorderPaint;
  late Paint nowPriceLinePaint;
  late Paint _bgPaint;
  /// Viền khung phân cách plot | price-axis-strip | time-axis (§7.5) — tách
  /// riêng khỏi `gridPaint` của từng renderer (chỉ dùng nội bộ panel đó).
  late Paint gridSeparatorPaint;
  late Paint _trendLinePaint, _trendLineStrokePaint, _trendLineSegmentPaint;
  final bool hideGrid;
  final bool showNowPrice;
  final VerticalTextAlignment verticalTextAlignment;
  final double? livePrice;
  final double? bidPrice;
  final double? askPrice;
  final String bidLabel;
  final String askLabel;
  // khi true, bỏ qua drawBg để canvas trong suốt — dùng khi có backgroundLogo widget ở layer dưới
  final bool skipBg;

  ChartPainter(
    super.chartStyle,
    this.chartColors, {
    required this.lines, //For TrendLine
    required this.isTrendLine, //For TrendLine
    required this.selectY, //For TrendLine
    this.livePrice,
    this.bidPrice,
    this.askPrice,
    this.bidLabel = 'Bid',
    this.askLabel = 'Ask',
    required this.sink,
    required super.datas,
    required super.scaleX,
    required super.scaleY,
    required super.scrollX,
    required super.isLongPress,
    required super.selectX,
    required super.xFrontPadding,
    required super.baseDimension,
    required super.priceAxisWidthCache,
    required super.timeTickPlanner,
    super.isOnTap,
    super.isTapShowInfoDialog,
    required this.verticalTextAlignment,
    super.mainIndicators,
    super.volHidden,
    super.secondaryIndicators,
    super.isLine = false,
    super.offsetY = 0.0,
    this.hideGrid = false,
    this.showNowPrice = true,
    this.fixedLength = 2,
    this.skipBg = false,
  }) {
    paintCross = Paint()
      ..color = chartColors.crossColor
      ..strokeWidth = chartStyle.crossWidth
      ..isAntiAlias = true;
    selectPointPaint = Paint()
      ..isAntiAlias = true
      ..color = chartColors.selectFillColor;
    selectorBorderPaint = Paint()
      ..isAntiAlias = true
      ..strokeWidth = chartStyle.borderWidth
      ..style = PaintingStyle.stroke
      ..color = chartColors.selectBorderColor;

    gridSeparatorPaint = Paint()
      ..color = chartColors.gridColor
      ..strokeWidth = 0.5
      ..isAntiAlias = true;
    nowPriceLinePaint = Paint()
      ..strokeWidth = chartStyle.nowPriceLineWidth
      ..isAntiAlias = true;
    _bgPaint = Paint()..color = chartColors.bgColor;
    _trendLinePaint = Paint()
      ..color = chartColors.trendLineColor
      ..strokeWidth = 1
      ..isAntiAlias = true;
    _trendLineStrokePaint = Paint()
      ..color = chartColors.trendLineColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    _trendLineSegmentPaint = Paint()
      ..color = Colors.yellow
      ..strokeWidth = 2;

    // Áp style theo chartColors cho indicator nào chưa tự custom indicatorStyle.
    applyIndicatorColorStyles(mainIndicators, secondaryIndicators, chartColors);
  }

  @override
  TextStyle getTextStyle(Color color) =>
      resolveTextStyle(chartColors.candleStyle.textStyle, color);

  /// Headroom trên/dưới dải giá hiển thị (CHART_AXES.md §6.2) — không có phần
  /// đệm này, nến cao/thấp nhất chạm sát mép panel. Chỉ áp cho DẢI hiển thị
  /// (đưa vào `MainRenderer`); `mMainMaxValue`/`mMainMinValue` gốc (annotation
  /// max/min, kẹp now-price) giữ nguyên giá trị thật, không bị pad.
  static const double _kPricePadFraction = 0.08;

  @override
  void initChartRenderer() {
    final double priceRange = mMainMaxValue - mMainMinValue;
    final double pricePad = priceRange > 0 ? priceRange * _kPricePadFraction : 0;
    mMainRenderer = MainRenderer(
      mMainRect,
      mPriceAxisRect,
      mMainMaxValue + pricePad,
      mMainMinValue - pricePad,
      mTopPadding,
      mainIndicators,
      isLine,
      fixedLength,
      chartStyle,
      chartColors,
      scaleX,
      verticalTextAlignment,
      mBottomPadding,
      scaleY,
      (mMainRect.top + mMainRect.bottom) / 2,
      offsetY,
    );
    if (mVolRect != null) {
      mVolRenderer = VolRenderer(
        mVolRect!,
        mPriceAxisRect,
        mVolMaxValue,
        mVolMinValue,
        mChildPadding,
        fixedLength,
        chartStyle,
        chartColors,
      );
    } else {
      mVolRenderer = null;
    }
    mSecondaryRendererList.clear();
    for (int i = 0; i < mSecondaryRectList.length; ++i) {
      mSecondaryRendererList.add(
        SecondaryRenderer(
          mSecondaryRectList[i].mRect,
          mPriceAxisRect,
          mSecondaryRectList[i].mMaxValue,
          mSecondaryRectList[i].mMinValue,
          mChildPadding,
          secondaryIndicators[i],
          fixedLength,
          chartStyle,
          chartColors,
        ),
      );
    }

    // §7.6 — đo label rộng nhất SAU khi biết tick giá thật, áp cho frame kế
    // tiếp (xem doc [priceAxisWidth]/[PriceAxisWidthCache]). Chỉ đo panel giá
    // chính (số dài/nhiều thập phân nhất, quyết định độ rộng strip).
    updatePriceAxisWidth(
      (mMainRenderer as MainRenderer).measureMaxLabelWidth(
        getTextStyle(chartColors.defaultTextColor),
      ),
    );
  }

  @override
  void drawBg(Canvas canvas, Size size) {
    if (skipBg) return;
    // mWidth, không phải mMainRect.width/... — các rect panel giờ chỉ rộng
    // bằng mPlotWidth (§7), nhưng nền phải phủ hết TOÀN BỘ canvas kể cả strip
    // giá bên phải, nếu không strip sẽ trông như 1 khoảng trống trong suốt.
    canvas.drawRect(
      Rect.fromLTRB(0, 0, mWidth, mMainRect.height + mTopPadding),
      _bgPaint,
    );
    if (mVolRect != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, mMainRect.bottom, mWidth, mVolRect!.bottom),
        _bgPaint,
      );
    }
    for (int i = 0; i < mSecondaryRectList.length; ++i) {
      final r = mSecondaryRectList[i].mRect;
      canvas.drawRect(
        Rect.fromLTRB(0, r.top - mChildPadding, mWidth, r.bottom),
        _bgPaint,
      );
    }
    // mDateRect + mCornerRect riêng (không gộp thành 1 rect full-width) để
    // giữ nguyên mDateRect đúng nghĩa "chỉ rộng bằng plot" (R1) cho các chỗ
    // khác đang dùng nó — ở đây chỉ cần tô nền, ghép 2 rect là đủ, không cần
    // đổi field.
    canvas.drawRect(mDateRect, _bgPaint);
    canvas.drawRect(mCornerRect, _bgPaint);
  }

  @override
  void drawGrid(canvas) {
    if (!hideGrid) {
      // Cùng 1 danh sách x cho cả 3 panel — lưới dọc luôn thẳng hàng dù số
      // lượng/vị trí tick thay đổi theo zoom (CHART_AXES.md I6).
      final verticalXs = mTimeTicks.map((t) => t.x).toList();
      mMainRenderer.drawGrid(canvas, mGridRows, verticalXs);
      mVolRenderer?.drawGrid(canvas, mGridRows, verticalXs);
      for (final element in mSecondaryRendererList) {
        element.drawGrid(canvas, mGridRows, verticalXs);
      }
    }
    _drawAxisSeparators(canvas);
  }

  /// 2 đường phân cách khung (§7, §7.5 z-order bước 4) — KHÔNG phụ thuộc
  /// `hideGrid` (đây là viền khung, không phải lưới giá/thời gian):
  ///  - dọc tại `mPlotWidth`, cao hết plot+strip giá+trục thời gian
  ///    (main→đáy `mDateRect`) — ranh giới plot | price axis (R2).
  ///  - ngang tại đỉnh `mDateRect`, rộng hết `mWidth` — ranh giới
  ///    {plot,price axis} | {time axis, corner} (R1).
  void _drawAxisSeparators(Canvas canvas) {
    canvas.drawLine(
      Offset(mPlotWidth, mMainRect.top),
      Offset(mPlotWidth, mDateRect.bottom),
      gridSeparatorPaint,
    );
    canvas.drawLine(
      Offset(0, mDateRect.top),
      Offset(mWidth, mDateRect.top),
      gridSeparatorPaint,
    );
  }

  @override
  void drawChart(Canvas canvas, Size size) {
    // Đường tham chiếu ngang (vd 20/80 của StochRSI) vẽ ở screen space,
    // trước khi translate/scale để không bị giãn theo scaleX và luôn
    // nằm phía sau đường indicator. Cùng gate bởi hideGrid như drawGrid ở trên,
    // vì đây cũng là một dạng đường lưới nền.
    if (!hideGrid) {
      for (final element in mSecondaryRendererList) {
        element.drawReferenceLines(canvas);
      }
    }

    canvas.save();
    // Clip theo chiều NGANG vào đúng mPlotWidth, ÁP TRƯỚC translate/scale
    // theo X bên dưới nên nằm ở screen space (không co giãn theo scaleX) —
    // nếu không, nến/volume/secondary ở gần mép phải sẽ vẽ TRÀN vào price-
    // axis strip (đè lên label giá) trước khi index của chúng bị index-loop
    // (mRealStopIndex/mVisibleStopIndex) loại hẳn khỏi vòng vẽ — thấy rõ nhất
    // khi zoom vào (candleWidth lớn, thân nến cuối cùng thừa hẳn ra ngoài dù
    // tâm nến vẫn còn nằm trong mPlotWidth). Nến/volume/secondary vốn không
    // hề bị clip ngang ở đâu khác — clip duy nhất trước đây (`BaseChartPainter.
    // paint`) phủ TOÀN canvas, gồm cả strip giá, nên không chặn được.
    canvas.clipRect(Rect.fromLTRB(0, 0, mPlotWidth, mDateRect.top));
    canvas.translate(mTranslateX * scaleX, 0.0);
    canvas.scale(scaleX, 1.0);

    // TODO: scaleY dùng canvas transform thay vì scale value range từng component
    // giúp main chart và volume scale cùng nhau như 1 đơn vị (tương tự cách scaleX hoạt động)
    canvas.save();
    // Clip theo chiều Y vào đúng vùng mMainRect — tránh nội dung tràn ra ngoài
    // đè lên time bar, secondary indicators hoặc top padding khi scaleY thay đổi
    canvas.clipRect(
      Rect.fromLTRB(
        -mDataLen - mWidth,
        mMainRect.top,
        mDataLen + mWidth,
        mMainRect.bottom,
      ),
    );
    final double centerY = (mMainRect.top + mMainRect.bottom) / 2;
    // offsetY dịch chuyển chart dọc (pan Y), neo tại centerY để scaleY không bị lệch
    canvas.translate(0, centerY * (1 - scaleY) + offsetY);
    canvas.scale(1.0, scaleY);
    // mRealStartIndex/mRealStopIndex (không phải mStartIndex/mStopIndex) —
    // 2 biến sau có thể trỏ vào vùng tương lai (chưa có nến) khi 1 main
    // indicator dùng futureShift (vd Ichimoku), truy cập datas![i] ở đó sẽ
    // RangeError. mRealStartIndex/mRealStopIndex đã clamp về nến thật và
    // mở rộng thêm futureShift mỗi phía để vẫn đủ nến nguồn vẽ đường dịch.
    for (int i = mRealStartIndex; datas != null && i <= mRealStopIndex; i++) {
      KLineEntity? curPoint = datas?[i];
      if (curPoint == null) continue;
      KLineEntity lastPoint = i == 0 ? curPoint : datas![i - 1];
      double curX = getX(i);
      double lastX = i == 0 ? curX : getX(i - 1);
      mMainRenderer.drawChart(lastPoint, curPoint, lastX, curX, size, canvas);
    }
    canvas.restore();

    // VolRenderer + SecondaryRenderer cùng nằm ngoài scope scaleY của main
    // → panel volume + indicator phụ không bị giãn khi user zoom dọc nến.
    // Dùng mVisibleStartIndex/mVisibleStopIndex (không phải mRealStartIndex/
    // mRealStopIndex) — vol/secondary không có khái niệm đường bị dịch nên
    // không cần vùng margin rộng hơn viewport, chỉ tốn thêm draw call vô ích.
    for (int i = mVisibleStartIndex;
        datas != null && i <= mVisibleStopIndex;
        i++) {
      KLineEntity? curPoint = datas?[i];
      if (curPoint == null) continue;
      KLineEntity lastPoint = i == 0 ? curPoint : datas![i - 1];
      double curX = getX(i);
      double lastX = i == 0 ? curX : getX(i - 1);
      mVolRenderer?.drawChart(lastPoint, curPoint, lastX, curX, size, canvas);
      for (final element in mSecondaryRendererList) {
        element.drawChart(lastPoint, curPoint, lastX, curX, size, canvas);
      }
    }

    if ((isLongPress || (isTapShowInfoDialog && isOnTap)) && !isTrendLine) {
      drawCrossLine(canvas, size);
    }
    if (isTrendLine) drawTrendLines(canvas, size);
    canvas.restore();
  }

  @override
  void drawVerticalText(canvas) {
    var textStyle = getTextStyle(chartColors.defaultTextColor);
    if (!hideGrid) {
      mMainRenderer.drawVerticalText(canvas, textStyle, mGridRows);
    }
    // Panel volume dùng textStyle riêng (chartColors.volumeStyle.textStyle) —
    // không tái dùng textStyle của main chart ở trên.
    final volTextStyle = mVolRenderer?.getTextStyle(
      chartColors.defaultTextColor,
    );
    if (volTextStyle != null) {
      mVolRenderer?.drawVerticalText(canvas, volTextStyle, mGridRows);
    }

    for (final element in mSecondaryRendererList) {
      element.drawVerticalText(
        canvas,
        element.getTextStyle(chartColors.defaultTextColor),
        mGridRows,
      );
    }
  }

  @override
  void drawDate(Canvas canvas, Size size) {
    if (datas == null) return;

    // Tick đã được BaseChartPainter chọn 1 lần/frame (weight ladder,
    // CHART_AXES.md §5) — ở đây chỉ vẽ, không tự chọn tick (I3).
    //
    // KHÔNG kẹp/ẩn label theo có "fit" hay không — 2 cách đó đều gây cảm giác
    // ẩn/hiện đột ngột ở 2 mép (kẹp thì label dính cứng 1 chỗ; ẩn khi không
    // fit thì label biến mất/xuất hiện đột ngột dù gridline vẫn còn). Thay
    // vào đó CLIP canvas theo đúng mPlotWidth rồi vẽ label ở ĐÚNG vị trí thật
    // (tick.x, không dịch) — y hệt cách nến/volume bị canvas cắt tự nhiên khi
    // trượt ra khỏi viewport, cho cảm giác trượt liên tục thay vì bật/tắt.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, mDateRect.top, mPlotWidth, mDateRect.bottom));
    for (final tick in mTimeTicks) {
      TextPainter tp = getTextPainter(tick.label, null);
      double y = mDateRect.top + (mBottomPadding - tp.height) / 2;
      double x = tick.x - tp.width / 2;
      tp.paint(canvas, Offset(x, y));
    }
    canvas.restore();
  }

  /// draw the cross line. when user focus
  @override
  void drawCrossLineText(Canvas canvas, Size size) {
    var index = calculateSelectedX(selectX);
    KLineEntity point = getItem(index);

    TextPainter tp = getTextPainter(
      NumberUtil.formatFixed(point.close, fixedLength),
      chartColors.crossTextColor,
    );
    double textHeight = tp.height;
    double textWidth = tp.width;

    double w1 = 5;
    double w2 = 3;
    double r = textHeight / 2 + w2;
    double y = getMainY(point.close);
    double x;
    double space = 4.0;
    bool isLeft = false;
    if (translateXtoX(getX(index)) < mPlotWidth / 2) {
      isLeft = false;
      x = space;
      RRect rect = RRect.fromLTRBR(
        x,
        y - r,
        x + textWidth + 2 * w1,
        y + r,
        Radius.circular(2.0),
      );
      canvas.drawRRect(rect, selectPointPaint);
      canvas.drawRRect(rect, selectorBorderPaint);
      tp.paint(canvas, Offset(x + w1, y - textHeight / 2));
    } else {
      isLeft = true;
      x = mPlotWidth - textWidth - 2 * w1 - space;
      RRect rect = RRect.fromLTRBR(
        x,
        y - r,
        mPlotWidth - space,
        y + r,
        Radius.circular(2.0),
      );
      canvas.drawRRect(rect, selectPointPaint);
      canvas.drawRRect(rect, selectorBorderPaint);
      tp.paint(canvas, Offset(x + w1, y - textHeight / 2));
    }

    TextPainter dateTp = getTextPainter(
      getDate(point.time),
      chartColors.crossTextColor,
    );
    textWidth = dateTp.width;
    r = textHeight / 2;
    x = translateXtoX(getX(index));
    y = mDateRect.top;

    if (x < textWidth + 2 * w1) {
      x = 1 + textWidth / 2 + w1;
    } else if (mPlotWidth - x < textWidth + 2 * w1) {
      x = mPlotWidth - 1 - textWidth / 2 - w1;
    }

    RRect rectBox = RRect.fromLTRBR(
      x - textWidth / 2 - w1,
      y,
      x + textWidth / 2 + w1,
      mDateRect.bottom,
      Radius.circular(2.0),
    );

    // double baseLine = textHeight / 2;
    canvas.drawRRect(rectBox, selectPointPaint);
    canvas.drawRRect(rectBox, selectorBorderPaint);

    dateTp.paint(
      canvas,
      Offset(
        x - textWidth / 2,
        mDateRect.top + (mDateRect.height - dateTp.height) / 2,
      ),
    );

    //Long press to display the details of this data
    sink.add(InfoWindowEntity(point, isLeft: isLeft));
  }

  @override
  void drawText(Canvas canvas, KLineEntity data, double x) {
    // Khi long press / tap: hiển thị data của nến được chọn (cross line)
    // Bình thường: data đến từ getItem(mStopIndex) — candle phải nhất đang thấy
    if (isLongPress || (isTapShowInfoDialog && isOnTap)) {
      var index = calculateSelectedX(selectX);
      data = getItem(index);
    }
    mMainRenderer.drawText(canvas, data, x);
    mVolRenderer?.drawText(canvas, data, x);
    for (final element in mSecondaryRendererList) {
      element.drawText(canvas, data, x);
    }
  }

  @override
  void drawMaxAndMin(Canvas canvas) {
    if (isLine) return;
    //plot maxima and minima
    double x = translateXtoX(getX(mMainMinIndex));
    double y = _applyScaleY(getMainY(mMainLowMinValue));
    if (x < mPlotWidth / 2) {
      //draw right
      TextPainter tp = getTextPainter(
        "── ${NumberUtil.formatFixed(mMainLowMinValue, fixedLength) ?? ''}",
        chartColors.minColor,
      );
      tp.paint(canvas, Offset(x, y - tp.height / 2));
    } else {
      TextPainter tp = getTextPainter(
        "${NumberUtil.formatFixed(mMainLowMinValue, fixedLength) ?? ''} ──",
        chartColors.minColor,
      );
      tp.paint(canvas, Offset(x - tp.width, y - tp.height / 2));
    }
    x = translateXtoX(getX(mMainMaxIndex));
    y = _applyScaleY(getMainY(mMainHighMaxValue));
    if (x < mPlotWidth / 2) {
      //draw right
      TextPainter tp = getTextPainter(
        "── ${NumberUtil.formatFixed(mMainHighMaxValue, fixedLength) ?? ''}",
        chartColors.maxColor,
      );
      tp.paint(canvas, Offset(x, y - tp.height / 2));
    } else {
      TextPainter tp = getTextPainter(
        "${NumberUtil.formatFixed(mMainHighMaxValue, fixedLength) ?? ''} ──",
        chartColors.maxColor,
      );
      tp.paint(canvas, Offset(x - tp.width, y - tp.height / 2));
    }
  }

  @override
  void drawNowPrice(Canvas canvas) {
    if (!showNowPrice) return;
    if (datas == null) return;

    // ưu tiên livePrice từ socket, fallback về datas.last.close
    final double value = livePrice ?? datas!.last.close;

    double y = _applyScaleY(getMainY(value));

    // giữ trong vùng hiển thị (đã tính scaleY)
    if (y > _applyScaleY(getMainY(mMainLowMinValue))) {
      y = _applyScaleY(getMainY(mMainLowMinValue));
    }
    if (y < _applyScaleY(getMainY(mMainHighMaxValue))) {
      y = _applyScaleY(getMainY(mMainHighMaxValue));
    }

    // màu dựa theo livePrice so với open của nến cuối
    Color priceColor = value >= datas!.last.open
        ? chartColors.livePriceStyle.upColor
        : chartColors.livePriceStyle.dnColor;

    nowPriceLinePaint.color = priceColor;

    // vẽ đường kẻ ngang — LUÔN vẽ (không phụ thuộc bidPrice/askPrice), vẫn
    // là mốc "đây là mức giá hiện tại" xuyên suốt chart bất kể badge giá vẽ
    // ở đâu.
    canvas.drawDashLine(
      Offset(0, y),
      Offset(-mTranslateX + mWidth / scaleX, y),
      nowPriceLinePaint,
    );

    // Badge "flag" giá (mũi tên + số) chỉ vẽ khi KHÔNG có đủ cặp bid/ask —
    // khi có, [drawBidAsk] vẽ 1 box gộp cả Ask/Bid/live-price (xem đó), vẽ
    // thêm cái này nữa sẽ trùng lặp giá trị live price ở 2 nơi cùng lúc.
    if (bidPrice != null && askPrice != null) return;

    // label vẽ giá — nếu textStyle không tự set color thì fallback về trắng
    // (mặc định của LivePriceStyle), tránh chữ dùng màu mặc định của
    // TextPainter (đen) không đọc được trên nền badge màu upColor/dnColor.
    TextPainter tp = TextPainter(
      text: TextSpan(
        text: NumberUtil.formatFixed(value, fixedLength) ?? '',
        style: resolveTextStyle(chartColors.livePriceStyle.textStyle, Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    double paddingX = 5, paddingY = 3;
    double space = 5.0;
    double offsetX;
    switch (verticalTextAlignment) {
      case VerticalTextAlignment.left:
        offsetX = space;
        break;
      case VerticalTextAlignment.right:
        offsetX = mPlotWidth - tp.width - paddingX * 2 - space;
        break;
    }

    double top = y - tp.height / 2;
    final badgeWidth = tp.width + paddingX * 2;
    final badgeHeight = tp.height + paddingY * 2;

    // Nền badge "flag" — width/height tự scale theo độ dài text giá
    // (LivePriceBadgePainter.paint tự nhân tỉ lệ theo size truyền vào).
    canvas.save();
    canvas.translate(offsetX, top - paddingY);
    LivePriceBadgePainter(
      color: priceColor,
    ).paint(canvas, Size(badgeWidth, badgeHeight));
    canvas.restore();

    tp.paint(canvas, Offset(offsetX + paddingX, top));
  }

  // Padding X/Y trong mỗi ô, khe hở giữa 3 ô, khoảng cách mép trái khi đóng
  // `left`, mức tràn qua price-axis strip khi đóng `right` (âm = lấn qua
  // `mPlotWidth`) — tách thành static const để [_bidAskTotalWidth] (dùng bởi
  // [extraFrontPaddingPx]) tính đúng bề rộng GIỐNG HỆT [drawBidAsk], không
  // lệch nhau nếu sau này chỉnh số.
  static const double _bidAskLeftSpace = 2.0;
  static const double _bidAskRightOverflow = -20.0;
  static const double _bidAskPaddingX = 6.0, _bidAskPaddingY = 3.0;
  static const double _bidAskCellGap = 2.0;

  /// Tổng bề rộng box bid/ask — CÙNG công thức với phần bề rộng trong
  /// [drawBidAsk] (không vẽ gì) — dùng bởi [extraFrontPaddingPx] để chừa đủ
  /// chỗ trước nến cuối. Trả `null` khi không đủ điều kiện vẽ box (giống hệt
  /// điều kiện đầu [drawBidAsk]).
  double? _bidAskTotalWidth() {
    if (bidPrice == null || askPrice == null) return null;
    if (datas == null) return null;

    final double value = livePrice ?? datas!.last.close;
    final textStyle = resolveTextStyle(chartColors.livePriceStyle.textStyle, Colors.white);
    TextPainter buildTp(String text) => TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final askTp = buildTp('$askLabel ${NumberUtil.formatFixed(askPrice!, fixedLength) ?? ''}');
    final bidTp = buildTp('$bidLabel ${NumberUtil.formatFixed(bidPrice!, fixedLength) ?? ''}');
    final priceTp = buildTp(NumberUtil.formatFixed(value, fixedLength) ?? '');

    final double leftColWidth =
        [askTp.width, bidTp.width].reduce((a, b) => a > b ? a : b) + _bidAskPaddingX * 2;
    final double rightColWidth = priceTp.width + _bidAskPaddingX * 2;
    return leftColWidth + _bidAskCellGap + rightColWidth;
  }

  /// Chỉ đóng `right` (mặc định — mép sát trục giá, đúng nơi box thật sự
  /// tràn vào vùng plot) mới cần chừa chỗ; `left` đã luôn nằm gọn trong
  /// `mPlotWidth` từ trước (không đụng tới nến cuối). Cộng thêm biên thở nhỏ
  /// (8px) — tránh box dính sát mép nến cuối dù kỹ thuật không đè lên.
  ///
  /// Bối cảnh: box rộng hơn nhiều so với badge now-price cũ (2 cột thay vì
  /// 1), trong khi `xFrontPadding` mặc định (100px) được tính cho badge cũ —
  /// khi mới mở chart (chưa scroll), nến cuối có thể nằm ngay dưới box nếu
  /// không chừa thêm. Xem CHANGELOG.
  @override
  double get extraFrontPaddingPx {
    if (verticalTextAlignment != VerticalTextAlignment.right) return 0.0;
    final totalWidth = _bidAskTotalWidth();
    if (totalWidth == null) return 0.0;
    const double breathingMargin = 8.0;
    final double required = totalWidth + _bidAskRightOverflow + breathingMargin;
    // `required` là TỔNG khoảng gap cần có — chỉ CỘNG THÊM phần còn thiếu so
    // với `xFrontPadding` đã tính sẵn (không cộng thẳng `required`, tránh
    // cộng dồn 2 lần khi `xFrontPadding` mặc định đã đủ chỗ).
    final double basePadding = BaseChartPainter.effectiveRightPaddingPx(
      xFrontPadding,
      mPlotWidth,
    );
    final double extra = required - basePadding;
    return extra > 0 ? extra : 0.0;
  }

  /// 1 box gộp — cột TRÁI 2 ô xếp chồng (Ask trên/đỏ, Bid dưới/xanh), cột
  /// PHẢI 1 ô CAO BẰNG 1 HÀNG (không kéo dài hết chiều cao cột trái) hiện
  /// live price (màu theo up/down như badge cũ), căn giữa theo chiều dọc
  /// trong khối — tất cả trong CÙNG 1 khối, tâm dọc tại ĐÚNG Y của đường
  /// now-price (không
  /// còn map riêng theo giá thật của bid/ask nữa — đơn giản hơn hẳn bản
  /// trước, và luôn đúng ý "đi cùng live price"). Đóng theo
  /// [verticalTextAlignment] (mặc định `right` — sát trục giá bên phải,
  /// khớp đúng vị trí badge now-price cũ; `left` thì đóng mép trái plot),
  /// luôn nằm trong `mPlotWidth` nên không đè lên price-axis strip. Chỉ vẽ
  /// khi CẢ HAI [bidPrice]/[askPrice] cùng non-null; live price vẫn theo
  /// đúng fallback `livePrice ?? datas.last.close` như [drawNowPrice] (2 hàm
  /// phải khớp Y với nhau — cùng 1 đường dashed).
  ///
  /// [extraFrontPaddingPx] chừa sẵn chỗ trước nến cuối bằng công thức bề
  /// rộng GIỐNG HỆT box vẽ ở đây (qua [_bidAskTotalWidth]) — sửa layout ở
  /// dưới (padding/cellGap/rightOverflow) thì sửa luôn các hằng số
  /// `_bidAsk*` ở trên, đừng để 2 nơi lệch nhau.
  @override
  void drawBidAsk(Canvas canvas) {
    if (bidPrice == null || askPrice == null) return;
    if (datas == null) return;

    final double value = livePrice ?? datas!.last.close;
    final double minY = _applyScaleY(getMainY(mMainHighMaxValue));
    final double maxY = _applyScaleY(getMainY(mMainLowMinValue));
    final double centerY = _applyScaleY(getMainY(value)).clamp(minY, maxY);

    final Color priceColor = value >= datas!.last.open
        ? chartColors.livePriceStyle.upColor
        : chartColors.livePriceStyle.dnColor;

    final textStyle = resolveTextStyle(chartColors.livePriceStyle.textStyle, Colors.white);
    TextPainter buildTp(String text) =>
        TextPainter(
          text: TextSpan(text: text, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();

    final askTp = buildTp('$askLabel ${NumberUtil.formatFixed(askPrice!, fixedLength) ?? ''}');
    final bidTp = buildTp('$bidLabel ${NumberUtil.formatFixed(bidPrice!, fixedLength) ?? ''}');
    final priceTp = buildTp(NumberUtil.formatFixed(value, fixedLength) ?? '');

    final double rowHeight = askTp.height + _bidAskPaddingY * 2;
    final double leftColWidth =
        [askTp.width, bidTp.width].reduce((a, b) => a > b ? a : b) + _bidAskPaddingX * 2;
    final double rightColWidth = priceTp.width + _bidAskPaddingX * 2;
    final double boxHeight = rowHeight * 2 + _bidAskCellGap;

    // `centerY` đã kẹp trong [minY, maxY] (1 điểm), nhưng box có CHIỀU CAO
    // (`boxHeight`) — nếu centerY sát mép trên/dưới, nửa box vẫn có thể tràn
    // ra ngoài [minY, maxY]. Dịch cả khối vào lại, giống cách đã sửa ở bản
    // trước cho 2 badge riêng (nay chỉ còn 1 khối nên đơn giản hơn nhiều —
    // không cần giữ `minGap` giữa 2 điểm nữa).
    double top = centerY - boxHeight / 2;
    if (top < minY) {
      top = minY;
    }
    if (top + boxHeight > maxY) {
      top = maxY - boxHeight;
    }
    // Trường hợp cực đoan `boxHeight > maxY - minY` (main chart thấp hơn cả
    // box — hầu như không xảy ra trong thực tế): nhánh trên có thể đẩy
    // `top` xuống dưới `minY` lần nữa. Ưu tiên không tràn mép TRÊN (dữ liệu
    // nến quan trọng hơn phần đáy) — kẹp cứng lần cuối.
    top = top.clamp(minY, maxY);
    final double askTop = top;
    final double bidTop = top + rowHeight + _bidAskCellGap;

    // Đóng theo `verticalTextAlignment` — mặc định `right` (khớp đúng cách
    // badge now-price cũ đóng bên phải sát trục giá), cố ý tràn nhẹ qua
    // price-axis strip (`rightOverflow` âm) theo yêu cầu. `left` thì vẫn giữ
    // nguyên trong `mPlotWidth` như trước (không ai yêu cầu đổi nhánh này).
    final double totalWidth = leftColWidth + _bidAskCellGap + rightColWidth;
    final double leftColLeft = verticalTextAlignment == VerticalTextAlignment.right
        ? mPlotWidth - totalWidth - _bidAskRightOverflow
        : _bidAskLeftSpace;
    final double rightLeft = leftColLeft + leftColWidth + _bidAskCellGap;

    void drawCell(Rect rect, Color color, TextPainter tp) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = color,
      );
      tp.paint(
        canvas,
        Offset(
          rect.left + (rect.width - tp.width) / 2,
          rect.top + (rect.height - tp.height) / 2,
        ),
      );
    }

    drawCell(
      Rect.fromLTWH(leftColLeft, askTop, leftColWidth, rowHeight),
      chartColors.livePriceStyle.dnColor,
      askTp,
    );
    drawCell(
      Rect.fromLTWH(leftColLeft, bidTop, leftColWidth, rowHeight),
      chartColors.livePriceStyle.upColor,
      bidTp,
    );
    // Ô live price chỉ cao bằng 1 hàng (không kéo dài hết chiều cao Ask+Bid
    // cộng lại) — căn giữa theo chiều dọc trong khối, để trống đều 2 bên
    // trên/dưới trong cột phải.
    drawCell(
      Rect.fromLTWH(rightLeft, top + (boxHeight - rowHeight) / 2, rightColWidth, rowHeight),
      priceColor,
      priceTp,
    );
  }

  void drawTrendLines(Canvas canvas, Size size) {
    final index = calculateSelectedX(selectX);
    final double x = getX(index);
    trendLineX = x;
    final double y = selectY;

    canvas.drawLine(
      Offset(x, mTopPadding),
      Offset(x, size.height),
      _trendLinePaint,
    );
    canvas.drawLine(
      Offset(-mTranslateX, y),
      Offset(-mTranslateX + mWidth / scaleX, y),
      _trendLinePaint,
    );
    canvas.drawOval(
      scaleX >= 1
          ? Rect.fromCenter(
              center: Offset(x, y),
              height: 15.0 * scaleX,
              width: 15.0,
            )
          : Rect.fromCenter(
              center: Offset(x, y),
              height: 10.0,
              width: 10.0 / scaleX,
            ),
      _trendLineStrokePaint,
    );

    for (final element in lines) {
      final y1 = -((element.p1.dy - 35) / element.scale) + element.maxHeight;
      final y2 = -((element.p2.dy - 35) / element.scale) + element.maxHeight;
      final a = (trendLineMax! - y1) * trendLineScale! + trendLineContentRec!;
      final b = (trendLineMax! - y2) * trendLineScale! + trendLineContentRec!;
      canvas.drawLine(
        Offset(element.p1.dx, a),
        element.p2 == Offset(-1, -1) ? Offset(x, y) : Offset(element.p2.dx, b),
        _trendLineSegmentPaint,
      );
    }
  }

  ///draw cross lines
  @override
  void drawCrossLine(Canvas canvas, Size size) {
    var index = calculateSelectedX(selectX);
    KLineEntity point = getItem(index);
    double x = getX(index);
    double y = getMainY(point.close);

    // K-line chart vertical line
    canvas.drawDashLine(Offset(x, 0), Offset(x, size.height), paintCross);

    // K-line chart horizontal line
    canvas.drawDashLine(
      Offset(-mTranslateX, y),
      Offset(-mTranslateX + mWidth / scaleX, y),
      paintCross,
    );

    if (scaleX >= 1) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), height: 4.0 * scaleX, width: 4.0),
        paintCross,
      );
    } else {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), height: 4.0, width: 4.0 / scaleX),
        paintCross,
      );
    }
  }

  TextPainter getTextPainter(String? text, Color? color) {
    color ??= chartColors.defaultTextColor;
    TextSpan span = TextSpan(text: text, style: getTextStyle(color));
    TextPainter tp = TextPainter(text: span, textDirection: TextDirection.ltr);
    tp.layout();
    return tp;
  }

  static final Map<int, String> _dateStringCache = {};
  static List<String>? _cacheFormats;

  String getDate(int? date) {
    if (date == null) return '';
    if (!_formatsEqual(_cacheFormats, mFormats)) {
      _dateStringCache.clear();
      _cacheFormats = mFormats;
    }
    return _dateStringCache.putIfAbsent(
      date,
      () => dateFormat(DateTime.fromMillisecondsSinceEpoch(date), mFormats),
    );
  }

  static bool _formatsEqual(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  double getMainY(double y) => mMainRenderer.getY(y);

  // Chuyển Y gốc sang Y screen — dùng cho labels vẽ ngoài canvas transform (nowPrice, maxMin)
  // công thức đảo ngược của canvas.translate + canvas.scale, có tính offsetY
  double _applyScaleY(double rawY) {
    final double centerY = (mMainRect.top + mMainRect.bottom) / 2;
    return (centerY + (rawY - centerY) * scaleY + offsetY).clamp(
      mMainRect.top,
      mMainRect.bottom,
    );
  }

  @override
  bool shouldRepaint(BaseChartPainter oldDelegate) {
    if (oldDelegate is ChartPainter) {
      if (oldDelegate.livePrice != livePrice ||
          oldDelegate.bidPrice != bidPrice ||
          oldDelegate.askPrice != askPrice ||
          // Hiếm khi đổi lúc runtime (vd chuyển locale) hơn bidPrice/askPrice,
          // nhưng vẫn là field CÓ THỂ đổi qua UI — thiếu dòng này thì badge
          // giữ nguyên text locale cũ tới khi có lý do khác trigger repaint,
          // đúng lớp lỗi mà comment về `bodyStyle` ngay dưới đã cảnh báo.
          oldDelegate.bidLabel != bidLabel ||
          oldDelegate.askLabel != askLabel ||
          oldDelegate.isTrendLine != isTrendLine ||
          oldDelegate.selectY != selectY ||
          // `chartColors` KHÔNG so nguyên object — instance mới được dựng
          // lại mỗi build (vd `_demoColors(state)` trong example) dù nội
          // dung không đổi, so reference sẽ ép repaint MỌI build (jank).
          // `bodyStyle` là field DUY NHẤT trong chartColors hiện đổi qua
          // tương tác UI trực tiếp (Kiểu K-line picker) — thiếu dòng này,
          // đổi Solid/Hollow không tự vẽ lại ngay, chỉ "ăn theo" lần
          // repaint tiếp theo do lý do khác (vd tick livePrice) mới hiện.
          // Field `chartColors` nào khác sau này cũng đổi được qua UI thì
          // phải thêm so sánh riêng ở đây theo đúng cách này (không so
          // nguyên `chartColors`).
          oldDelegate.chartColors.candleStyle.bodyStyle !=
              chartColors.candleStyle.bodyStyle ||
          !_trendLinesEqual(oldDelegate.lines, lines)) {
        return true;
      }
    }
    return super.shouldRepaint(oldDelegate);
  }

  static bool _trendLinesEqual(List<TrendLine> a, List<TrendLine> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final TrendLine x = a[i], y = b[i];
      if (x.p1 != y.p1 ||
          x.p2 != y.p2 ||
          x.maxHeight != y.maxHeight ||
          x.scale != y.scale) {
        return false;
      }
    }
    return true;
  }

  bool isInMainRect(Offset point) => mMainRect.contains(point);
}
