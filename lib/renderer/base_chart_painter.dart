import 'dart:math';
import 'package:flutter/material.dart'
    show Color, TextStyle, Rect, Canvas, Size, CustomPainter;
import 'package:k_chart_jk/indicator/indicator_template.dart';
import 'package:k_chart_jk/utils/index.dart';
import '../styles/k_chart_style.dart' show KChartStyle;
import '../entity/k_line_entity.dart';
import 'base_dimension.dart';

/// Holder mutable cho bề rộng strip trục giá (CHART_AXES.md §7.6) — cache
/// qua các frame dù painter bị recreate mỗi build (giống lý do dùng `static`
/// trước đây cho [BaseChartPainter.maxScrollX]/`currentStartIndex`).
///
/// **KHÔNG dùng `static`** — sở hữu bởi `_KChartWidgetState` (field bền qua
/// các lần `build()`), truyền xuống painter qua constructor. `static` nghĩa
/// là TOÀN PROCESS dùng chung 1 giá trị — 2 `KChartWidget` vẽ đồng thời với
/// độ rộng label giá khác nhau sẽ tranh chấp/nhấp nháy layout của nhau.
/// Instance vẫn giữ được lợi ích "trễ 1 frame" (xem [BaseChartPainter.
/// updatePriceAxisWidth]), chỉ khác chỗ sở hữu.
class PriceAxisWidthCache {
  /// Seed khớp default gợi ý trong CHART_AXES.md §7.6.
  double value = 64.0;
}

/// BaseChartPainter
abstract class BaseChartPainter extends CustomPainter {
  static double maxScrollX = 0.0;

  /// Bề rộng strip trục giá bên phải, đọc từ [priceAxisWidthCache] (instance,
  /// sở hữu bởi `_KChartWidgetState` — xem doc [PriceAxisWidthCache]).
  /// [updatePriceAxisWidth] tính lại mỗi frame SAU khi biết label rộng nhất,
  /// áp dụng cho frame KẾ TIẾP — layout luôn trễ đúng 1 frame so với nội dung
  /// thật, tránh vòng lặp phản hồi width→plotW→visible range→price
  /// range→label→width (FAILURE MODE 7) mà không cần biết trước label rộng
  /// bao nhiêu.
  double get priceAxisWidth => priceAxisWidthCache.value;
  final PriceAxisWidthCache priceAxisWidthCache;

  /// Planner tick trục thời gian — instance, cùng lý do sở hữu như
  /// [priceAxisWidthCache] (xem doc `TimeTickPlanner`, `utils/time_ticks.dart`).
  final TimeTickPlanner timeTickPlanner;

  /// Áp §7.6: `clamp(maxLabelWidth + 14, 48, 96)`, làm tròn lên bội số 8, có
  /// hysteresis — chỉ THU khi yêu cầu mới thấp hơn giá trị hiện tại ít nhất 1
  /// bậc 8px trọn vẹn; PHÌNH thì áp ngay (label bị cắt còn tệ hơn 1 frame
  /// rộng dư). Không hysteresis khi phình sẽ làm nhãn tràn ra ngoài panel lúc
  /// giá đổi độ dài (vd 999→1000) trong đúng frame đó.
  void updatePriceAxisWidth(double maxLabelWidth) {
    final double raw = (maxLabelWidth + 14.0).clamp(48.0, 96.0);
    final double required = (raw / 8.0).ceil() * 8.0;
    if (required > priceAxisWidth || required <= priceAxisWidth - 8.0) {
      priceAxisWidthCache.value = required;
    }
  }

  /// Bản sao static của [mStartIndex] sau lần `calculateValue()` gần nhất —
  /// cho phép `KChartWidget` (gesture handler) đọc "còn cách bao nhiêu nến
  /// tới mép cũ nhất" ngay lúc scroll, không cần đợi painter instance mới
  /// (painter bị recreate mỗi build). Cùng pattern với [maxScrollX].
  static int currentStartIndex = 0;
  List<KLineEntity>? datas; // data of chart

  List<MainIndicator> mainIndicators;

