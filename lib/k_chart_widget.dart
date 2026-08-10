import 'dart:async';
import 'package:flutter/material.dart';
import 'package:k_chart_jk/entity/index.dart';
import 'package:k_chart_jk/indicator/indicator_template.dart';
import 'package:k_chart_jk/renderer/index.dart';
import 'package:k_chart_jk/k_chart_scale_state.dart';
import 'package:k_chart_jk/renderer/k_chart_controller.dart';
import 'package:k_chart_jk/utils/index.dart';
import 'renderer/base_dimension.dart';

class TimeFormat {
  static const List<String> yearMonthDay = [yyyy, '-', mm, '-', dd];
  static const List<String> yearMonthDayWithHour = [
    yyyy,
    '-',
    mm,
    '-',
    dd,
    ' ',
    hour24Padded,
    ':',
    nn,
  ];
}

typedef WidgetDetailBuilder = Widget Function(KLineEntity entity);

/// Gọi khi user kết thúc zoom; [KChartScaleState.scaleX] nằm trong [KChartWidget.minScale]–[KChartWidget.maxScale].
typedef OnChartScaleChanged = void Function(KChartScaleState scale);

class KChartWidget extends StatefulWidget {
  final List<KLineEntity>? datas;
  final List<MainIndicator> mainIndicators;

  /// Ẩn panel volume. Khi `true`, `BaseDimension.mVolumeHeight = 0` và
  /// `BaseChartPainter.mVolRect = null` — `VolRenderer` không được tạo.
  final bool volHidden;
  final List<SecondaryIndicator> secondaryIndicators;

  ///SecondaryState { MACD, KDJ, RSI, WR, CCI }
  // final Function()? onSecondaryTap;
  final bool isLine;
  final bool
  isTapShowInfoDialog; //Whether to enable click to display detailed data
  final bool hideGrid;
  final bool showNowPrice;
  final bool showInfoDialog;
  final bool materialInfoDialog; // Material Style Information Popup

  /// Ép format nhãn trục thời gian + crosshair, dùng cho MỌI tick bất kể
  /// weight (bỏ qua thuật toán thích ứng ở CHART_AXES.md §5.3). `null`
  /// (mặc định) = giữ nguyên hành vi thích ứng — format tự đổi theo mức zoom.
  /// Tương đương set [KChartStyle.dateTimeFormat]; nếu cả hai đều được set,
  /// [KChartStyle.dateTimeFormat] thắng (xem `_effectiveChartStyle`).
  final List<String>? timeFormat;
  final double mBaseHeight;
  final double? mSecondaryHeight;

  // It will be called when the screen scrolls to the end.
  // If true, it will be scrolled to the end of the right side of the screen.
  // If it is false, it will be scrolled to the end of the left side of the screen.
  final Function(bool)? onLoadMore;

  final int fixedLength;
  final int flingTime;
  final double flingRatio;
  final Curve flingCurve;
  final Function(bool)? isOnDrag;
  final KChartColors chartColors;
  final KChartStyle chartStyle;
  final VerticalTextAlignment verticalTextAlignment;
  final bool isTrendLine;
  /// Padding phải sau nến cuối (px tại chart ≥375px). Chart hẹp hơn tự co — xem [BaseChartPainter.effectiveRightPaddingPx].
  final double xFrontPadding;
  final WidgetDetailBuilder detailBuilder;
  /// Giới hạn zoom ngang (pinch) và clamp [KChartScaleState.scaleX] khi lưu/khôi phục.
  final double minScale;
  final double maxScale;
  final double? livePrice;

  final KChartController? controller;
  final bool isLoadingMore;

  /// Widget hiển thị như watermark ở giữa vùng main chart (vd: SvgPicture.asset(...))
  final Widget? backgroundLogo;

  /// Độ trong suốt của backgroundLogo (0.0 = ẩn hoàn toàn, 1.0 = hiện đầy đủ)
  final double backgroundLogoOpacity;