  List<SecondaryIndicator> secondaryIndicators;

  /// Toggle hiển thị panel volume (ẩn = true). Khi ẩn `mVolRect` không được tạo
  /// và `BaseDimension.mVolumeHeight` = 0.
  bool volHidden;
  bool isTapShowInfoDialog;
  double scaleX = 1.0, scaleY = 1.0, scrollX = 0.0, selectX;
  double offsetY = 0.0;
  bool isLongPress = false;
  bool isOnTap;
  bool isLine;

  /// Rectangle box of main chart
  late Rect mMainRect;

  late Rect mDateRect;

  /// Strip trục giá bên phải (CHART_AXES.md §7) — main/vol/secondary đều vẽ
  /// label giá trị của mình vào đây thay vì đè lên nội dung panel. Chiều cao
  /// trùng khối plot (main→đáy panel cuối, KHÔNG gồm time axis) — mỗi
  /// renderer tự cắt theo `chartRect.top/bottom` của nó để lấy đúng phần dọc.
  late Rect mPriceAxisRect;

  /// Ô chết góc dưới-phải (§7.4) — giao giữa strip giá và trục thời gian,
  /// không thuộc trục nào. Chỉ tô nền để 2 đường phân cách kết thúc gọn,
  /// không có nội dung khác.
  late Rect mCornerRect;

  /// Chiều rộng khối plot (nến + lưới + trục thời gian) = `mWidth -
  /// priceAxisWidth` (§7.1). Dùng thay `mWidth` cho MỌI phép tính phụ thuộc
  /// "cạnh phải màn hình" của khối plot — viewport, index range, tick trục
  /// thời gian — nếu không dải index hiển thị sẽ tính lố vào phần bị strip
  /// giá che khuất, làm lệch auto-scale giá (§7.1 cảnh báo đúng lỗi này).
  late double mPlotWidth;

  /// Rectangle box of volume panel — null khi `volHidden = true`.
  Rect? mVolRect;

  /// Secondary list support
  List<RenderRect> mSecondaryRectList = [];
  late double mDisplayHeight, mWidth;
  double mTopPadding = 20.0,
      mBottomPadding = 16.0,
      mChildPadding = 12.0,
      mPaddingMainChild = 10.0;
  int mGridRows = 4, mGridColumns = 4;
  int mStartIndex = 0, mStopIndex = 0;

  /// Tick trục thời gian đã chọn cho frame hiện tại — tính 1 lần trong
  /// [calculateValue] rồi dùng chung bởi `drawDate` VÀ `drawGrid` của mọi
  /// panel (main/vol/secondary), đảm bảo lưới dọc + label luôn thẳng hàng
  /// (CHART_AXES.md I3, I6). Không renderer nào được tự chọn tick riêng.
  List<({int index, double x, String label})> mTimeTicks = [];

  /// Vùng nến THẬT đang thực sự hiển thị trên màn hình — giao giữa viewport
  /// (`mStartIndex..mStopIndex`, có thể trỏ vào vùng tương lai) và dữ liệu
  /// thật (`0..mItemCount-1`). Luôn nằm trong `[0, mItemCount-1]` — an toàn
  /// để dùng làm index vào `datas!`. Dùng cho MỌI thứ phải phản ánh đúng
  /// "nến nào đang thấy trên màn hình": high/low nến (`mMainHighMaxValue`/
  /// `mMainMaxIndex`, dùng bởi `drawMaxAndMin`), volume, secondary, và
  /// candle dùng cho label header (`drawText`). KHÔNG dùng
  /// [mRealStartIndex]/[mRealStopIndex] (rộng hơn) cho các mục đích này —
  /// xem giải thích ở đó.
  int mVisibleStartIndex = 0, mVisibleStopIndex = 0;

  /// Vùng nến THẬT cần quét để có đủ dữ liệu nguồn cho các đường bị dịch
  /// (vd Ichimoku: Span A/B dịch tới trước, Chikou dịch lùi `futureShift`
  /// nến) — rộng hơn [mVisibleStartIndex]/[mVisibleStopIndex] thêm
  /// `mFutureSlots` mỗi phía. CHỈ dùng cho: (a) draw loop main chart (cần đủ
  /// nến nguồn để đường dịch vẽ được vào vùng đang hiển thị), (b) quét phần
  /// "margin" trong `calculateValue()` để lấy đóng góp Y-range của riêng các
  /// đường bị dịch. KHÔNG dùng cho high/low nến, volume, secondary, hay bất
  /// cứ chỗ nào cần "nến đang thực sự hiển thị" — nến trong vùng margin có
  /// thể hoàn toàn nằm ngoài màn hình.
  int mRealStartIndex = 0, mRealStopIndex = 0;
  double mMainMaxValue = double.minPositive, mMainMinValue = double.maxFinite;
  double mVolMaxValue = double.minPositive, mVolMinValue = double.maxFinite;
  double mTranslateX = double.minPositive;
  int mMainMaxIndex = 0, mMainMinIndex = 0;
  double mMainHighMaxValue = double.minPositive,
      mMainLowMinValue = double.maxFinite;
  int mItemCount = 0;

  /// Số slot "tương lai" (chưa có nến) cần chừa bên phải nến cuối, do main
  /// indicator nào đó cần dịch tới trước để vẽ đúng (vd Ichimoku — xem
  /// `MainIndicator.futureShift`). `0` khi không có indicator nào yêu cầu →
  /// mọi tính toán bên dưới thu gọn về đúng hành vi cũ, không ảnh hưởng
  /// chart không dùng indicator loại này.
  int mFutureSlots = 0;
  double mDataLen = 0.0; // the data occupies the total length of the screen
  final KChartStyle chartStyle;
  late double mPointWidth;
  List<String> mFormats = [yyyy, '-', mm, '-', dd, ' ', hour24Padded, ':', nn];

  /// Giá trị padding phải tối đa (px tại [referenceChartWidth]). Thực tế qua [_effectiveRightPaddingPx].
  double xFrontPadding;

  /// base dimension
  final BaseDimension baseDimension;

  /// constructor BaseChartPainter
  ///
  BaseChartPainter(
    this.chartStyle, {
    this.datas,
    required this.scaleX,
    required this.scaleY,
    required this.scrollX,
    required this.isLongPress,
    required this.selectX,
    required this.xFrontPadding,
    required this.baseDimension,
    required this.priceAxisWidthCache,
    required this.timeTickPlanner,
    this.isOnTap = false,
    this.offsetY = 0.0,
    this.mainIndicators = const [],
    this.volHidden = false,
    this.isTapShowInfoDialog = false,
    this.secondaryIndicators = const [],
    this.isLine = false,
  }) {
    mItemCount = datas?.length ?? 0;
    mPointWidth = chartStyle.pointWidth;
    mTopPadding =
        chartStyle.topPadding +
        baseDimension.totalLabelHeight; // space to display text of main chart
    mBottomPadding = chartStyle.bottomPadding;
    mChildPadding = chartStyle.childPadding;
    mGridRows = chartStyle.gridRows;
    mGridColumns = chartStyle.gridColumns;
    for (final ind in mainIndicators) {
      if (ind.futureShift > mFutureSlots) mFutureSlots = ind.futureShift;
    }
    mDataLen = (mItemCount + mFutureSlots) * mPointWidth;
    initFormats();
  }

  /// init format time
  void initFormats() {
    if (mItemCount < 2) {
      mFormats =
          chartStyle.dateTimeFormat ??
          [yyyy, '-', mm, '-', dd, ' ', hour24Padded, ':', nn];
      return;
    }

    int firstTime = datas!.first.time ?? 0;
    int secondTime = datas![1].time ?? 0;
    int time = (secondTime - firstTime) ~/ 1000;

    if (time >= 24 * 60 * 60) {
      // daily or monthly line
      mFormats =
          chartStyle.dateTimeFormat ??
          (time >= 24 * 60 * 60 * 28 ? [yy, '-', mm] : [yy, '-', mm, '-', dd]);
    } else {
      // hour/minute line
      mFormats =
          chartStyle.dateTimeFormat ??
          [mm, '-', dd, ' ', hour24Padded, ':', nn];
    }
    // mGridColumns không còn quyết định số lượng/label trục thời gian nữa —
    // xem [_updateTimeTicks]/`TimeTickPlanner` (CHART_AXES.md §5). `mFormats`
    // ở đây chỉ còn phục vụ label crosshair (`getDate` trong `ChartPainter`).
  }