  /// Callback khi pan dọc vượt qua clamp boundary của offsetY (50%).
  /// delta > 0: drag xuống quá biên dưới; delta < 0: drag lên quá biên trên.
  /// Parent có thể dùng để forward sang outer ScrollController (handoff).
  final ValueChanged<double>? onVerticalOverscroll;

  /// Scale đã lưu — truyền lại khi đổi timeframe; `scaleX` clamp theo [minScale]/[maxScale].
  final KChartScaleState? chartScale;

  /// Kết thúc pinch / scaleY / zoom controller / double-tap reset scaleY.
  final OnChartScaleChanged? onChartScaleChanged;

  const KChartWidget(
    this.datas,
    this.chartStyle,
    this.chartColors, {
    required this.detailBuilder,
    required this.isTrendLine,
    this.livePrice,
    this.xFrontPadding = 100,
    this.mainIndicators = const [],
    this.secondaryIndicators = const [],
    // this.onSecondaryTap,
    this.volHidden = false,
    this.isLine = false,
    this.isTapShowInfoDialog = false,
    this.hideGrid = false,
    this.showNowPrice = true,
    this.showInfoDialog = true,
    this.materialInfoDialog = true,
    this.timeFormat,
    this.onLoadMore,
    this.fixedLength = 2,
    this.flingTime = 600,
    this.flingRatio = 0.5,
    this.flingCurve = Curves.decelerate,
    this.isOnDrag,
    this.verticalTextAlignment = VerticalTextAlignment.right,
    this.mBaseHeight = 360,
    this.mSecondaryHeight,
    this.controller,
    this.minScale = 0.2,
    this.maxScale = 2.2,
    this.isLoadingMore = false,
    this.backgroundLogo,
    this.backgroundLogoOpacity = 1,
    this.onVerticalOverscroll,
    this.chartScale,
    this.onChartScaleChanged,
    super.key,
  });

  @override
  State<KChartWidget> createState() => _KChartWidgetState();
}