  /// paint chart
  @override
  void paint(Canvas canvas, Size size) {
    // §7.8 — layout pass đầu tiên / animation collapse có thể giao size 0.
    // Vẽ garbage vào Rect âm/0 còn tệ hơn bỏ qua hẳn frame này.
    if (size.width <= 0 || size.height <= 0) return;
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, size.height));
    mDisplayHeight = size.height - mTopPadding - mBottomPadding;
    mWidth = size.width;
    initRect(size);
    calculateValue();
    initChartRenderer();

    canvas.save();
    drawBg(canvas, size);
    drawGrid(canvas);
    if (datas != null && datas!.isNotEmpty) {
      drawChart(canvas, size);
      drawVerticalText(canvas);
      drawDate(canvas, size);

      // Dùng candle phải nhất đang hiển thị (mVisibleStopIndex, clamp về
      // nến thật VÀ trong viewport — mStopIndex có thể trỏ vào vùng tương
      // lai, mRealStopIndex rộng hơn viewport nên KHÔNG dùng ở đây) → label
      // MA/VOL/secondary cập nhật theo vị trí scroll, không cố định ở nến cuối
      drawText(canvas, getItem(mVisibleStopIndex), chartStyle.space);
      drawMaxAndMin(canvas);
      drawNowPrice(canvas);

      if (isLongPress || (isTapShowInfoDialog && isOnTap)) {
        drawCrossLineText(canvas, size);
      }
    }
    canvas.restore();
  }

  /// init chart renderer
  void initChartRenderer();

  /// draw the background of chart
  void drawBg(Canvas canvas, Size size);

  /// draw the grid of chart
  void drawGrid(Canvas canvas);

  /// draw chart
  void drawChart(Canvas canvas, Size size);

  /// draw vertical text
  void drawVerticalText(Canvas canvas);

  /// draw date
  void drawDate(Canvas canvas, Size size);

  /// draw text
  void drawText(Canvas canvas, KLineEntity data, double x);

  /// draw maximum and minimum values
  void drawMaxAndMin(Canvas canvas);

  /// draw the current price
  void drawNowPrice(Canvas canvas);

  /// draw cross line
  void drawCrossLine(Canvas canvas, Size size);

  /// draw text of the cross line
  void drawCrossLineText(Canvas canvas, Size size);

  /// init the rectangle box to draw chart
  ///
  /// Layout (CHART_AXES.md §7) — plot bên trái, strip giá bên phải, chia đôi
  /// theo chiều rộng bởi [mPlotWidth]/[priceAxisWidth]; dọc (top → bottom)
  /// trong khối plot:
  ///   mMainRect             — candles + main indicators
  ///   mVolRect              — vol panel (nếu volHidden = false)
  ///   mSecondaryRectList[i] — mỗi secondary indicator 1 panel
  ///   mDateRect             — trục thời gian (đáy cùng, rộng = mPlotWidth — R1)
  ///   mPriceAxisRect        — cả cột bên phải, cao bằng main+vol+secondary
  ///   mCornerRect           — ô chết dưới-phải, giao strip giá × trục thời gian
  void initRect(Size size) {
    // §7.1: dùng width đã tính từ frame TRƯỚC (xem [priceAxisWidth] doc) —
    // rồi cập nhật lại cho frame sau trong `ChartPainter.initChartRenderer`
    // khi đã biết label rộng bao nhiêu.
    mPlotWidth = max(1.0, mWidth - priceAxisWidth);

    double volHeight = baseDimension.mVolumeHeight;
    double secondaryHeight = baseDimension.mSecondaryHeight;

    double mainHeight = mDisplayHeight;
    mainHeight -= volHeight;
    mainHeight -= baseDimension.totalSecondaryHeight;
    // Nhường mPaddingMainChild cho gap giữa main và vol — main chart ngắn hơn,
    // vol chart vẫn đủ chiều cao.
    if (!volHidden) mainHeight -= mPaddingMainChild;

    mMainRect = Rect.fromLTRB(
      0,
      mTopPadding,
      mPlotWidth,
      mTopPadding + mainHeight,
    );

    if (!volHidden) {
      mVolRect = Rect.fromLTRB(
        0,
        mMainRect.bottom + mChildPadding + mPaddingMainChild,
        mPlotWidth,
        mMainRect.bottom + mPaddingMainChild + volHeight,
      );
    } else {
      mVolRect = null;
    }

    final double secondaryTop = (mVolRect ?? mMainRect).bottom;

    mSecondaryRectList.clear();
    for (int i = 0; i < secondaryIndicators.length; ++i) {
      mSecondaryRectList.add(
        RenderRect(
          Rect.fromLTRB(
            0,
            secondaryTop + i * secondaryHeight + mChildPadding,
            mPlotWidth,
            secondaryTop + i * secondaryHeight + secondaryHeight,
          ),
        ),
      );
    }

    // Date rect ở đáy cùng — dưới panel cuối (vol/secondary) hoặc main nếu cả 2 ẩn.
    // R1: rộng bằng đúng mPlotWidth, cùng x origin với plot — KHÔNG full mWidth.
    final double dateTop = mSecondaryRectList.isNotEmpty
        ? mSecondaryRectList.last.mRect.bottom
        : (mVolRect ?? mMainRect).bottom;
    mDateRect = Rect.fromLTRB(0, dateTop, mPlotWidth, dateTop + mBottomPadding);

    // R2: strip giá cao bằng đúng khối plot (main→đáy panel cuối), cùng y
    // origin — KHÔNG kéo dài xuống hết totalH (phần dưới là mCornerRect).
    mPriceAxisRect = Rect.fromLTRB(mPlotWidth, mMainRect.top, mWidth, dateTop);
    mCornerRect = Rect.fromLTRB(
      mPlotWidth,
      mDateRect.top,
      mWidth,
      mDateRect.bottom,
    );
  }

  /// calculate values
  void calculateValue() {
    mTimeTicks = [];
    if (datas == null) return;
    if (datas!.isEmpty) return;
    maxScrollX = getMinTranslateX().abs();
    setTranslateXFromScrollX(scrollX);
    mStartIndex = indexOfTranslateX(xToTranslateX(0));
    // mPlotWidth, không phải mWidth — cạnh phải thật của khối plot (§7.1);
    // dùng mWidth ở đây sẽ tính dư index vào phần bị strip giá che khuất,
    // làm lệch auto-scale giá (§6.2 đọc `firstVisible..lastVisible`).
    mStopIndex = indexOfTranslateX(xToTranslateX(mPlotWidth));
    // mStartIndex có thể vượt mItemCount-1 khi cả viewport nằm trong vùng
    // tương lai (zoom sâu + scroll hết cỡ, xem mFutureSlots) — clamp để giữ
    // đúng cam kết "safe index" của field public này.
    currentStartIndex = min(max(mStartIndex, 0), mItemCount - 1);

    // mStartIndex/mStopIndex có thể trỏ vào vùng tương lai (> mItemCount-1)
    // khi có indicator dùng mFutureSlots (vd Ichimoku).
    mVisibleStartIndex = max(mStartIndex, 0);
    mVisibleStopIndex = min(mStopIndex, mItemCount - 1);
    mRealStartIndex = max(0, mStartIndex - mFutureSlots);
    mRealStopIndex = min(mStopIndex + mFutureSlots, mItemCount - 1);
    _updateTimeTicks();

    for (int i = mRealStartIndex; i <= mRealStopIndex; i++) {
      var item = datas![i];
      if (i >= mVisibleStartIndex && i <= mVisibleStopIndex) {
        getMainMaxMinValue(item, i);
        if (mVolRect != null) getVolMaxMinValue(item);
        for (int idx = 0; idx < mSecondaryRectList.length; ++idx) {
          getSecondaryMaxMinValue(idx, item);
        }
      } else {
        // Nến trong phần "margin" (ngoài viewport, chỉ có mặt để cấp dữ liệu
        // nguồn cho đường bị dịch) — CHỈ những main indicator có futureShift
        // > 0 mới có thể có phần vẽ dịch rơi vào vùng đang hiển thị, nên chỉ
        // chúng mới được góp vào Y-range ở đây. Không đụng tới high/low nến
        // (mMainHighMaxValue/mMainMaxIndex), volume, hay secondary — những
        // thứ đó không bị dịch nên nến ngoài viewport không liên quan.
        for (final ind in mainIndicators) {
          if (ind.futureShift <= 0) continue;
          final value = ind.getMaxMinValue(item, mMainMinValue, mMainMaxValue);
          mMainMinValue = min(mMainMinValue, value.$1);
          mMainMaxValue = max(mMainMaxValue, value.$2);
        }
      }
    }
  }

  /// Chọn tick trục thời gian cho frame hiện tại (CHART_AXES.md §5) và chiếu
  /// sang toạ độ màn hình bằng đúng 1 hàm transform đang dùng cho nến/lưới
  /// (`translateXtoX(getX(index))`) — không tự bịa hệ toạ độ riêng (I2/I6).
  ///
  /// Kế hoạch chọn tick (`TimeTickPlanner`) được cache tĩnh theo
  /// `(barSpacing, số nến, interval, format)` nên KHÔNG rebuild mỗi frame pan —
  /// chỉ lọc lại theo PIXEL mỗi lần, rẻ vì kế hoạch vốn đã ngắn (đóng gói
  /// theo MIN_GAP_X).
  ///
  /// Lọc đúng theo §5.2 "per-frame projection": chỉ giữ tick có `x` thật sự
  /// nằm trong `[0, mPlotWidth]` (R1 — trục thời gian rộng bằng plot, không
  /// phải cả mWidth, xem §7). KHÔNG lọc theo margin index (`mStartIndex±1`)
  /// — 1 index dư ra khi barSpacing lớn có thể ứng với hàng chục px NGOÀI
  /// màn hình, và `drawDate` chỉ kẹp TEXT (không kẹp gridline, đúng I6) nên
  /// 1 tick off-screen lọt qua sẽ bị kẹp dính cứng vào mép trái/phải — trông
  /// như "2 mốc bị hardcode" dù thật ra chỉ là tick sai vị trí lọt lưới.
  void _updateTimeTicks() {
    if (datas == null || datas!.isEmpty || mItemCount == 0) return;

    final double barSpacing = mPointWidth * scaleX;
    final int intervalMs = detectIntervalMs(datas!);
    final List<TimeTick> plan = timeTickPlanner.getOrBuild(
      candles: datas!,
      barSpacing: barSpacing,
      intervalMs: intervalMs,
      forcedFormat: chartStyle.dateTimeFormat,
    );

    final ticks = <({int index, double x, String label})>[];
    for (final t in plan) {
      if (t.index < 0 || t.index >= mItemCount) continue;
      final double x = translateXtoX(getX(t.index));
      if (x < 0 || x > mPlotWidth) continue;
      ticks.add((index: t.index, x: x, label: t.label));
    }

    if (ticks.isEmpty) {
      // Fallback B (§5.2) — kế hoạch không có tick nào rơi vào viewport hiện
      // tại (vd zoom rất sâu trên dataset nhỏ): vẫn hiện đúng 1 tick tại nến
      // giữa màn hình, trục không bao giờ trống.
      final int mid = indexOfTranslateX(
        xToTranslateX(mPlotWidth / 2),
      ).clamp(0, mItemCount - 1);
      ticks.add((
        index: mid,
        x: translateXtoX(getX(mid)),
        label: labelForCandle(
          datas![mid],
          forcedFormat: chartStyle.dateTimeFormat,
        ),
      ));
    }

    mTimeTicks = ticks;
  }

  /// max/min cho panel volume.
  void getVolMaxMinValue(KLineEntity item) {
    final ma5 = item.MA5Volume ?? 0;
    final ma10 = item.MA10Volume ?? 0;
    mVolMaxValue = max(mVolMaxValue, max(item.vol, max(ma5, ma10)));
    mVolMinValue = min(mVolMinValue, item.vol);
  }

  /// compute maximum and minimum value
  void getMainMaxMinValue(KLineEntity item, int i) {
    double maxPrice = item.high;
    double minPrice = item.low;
    for (int i = 0; i < mainIndicators.length; ++i) {
      final value = mainIndicators[i].getMaxMinValue(item, minPrice, maxPrice);
      minPrice = value.$1;
      maxPrice = value.$2;
    }

    mMainMaxValue = max(mMainMaxValue, maxPrice);
    mMainMinValue = min(mMainMinValue, minPrice);

    if (mMainHighMaxValue < item.high) {
      mMainHighMaxValue = item.high;
      mMainMaxIndex = i;
    }
    if (mMainLowMinValue > item.low) {
      mMainLowMinValue = item.low;
      mMainMinIndex = i;
    }

    if (isLine) {
      mMainMaxValue = max(mMainMaxValue, item.close);
      mMainMinValue = min(mMainMinValue, item.close);
    }
  }

  // compute maximum and minimum of secondary value
  void getSecondaryMaxMinValue(int index, KLineEntity item) {
    SecondaryIndicator indicator = secondaryIndicators[index];
    var (minValue, maxValue) = indicator.getMaxMinValue(
      item,
      mSecondaryRectList[index].mMinValue,
      mSecondaryRectList[index].mMaxValue,
    );
    // Đảm bảo mọi đường tham chiếu ngang (vd 20/80 của StochRSI) luôn nằm
    // trong range hiển thị, không phụ thuộc từng indicator tự chép logic này
    // trong getMaxMinValue của nó.
    for (final refValue in indicator.referenceValues) {
      minValue = min(minValue, refValue);
      maxValue = max(maxValue, refValue);
    }
    mSecondaryRectList[index].mMinValue = minValue;
    mSecondaryRectList[index].mMaxValue = maxValue;
  }

  // translate x
  double xToTranslateX(double x) => -mTranslateX + x / scaleX;

  int indexOfTranslateX(double translateX) =>
      _indexOfTranslateX(translateX, 0, mItemCount + mFutureSlots - 1);

  /// Using binary search for the index of the current value
  int _indexOfTranslateX(double translateX, int start, int end) {
    if (end == start || end == -1) {
      return start;
    }
    if (end - start == 1) {
      double startValue = getX(start);
      double endValue = getX(end);
      return (translateX - startValue).abs() < (translateX - endValue).abs()
          ? start
          : end;
    }
    int mid = start + (end - start) ~/ 2;
    double midValue = getX(mid);
    if (translateX < midValue) {
      return _indexOfTranslateX(translateX, start, mid);
    } else if (translateX > midValue) {
      return _indexOfTranslateX(translateX, mid, end);
    } else {
      return mid;
    }
  }

  /// Get x coordinate based on index
  /// + mPointWidth / 2 to prevent the first and last K-line from displaying incorrectly
  /// @param position index value
  double getX(int position) => position * mPointWidth + mPointWidth / 2;

  KLineEntity getItem(int position) => datas![position];

  /// Timestamp tại [index] — ngoại suy tuyến tính (`lastTime + k*interval`)
  /// cho vùng tương lai (`index >= mItemCount`, xem [mFutureSlots]). Đủ cho
  /// thị trường 24/7 (crypto); KHÔNG xử lý lịch phiên nghỉ (chứng khoán).
  int timeAt(int index) {
    if (index < mItemCount) return datas![index].time ?? 0;
    final lastTime = datas![mItemCount - 1].time ?? 0;
    final prevTime = mItemCount >= 2
        ? (datas![mItemCount - 2].time ?? lastTime)
        : lastTime;
    final interval = lastTime - prevTime;
    return lastTime + (index - mItemCount + 1) * interval;
  }

  /// scrollX convert to TranslateX
  void setTranslateXFromScrollX(double scrollX) =>
      mTranslateX = scrollX + getMinTranslateX();

  /// Chiều rộng tham chiếu (logical px): tại đây [xFrontPadding] = giá trị đầy đủ.
  /// Chart hẹp hơn → padding phải giảm tỷ lệ (fix khoảng trống ~100px cố định khi resize).
  static const double referenceChartWidth = 375.0;

  /// Padding phải thực tế (screen px).
  /// Ví dụ `xFrontPadding=100`: width 375→100px, 250→~67px, 187→~50px; width ≥375 giữ 100px.
  static double effectiveRightPaddingPx(
    double xFrontPadding,
    double chartWidth,
  ) {
    if (chartWidth <= 0) return xFrontPadding;
    final ratio = chartWidth / referenceChartWidth;
    return xFrontPadding * (ratio < 1.0 ? ratio : 1.0);
  }

  double get _effectiveRightPaddingPx =>
      effectiveRightPaddingPx(xFrontPadding, mPlotWidth);

  /// get the minimum value of translation
  double getMinTranslateX() {
    // paddingData: px → data space (/ scaleX) để gap màn hình ≈ _effectiveRightPaddingPx khi pinch zoom.
    // mPlotWidth, không phải mWidth — nến cuối phải cách MÉP PLOT (không phải
    // mép strip giá) đúng khoảng padding này (§7.1).
    final paddingData = _effectiveRightPaddingPx / scaleX;
    var x = -mDataLen + mPlotWidth / scaleX - mPointWidth / 2 - paddingData;
    return x >= 0 ? 0.0 : x;
  }

  /// calculate the value of x after long pressing and convert to [index]
  ///
  /// Clamp về [mVisibleStartIndex]/[mVisibleStopIndex] (nến thật ĐANG HIỂN
  /// THỊ) — không cho chọn vào vùng tương lai trống, cũng không cho chọn
  /// nến "margin" ngoài viewport (xem [mRealStartIndex]), vì crosshair/
  /// tooltip cần 1 `KLineEntity` thật VÀ đang thấy trên màn hình.
  int calculateSelectedX(double selectX) {
    int mSelectedIndex = indexOfTranslateX(xToTranslateX(selectX));
    if (mSelectedIndex < mVisibleStartIndex) {
      mSelectedIndex = mVisibleStartIndex;
    }
    if (mSelectedIndex > mVisibleStopIndex) {
      mSelectedIndex = mVisibleStopIndex;
    }
    return mSelectedIndex;
  }

  /// translateX is converted to X in view
  double translateXtoX(double translateX) =>
      (translateX + mTranslateX) * scaleX;

  /// define text style — fallback mặc định, `ChartPainter` override để dùng
  /// `chartColors.candleStyle.textStyle`.
  TextStyle getTextStyle(Color color) {
    return TextStyle(fontSize: 10.0, color: color);
  }

  @override
  bool shouldRepaint(BaseChartPainter oldDelegate) {
    return oldDelegate.datas != datas ||
        oldDelegate.scaleX != scaleX ||
        oldDelegate.scrollX != scrollX ||
        oldDelegate.isLongPress != isLongPress ||
        oldDelegate.selectX != selectX ||
        oldDelegate.isOnTap != isOnTap ||
        oldDelegate.offsetY != offsetY ||
        oldDelegate.scaleY != scaleY ||
        oldDelegate.volHidden != volHidden ||
        oldDelegate.isLine != isLine ||
        oldDelegate.mainIndicators != mainIndicators ||
        oldDelegate.secondaryIndicators != secondaryIndicators;
  }
}

/// Render Rectangle
class RenderRect {
  Rect mRect;
  double mMaxValue = double.minPositive, mMinValue = double.maxFinite;

  RenderRect(this.mRect);
}