class _KChartWidgetState extends State<KChartWidget>
    with TickerProviderStateMixin {
  // broadcast: StreamBuilder trong _buildInfoDialog có thể rebuild mà không lỗi
  // "Stream has already been listened to" (single-subscription stream).
  final StreamController<InfoWindowEntity?> mInfoWindowStream =
      StreamController<InfoWindowEntity?>.broadcast();
  double mScaleX = 1.0, mScrollX = 0.0, mSelectX = 0.0;
  // mOffsetY: độ dịch chuyển Y của chart (pan dọc), reset về 0 khi double tap
  double mScaleY = 1.0, mOffsetY = 0.0;

  // Cache bề rộng strip trục giá + planner tick trục thời gian — sở hữu ở
  // ĐÂY (field bền qua các lần build, giống mScaleX/mScrollX), KHÔNG static
  // như trước, để nhiều KChartWidget vẽ đồng thời không tranh chấp/rò rỉ vào
  // nhau (xem doc PriceAxisWidthCache/TimeTickPlanner).
  final PriceAxisWidthCache _priceAxisWidthCache = PriceAxisWidthCache();
  final TimeTickPlanner _timeTickPlanner = TimeTickPlanner();
  double _scaleYDragStart = 0.0;
  AnimationController? _controller;
  Animation<double>? aniX;

  //For TrendLine
  List<TrendLine> lines = [];
  double? changeinXposition;
  double? changeinYposition;
  double mSelectY = 0.0;
  bool waitingForOtherPairofCords = false;
  bool enableCordRecord = false;

  double getMinScrollX() {
    return mScaleX;
  }

  // Giới hạn offsetY: giữ tối thiểu 50% chart content trong view ở mọi scaleY
  // Công thức: |offsetY| ≤ baseHeight * scaleY / 2
  // Tại |offsetY| = max, đúng 1 nửa content height bị đẩy ra khỏi viewport.
  //   scaleY = 1   → ±0.5 * baseHeight (1/2 chart có thể trượt khỏi view)
  //   scaleY = 0.3 → ±0.15 * baseHeight (content nhỏ, pan range nhỏ tương ứng)
  //   scaleY = 5   → ±2.5 * baseHeight (zoom in nhiều → pan range lớn)
  double _clampOffsetY(double value) {
    final double maxOffset = widget.mBaseHeight * mScaleY / 2;
    return value.clamp(-maxOffset, maxOffset);
  }

  double _lastScale = 1.0;
  double _gestureScaleXAtStart = 1.0;
  double _gestureScaleYAtStart = 1.0;
  bool _suppressScaleCallback = false;
  static const double _minScaleY = 0.3;
  static const double _maxScaleY = 5.0;
  bool isScale = false, isDrag = false, isLongPress = false, isOnTap = false;
  // true khi gesture bắt đầu trong strip trục giá bên phải (width = _priceAxisWidthCache.value) → drag dọc = scaleY
  bool _isScaleYGesture = false;
  // true khi drag bắt đầu trong lúc crosshair đang hiển thị → drag di chuyển crosshair thay vì scroll
  bool _dragStartedInTapMode = false;
  // true khi gesture bắt đầu TRONG mMainRect. Khi false (vol/secondary/date),
  // chart không xử lý scroll/scale — forward delta Y cho outer scroll qua
  // `onVerticalOverscroll`, parent tự quyết định cuộn theo.
  bool _gestureInMain = true;

  // Chặn spam onLoadMore khi data chưa lấp đầy chiều rộng chart: chỉ request
  // lại khi độ dài data thực sự thay đổi so với lần request gần nhất, tránh
  // gọi trùng ở mỗi rebuild không liên quan (đổi style, đổi theme, ...) trong
  // lúc chờ isLoadingMore được parent cập nhật ngược lại (thường bất đồng bộ).
  int? _narrowLoadRequestedForLength;

  @override
  void dispose() {
    mInfoWindowStream.sink.close();
    mInfoWindowStream.close();
    _controller?.dispose();
    widget.controller?.removeListener(_onController);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onController);
    _restoreChartScaleFromWidget(reclampScrollAfterLayout: true);
    _maybeLoadMoreForNarrowData();
  }

  @override
  void didUpdateWidget(KChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _compensateScrollOnDataChange(oldWidget);
    if (widget.minScale != oldWidget.minScale ||
        widget.maxScale != oldWidget.maxScale) {
      mScaleX = mScaleX.clamp(widget.minScale, widget.maxScale);
      _lastScale = mScaleX;
    }
    if (widget.chartScale != null &&
        widget.chartScale != oldWidget.chartScale) {
      _restoreChartScaleFromWidget(reclampScrollAfterLayout: true);
    }
    _maybeLoadMoreForNarrowData();
  }

  // Data ban đầu (hoặc sau khi load thêm) có thể chưa đủ lấp đầy chiều rộng
  // chart (ChartPainter.maxScrollX <= 0). Các trigger onLoadMore khác chỉ bắn
  // từ gesture (pinch/scroll/fling) nên nếu user chưa tương tác gì thì sẽ
  // không bao giờ được gọi. Check lại đây sau mỗi frame để tự động load tiếp
  // cho tới khi đủ full-width, giống hệt cơ chế đã dùng khi pinch zoom out.
  void _maybeLoadMoreForNarrowData() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.isLoadingMore || widget.onLoadMore == null) return;
      final data = widget.datas;
      if (data == null || data.isEmpty) return;
      if (ChartPainter.maxScrollX > 0) return;
      if (_narrowLoadRequestedForLength == data.length) return;
      _narrowLoadRequestedForLength = data.length;
      widget.onLoadMore!(true);
    });
  }

  KChartScaleState get _currentChartScale => KChartScaleState(
        scaleX: mScaleX,
        scaleY: mScaleY,
        scrollX: mScrollX,
      ).clampedTo(minScale: widget.minScale, maxScale: widget.maxScale);

  void _restoreChartScaleFromWidget({bool reclampScrollAfterLayout = false}) {
    final external = widget.chartScale;
    final saved = external?.clampedTo(
      minScale: widget.minScale,
      maxScale: widget.maxScale,
    );
    if (saved == null) return;
    _suppressScaleCallback = true;
    mScaleX = saved.scaleX;
    mScaleY = saved.scaleY.clamp(_minScaleY, _maxScaleY);
    mScrollX = saved.scrollX
        .clamp(0.0, ChartPainter.maxScrollX > 0 ? ChartPainter.maxScrollX : 0.0)
        .toDouble();
    mOffsetY = _clampOffsetY(mOffsetY);
    _lastScale = mScaleX;
    _suppressScaleCallback = false;
    if (reclampScrollAfterLayout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.chartScale != external) return;
        final clamped =
            saved.scrollX.clamp(0.0, ChartPainter.maxScrollX).toDouble();
        if (mScrollX != clamped) {
          mScrollX = clamped;
          setState(() {});
        }
      });
    }
  }

  void _emitChartScaleChanged() {
    if (_suppressScaleCallback || widget.onChartScaleChanged == null) return;
    widget.onChartScaleChanged!(_currentChartScale);
  }

  /// Khi parent push thêm dữ liệu (live tick append nến mới, hoặc lazy-load
  /// prepend nến cũ), `mScrollX` tính theo offset từ biên phải vẫn giữ nguyên
  /// nhưng `getMinTranslateX` tính lại → view sẽ "trôi" khỏi vị trí user
  /// đang xem. Bù lại đây để user giữ đúng vùng candle đang nhìn:
  ///
  ///   - **Append nến mới (live)**: `mScrollX` đại diện khoảng cách tới biên
  ///     phải. Khi append thêm N nến, biên phải tịnh tiến thêm N×pointWidth.
  ///     Để giữ user ở đúng candle cũ, cộng N×pointWidth vào `mScrollX`.
  ///     Ngoại lệ: nếu user đang ở rightmost (mScrollX = 0) → giữ nguyên 0
  ///     để chart auto-follow nến mới (UX TradingView/Binance).
  ///
  ///   - **Prepend nến cũ (lazy-load)**: `getMinTranslateX` tự tính lại đúng
  ///     theo data mới; vị trí view trong data space tự bảo toàn → không cần
  ///     bù `mScrollX`.
  void _compensateScrollOnDataChange(KChartWidget oldWidget) {
    final oldData = oldWidget.datas;
    final newData = widget.datas;
    if (oldData == null || newData == null) return;
    if (oldData.isEmpty || newData.isEmpty) return;
    if (oldData.length == newData.length) return;

    final int diff = newData.length - oldData.length;
    if (diff <= 0) return; // chỉ xử lý append/prepend, không xử lý shrink

    // Append: nến đầu giữ nguyên, nến cuối mới hơn → có nến được thêm ở cuối.
    final bool appended =
        oldData.first.time == newData.first.time &&
        oldData.last.time != newData.last.time;
    if (!appended) return; // prepend hoặc replace toàn bộ → bỏ qua

    // User đang ở rightmost → auto-follow nến mới, không bù.
    if (mScrollX <= 0.0) return;

    mScrollX += diff * widget.chartStyle.pointWidth;
  }

  void _onController() {
    // 1: reset 2: zoom
    if (widget.controller!.action == 1) {
      mScaleX = 1.0;
      mScrollX = 0.0;
      mSelectX = 0.0;
      _lastScale = mScaleX;
      _emitChartScaleChanged();
    } else if (widget.controller!.action == 2) {
      mScaleX = (mScaleX + widget.controller!.zoom).clamp(
        widget.minScale,
        widget.maxScale,
      );
      _lastScale = mScaleX;
      _emitChartScaleChanged();
    }
    notifyChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.datas != null && widget.datas!.isEmpty) {
      mScrollX = mSelectX = 0.0;
      mScaleX = 1.0;
    }
    final BaseDimension baseDimension = BaseDimension(
      mBaseHeight: widget.mBaseHeight,
      mSecondaryHeight: widget.mSecondaryHeight ?? widget.mBaseHeight * .2,
      volHidden: widget.volHidden,
      secondaryIndicators: widget.secondaryIndicators,
      mainIndicators: widget.mainIndicators,
    );
    // `chartStyle.dateTimeFormat` là field thật sự chạy tới time-tick planner
    // + crosshair (BaseChartPainter.initFormats/_updateTimeTicks) — [timeFormat]
    // chỉ là tiện ích ở tầng widget, set hộ field đó khi `chartStyle` chưa tự
    // set. `chartStyle` set trực tiếp luôn thắng nếu cả hai cùng được truyền.
    final KChartStyle effectiveChartStyle =
        widget.chartStyle.dateTimeFormat != null || widget.timeFormat == null
        ? widget.chartStyle
        : KChartStyle(widget.timeFormat, widget.chartStyle.volBarOpacity);
    final bool hasLogo = widget.backgroundLogo != null;
    final painter = ChartPainter(
      effectiveChartStyle,
      widget.chartColors,
      livePrice: widget.livePrice,
      baseDimension: baseDimension,
      lines: List<TrendLine>.of(lines), //For TrendLine
      sink: mInfoWindowStream.sink,
      xFrontPadding: widget.xFrontPadding,
      priceAxisWidthCache: _priceAxisWidthCache,
      timeTickPlanner: _timeTickPlanner,
      isTrendLine: widget.isTrendLine, //For TrendLine
      selectY: mSelectY, //For TrendLine
      datas: widget.datas,
      scaleX: mScaleX,
      scaleY: mScaleY,
      scrollX: mScrollX,
      offsetY: mOffsetY,
      selectX: mSelectX,
      isLongPress: isLongPress,
      isOnTap: isOnTap,
      isTapShowInfoDialog: widget.isTapShowInfoDialog,
      mainIndicators: widget.mainIndicators,
      volHidden: widget.volHidden,
      secondaryIndicators: widget.secondaryIndicators,
      isLine: widget.isLine,
      hideGrid: widget.hideGrid,
      showNowPrice: widget.showNowPrice,
      fixedLength: widget.fixedLength,
      verticalTextAlignment: widget.verticalTextAlignment,
      // khi có logo, background tách thành Container riêng để logo nằm giữa
      skipBg: hasLogo,
    );

    return GestureDetector(
      onTapUp: (details) {
        if (!widget.isTrendLine &&
            painter.isInMainRect(details.localPosition)) {
          // tap-to-toggle: tap lần đầu → hiện crosshair, tap lại → ẩn crosshair
          if (isOnTap) {
            isOnTap = false;
            mInfoWindowStream.sink.add(null);
            notifyChanged();
          } else {
            isOnTap = true;
            if (mSelectX != details.localPosition.dx &&
                widget.isTapShowInfoDialog) {
              mSelectX = details.localPosition.dx;
              notifyChanged();
            }
          }
        }
        if (widget.isTrendLine && !isLongPress && enableCordRecord) {
          enableCordRecord = false;
          Offset p1 = Offset(getTrendLineX(), mSelectY);
          if (!waitingForOtherPairofCords) {
            lines.add(
              TrendLine(p1, Offset(-1, -1), trendLineMax!, trendLineScale!),
            );
          }
          if (waitingForOtherPairofCords) {
            var a = lines.last;
            lines.removeLast();
            lines.add(TrendLine(a.p1, p1, trendLineMax!, trendLineScale!));
            waitingForOtherPairofCords = false;
          } else {
            waitingForOtherPairofCords = true;
          }
          notifyChanged();
        }
      },
      onScaleStart: (details) {
        isScale = true;
        isLongPress = false;
        // lưu trạng thái tap trước khi gesture bắt đầu để quyết định mode drag
        _dragStartedInTapMode = isOnTap;
        if (!isOnTap) isOnTap = false;
        _stopAnimation();
        _lastScale = mScaleX;
        _gestureScaleXAtStart = mScaleX;
        _gestureScaleYAtStart = mScaleY;
        _scaleYDragStart = details.localFocalPoint.dy;
        // xác định scaleY gesture: 1 ngón tay trong strip trục giá thật bên
        // phải (§7.7 "price axis | drag vertical | scale Y") — dùng đúng
        // `priceAxisWidth` đang vẽ (§7.6), không phải xFrontPadding (đó là
        // padding sau nến cuối, không liên quan diện tích strip hiển thị).
        final renderBox = context.findRenderObject() as RenderBox?;
        final width = renderBox?.size.width ?? 0.0;
        final zoneWidth = _priceAxisWidthCache.value;
        _isScaleYGesture =
            details.pointerCount == 1 &&
            details.localFocalPoint.dx > width - zoneWidth;
        // Gesture bắt đầu trong vol/secondary/date → chart không xử lý
        // scroll/scale, chỉ forward delta Y cho outer scroll.
        _gestureInMain = painter.isInMainRect(details.localFocalPoint);
      },
      onScaleUpdate: (details) {
        // Touch ngoài main + 1 ngón:
        //   - dx → vẫn scroll nến X như bình thường.
        //   - dy → forward outer scroll (KHÔNG pan chart Y).
        // Pinch (≥2 ngón) vẫn để chart xử lý scaleX bình thường ở nhánh dưới.
        //
        // Từ khi có strip trục giá riêng (§7), `mMainRect` không còn phủ hết
        // chiều rộng nữa — kéo trên strip (trong hàng main) giờ cũng khiến
        // `isInMainRect` trả false dù đó chính là gesture scaleY hợp lệ.
        // Loại trừ rõ `_isScaleYGesture` ở đây để không bị nhánh này nuốt mất.
        if (!_gestureInMain && !_isScaleYGesture && details.pointerCount < 2) {
          isOnTap = false;
          mScrollX = (mScrollX + details.focalPointDelta.dx / mScaleX)
              .clamp(0.0, ChartPainter.maxScrollX)
              .toDouble();
          final double dy = details.focalPointDelta.dy;
          if (dy != 0 && widget.onVerticalOverscroll != null) {
            widget.onVerticalOverscroll!(dy);
          }
          if (!widget.isLoadingMore &&
              widget.onLoadMore != null &&
              (ChartPainter.maxScrollX <= 0 ||
                  mScrollX >= ChartPainter.maxScrollX * 0.8)) {
            widget.onLoadMore!(true);
          }
          notifyChanged();
          return;
        }
        if (_dragStartedInTapMode &&
            details.pointerCount == 1 &&
            !_isScaleYGesture) {
          // crosshair đang hiển thị → drag di chuyển crosshair theo ngón tay
          mSelectX = details.localFocalPoint.dx;
        } else if (_isScaleYGesture && details.pointerCount == 1) {
          // vùng phải + drag dọc → điều chỉnh scaleY (zoom dọc)
          final double delta = details.localFocalPoint.dy - _scaleYDragStart;
          mScaleY =
              (mScaleY - delta * 0.005).clamp(_minScaleY, _maxScaleY);
          _scaleYDragStart = details.localFocalPoint.dy;
          // Bound của offsetY phụ thuộc vào mScaleY → clamp lại sau khi đổi scaleY
          mOffsetY = _clampOffsetY(mOffsetY);
        } else if (details.scale != 1.0) {
          // 2 ngón tay → zoom scaleX, clamp theo widget.minScale/maxScale
          isOnTap = false;
          mScaleX = (_lastScale * details.scale).clamp(
            widget.minScale,
            widget.maxScale,
          );
        } else {
          // 1 ngón tay drag tự do → scroll X
          // Pan Y chỉ active sau khi user đã scaleY qua vùng Positioned bên phải
          isOnTap = false;
          mScrollX = (mScrollX + details.focalPointDelta.dx / mScaleX)
              .clamp(0.0, ChartPainter.maxScrollX)
              .toDouble();
          if (mScaleY != 1.0) {
            final double dy = details.focalPointDelta.dy;
            final double newOffsetY = mOffsetY + dy;
            final double clampedOffsetY = _clampOffsetY(newOffsetY);
            mOffsetY = clampedOffsetY;
            // Phần delta vượt clamp (chart đã đến biên 50% và user vẫn drag tiếp)
            // → forward cho parent để cuộn outer scrollview
            final double overscroll = newOffsetY - clampedOffsetY;
            if (overscroll != 0 && widget.onVerticalOverscroll != null) {
              widget.onVerticalOverscroll!(overscroll);
            }
          }
          if (!widget.isLoadingMore &&
              widget.onLoadMore != null &&
              (ChartPainter.maxScrollX <= 0 ||
                  mScrollX >= ChartPainter.maxScrollX * 0.8)) {
            widget.onLoadMore!(true);
          }
        }
        notifyChanged();
      },
      onScaleEnd: (details) {
        isScale = false;
        _lastScale = mScaleX;
        if (mScaleX != _gestureScaleXAtStart ||
            mScaleY != _gestureScaleYAtStart) {
          _emitChartScaleChanged();
        }
        // fling X kích hoạt cho mọi drag scroll thường (không phải kéo crosshair),
        // kể cả khi gesture bắt đầu ngoài main vì 1-finger drag ở vol/secondary
        // cũng update mScrollX.
        if (!_dragStartedInTapMode) {
          final velocity = details.velocity.pixelsPerSecond.dx;
          _onFling(velocity);
        }
        _dragStartedInTapMode = false;
        _gestureInMain = true;
        // Sau khi pinch zoom out đến mức tất cả data hiển thị (maxScrollX == 0),
        // cần trigger loadMore vì user không scroll thêm được.
        // maxScrollX chỉ được cập nhật sau paint() nên dùng post-frame callback.
        if (mScaleX != _gestureScaleXAtStart) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (!widget.isLoadingMore &&
                widget.onLoadMore != null &&
                ChartPainter.maxScrollX <= 0) {
              widget.onLoadMore!(true);
            }
          });
        }
      },
      onLongPressStart: (details) {
        isOnTap = false;
        isLongPress = true;
        if ((mSelectX != details.localPosition.dx ||
                mSelectY != details.globalPosition.dy) &&
            !widget.isTrendLine) {
          mSelectX = details.localPosition.dx;
          notifyChanged();
        }
        if (widget.isTrendLine && changeinXposition == null) {
          mSelectX = changeinXposition = details.localPosition.dx;
          mSelectY = changeinYposition = details.globalPosition.dy;
          notifyChanged();
        }
        if (widget.isTrendLine && changeinXposition != null) {
          changeinXposition = details.localPosition.dx;
          changeinYposition = details.globalPosition.dy;
          notifyChanged();
        }
      },
      onLongPressMoveUpdate: (details) {
        if ((mSelectX != details.localPosition.dx ||
                mSelectY != details.globalPosition.dy) &&
            !widget.isTrendLine) {
          mSelectX = details.localPosition.dx;
          mSelectY = details.localPosition.dy;
          notifyChanged();
        }
        if (widget.isTrendLine) {
          mSelectX = mSelectX + (details.localPosition.dx - changeinXposition!);
          changeinXposition = details.localPosition.dx;
          mSelectY =
              mSelectY + (details.globalPosition.dy - changeinYposition!);
          changeinYposition = details.globalPosition.dy;
          notifyChanged();
        }
      },
      onLongPressEnd: (details) {
        isLongPress = false;
        enableCordRecord = true;
        mInfoWindowStream.sink.add(null);
        notifyChanged();
      },
      child: Stack(
        children: [
          // layer 1: background color (luôn render, tách khỏi painter khi có logo)
          if (hasLogo)
            Positioned.fill(
              child: ColoredBox(color: widget.chartColors.bgColor),
            ),
          // layer 2: logo watermark — trên background, dưới chart content
          if (hasLogo)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: widget.mBaseHeight + baseDimension.totalLabelHeight,
              child: IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: widget.backgroundLogoOpacity.clamp(0.0, 1.0),
                    child: widget.backgroundLogo!,
                  ),
                ),
              ),
            ),
          // layer 3: chart content (canvas transparent khi hasLogo)
          CustomPaint(
            size: Size(double.infinity, baseDimension.mDisplayHeight),
            painter: painter,
          ),
          // Vùng scaleY + double-tap reset: width đồng bộ với strip trục giá
          // thật đang vẽ (§7.6/§7.7) — không còn xFrontPadding (đó là padding
          // sau nến cuối, không phải bề rộng trục giá hiển thị).
          // LayoutBuilder chỉ bọc Positioned (không bọc GestureDetector ngoài) để tránh
          // rebuild cả StreamBuilder → lỗi stream single-subscription.
          // TODO: bottom offset giới hạn vùng scaleY chỉ trong main chart
          // nếu muốn gesture phủ toàn bộ thì đổi lại bottom: 0
          Positioned(
            right: 0,
            top: 0,
            bottom:
                baseDimension.mVolumeHeight +
                baseDimension.totalSecondaryHeight +
                widget.chartStyle.bottomPadding,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scaleYZoneWidth = _priceAxisWidthCache.value;
                return GestureDetector(
                  onDoubleTap: () {
                    // double tap vùng phải → reset scaleY và offsetY về mặc định
                    mScaleY = 1.0;
                    mOffsetY = 0.0;
                    _emitChartScaleChanged();
                    notifyChanged();
                  },
                  child: Container(
                    color: Colors.transparent,
                    width: scaleYZoneWidth,
                  ),
                );
              },
            ),
          ),
          if (widget.showInfoDialog) _buildInfoDialog(),
        ],
      ),
    );
  }

  void _stopAnimation({bool needNotify = true}) {
    if (_controller != null && _controller!.isAnimating) {
      _controller!.stop();
      _onDragChanged(false);
      if (needNotify) {
        notifyChanged();
      }
    }
  }

  void _onDragChanged(bool isOnDrag) {
    isDrag = isOnDrag;
    if (widget.isOnDrag != null) {
      widget.isOnDrag!(isDrag);
    }
  }

  void _onFling(double x) {
    _controller = AnimationController(
      duration: Duration(milliseconds: widget.flingTime),
      vsync: this,
    );
    aniX = null;
    aniX = Tween<double>(begin: mScrollX, end: x * widget.flingRatio + mScrollX)
        .animate(
          CurvedAnimation(parent: _controller!.view, curve: widget.flingCurve),
        );
    aniX!.addListener(() {
      mScrollX = aniX!.value;
      if (mScrollX <= 0) {
        mScrollX = 0;
        _stopAnimation();
      } else if (mScrollX >= ChartPainter.maxScrollX) {
        mScrollX = ChartPainter.maxScrollX;
        if (widget.onLoadMore != null) {
          widget.onLoadMore!(false);
        }
        _stopAnimation();
      } else if (!widget.isLoadingMore &&
          widget.onLoadMore != null &&
          (ChartPainter.maxScrollX <= 0 ||
              mScrollX >= ChartPainter.maxScrollX * 0.8)) {
        widget.onLoadMore!(true);
      }
      notifyChanged();
    });
    aniX!.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _onDragChanged(false);
        notifyChanged();
      }
    });
    _controller!.forward();
  }

  void notifyChanged() => setState(() {});

  late List<String> infos;

  Widget _buildInfoDialog() {
    return StreamBuilder<InfoWindowEntity?>(
      stream: mInfoWindowStream.stream,
      builder: (context, snapshot) {
        if ((!isLongPress && !isOnTap) ||
            widget.isLine == true ||
            !snapshot.hasData ||
            snapshot.data?.kLineEntity == null) {
          return const SizedBox();
        }
        KLineEntity entity = snapshot.data!.kLineEntity;
        if (snapshot.data!.isLeft) {
          return Positioned(
            left: 10.0,
            child: widget.detailBuilder.call(entity),
          );
        }
        return Positioned(
          right: 10.0,
          child: widget.detailBuilder.call(entity),
        );
      },
    );
  }
}
