import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:k_chart_jk/k_chart_plus.dart';

import 'bloc/chart_bloc.dart';
import 'bloc/chart_event.dart';
import 'bloc/chart_state.dart';
import 'market/market_env.dart';
import 'market/order_book.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'K Chart JK Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF0B90B)),
        useMaterial3: true,
      ),
      home: BlocProvider(
        create: (_) => ChartBloc(),
        child: const ChartDemoPage(),
      ),
    );
  }
}

// ── Demo page ─────────────────────────────────────────────────────────────────

class _OrderBookItem {
  final OrderBookLevel? level;
  final Color? sideColor;

  /// Max quantity của phía này (từ WS `maxAmount`) — scale độ dài depth bar.
  final double sideMax;
  final bool isSpread;

  _OrderBookItem.row(this.level, this.sideColor, this.sideMax)
    : isSpread = false;
  _OrderBookItem.spread()
    : level = null,
      sideColor = null,
      sideMax = 0,
      isSpread = true;
}

class ChartDemoPage extends StatefulWidget {
  const ChartDemoPage({super.key});

  @override
  State<ChartDemoPage> createState() => _ChartDemoPageState();
}

/// Chỉ giữ state UI/gesture thuần túy (không phải data/business) — mọi thứ
/// còn lại (candle data, indicator, timeframe, live-tick, load-more...) nằm
/// trong [ChartBloc]/[ChartState]. View ở đây chỉ đọc [ChartState] qua
/// [BlocBuilder] và dispatch [ChartEvent], không tự tính toán gì.
class _ChartDemoPageState extends State<ChartDemoPage> {
  final KChartController _controller = KChartController();
  final ScrollController _outerScrollController = ScrollController();

  // Gesture priority cho chart vs outer scroll
  // true sau khi user drag dọc vùng phải chart (scaleY) — kích hoạt chart focused mode
  // → outer scroll bị khoá khi finger chạm chart, chart độc quyền xử lý gesture
  // false khi user double-tap vùng phải để reset scaleY
  bool _scaleYActive = false;
  // true khi finger đang chạm vùng chart
  bool _pointerOnChart = false;
  Offset? _chartPointerDownPos;
  int _chartPointerCount = 0;
  double _chartWidth = 0;
  DateTime? _lastTapTime;
  Offset? _lastTapPos;
  static const double _scaleYZoneWidth = 100.0;
  static const double _scaleYDragThreshold = 8.0;
  static const Duration _doubleTapMaxGap = Duration(milliseconds: 300);
  static const double _doubleTapMaxDistance = 20.0;

  // Cache indicator instance list — ChartState.mainIndicators/secondaryIndicators
  // là getter tạo instance (+ Paint) mới mỗi lần gọi. BlocBuilder rebuild trên
  // MỌI thay đổi state (kể cả livePrice, cập nhật mỗi tick WS không throttle),
  // nên nếu gọi thẳng getter mỗi build sẽ tạo lại toàn bộ indicator dù
  // mainTypes/secondaryTypes không đổi. Cache theo nội dung Set để tái dùng.
  Set<MainIndicatorType>? _cachedMainTypes;
  List<MainIndicator>? _cachedMainIndicators;
  Set<SecondaryIndicatorType>? _cachedSecondaryTypes;
  List<SecondaryIndicator>? _cachedSecondaryIndicators;

  List<MainIndicator> _mainIndicatorsFor(ChartState state) {
    if (_cachedMainIndicators == null ||
        !_setEquals(_cachedMainTypes!, state.mainTypes)) {
      _cachedMainTypes = state.mainTypes;
      _cachedMainIndicators = state.mainIndicators;
    }
    return _cachedMainIndicators!;
  }

  List<SecondaryIndicator> _secondaryIndicatorsFor(ChartState state) {
    if (_cachedSecondaryIndicators == null ||
        !_setEquals(_cachedSecondaryTypes!, state.secondaryTypes)) {
      _cachedSecondaryTypes = state.secondaryTypes;
      _cachedSecondaryIndicators = state.secondaryIndicators;
    }
    return _cachedSecondaryIndicators!;
  }

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  void dispose() {
    _controller.dispose();
    _outerScrollController.dispose();
    super.dispose();
  }

  // ── Chart pointer tracking ─────────────────────────────────────────────────

  bool _inScaleYZone(Offset pos) =>
      _chartWidth > 0 && pos.dx > _chartWidth - _scaleYZoneWidth;

  void _onChartPointerDown(PointerDownEvent e) {
    _chartPointerCount++;
    _chartPointerDownPos = e.localPosition;
    if (!_pointerOnChart) {
      setState(() => _pointerOnChart = true);
    }
    // Double-tap trong scaleY zone → khớp với hành vi reset scaleY của chart
    // → tắt scaleY active mode để outer scroll hoạt động lại
    if (_scaleYActive &&
        _inScaleYZone(e.localPosition) &&
        _lastTapTime != null &&
        _lastTapPos != null &&
        DateTime.now().difference(_lastTapTime!) < _doubleTapMaxGap &&
        (e.localPosition - _lastTapPos!).distance < _doubleTapMaxDistance) {
      setState(() => _scaleYActive = false);
      _lastTapTime = null;
      _lastTapPos = null;
    }
  }

  void _onChartPointerMove(PointerMoveEvent e) {
    if (_scaleYActive || _chartPointerDownPos == null) return;
    // Chỉ active khi: drag bắt đầu trong scaleY zone + vertical-dominant + > threshold
    if (!_inScaleYZone(_chartPointerDownPos!)) return;
    final delta = e.localPosition - _chartPointerDownPos!;
    if (delta.dy.abs() > _scaleYDragThreshold &&
        delta.dy.abs() > delta.dx.abs()) {
      setState(() => _scaleYActive = true);
    }
  }

  void _onChartPointerUp(PointerUpEvent e) {
    // Ghi nhận tap để detect double-tap ở lần down kế tiếp
    if (_chartPointerDownPos != null) {
      final dist = (e.localPosition - _chartPointerDownPos!).distance;
      if (dist < _doubleTapMaxDistance) {
        _lastTapTime = DateTime.now();
        _lastTapPos = e.localPosition;
      } else {
        _lastTapTime = null;
        _lastTapPos = null;
      }
    }
    _releaseChartPointer();
  }

  void _onChartPointerCancel(PointerCancelEvent e) {
    _lastTapTime = null;
    _lastTapPos = null;
    _releaseChartPointer();
  }

  void _releaseChartPointer() {
    _chartPointerCount = (_chartPointerCount - 1).clamp(0, 10);
    if (_chartPointerCount == 0) {
      _chartPointerDownPos = null;
      if (_pointerOnChart) {
        setState(() => _pointerOnChart = false);
      }
    }
  }

  void _onChartVerticalOverscroll(double delta) {
    if (!_outerScrollController.hasClients) return;
    final pos = _outerScrollController.position;
    // Convention: chart pan Y dùng mOffsetY += dy (content theo finger).
    // Scroll Flutter ngược lại: pos.pixels TĂNG = reveal content bên dưới
    // (finger drag UP). Vì vậy phải NEGATE delta khi forward sang outer:
    //   finger drag DOWN → overscroll > 0 → outer pos giảm (reveal content trên)
    //   finger drag UP   → overscroll < 0 → outer pos tăng (reveal content dưới)
    final target = (pos.pixels - delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if (target != pos.pixels) {
      // jumpTo bypass physics → vẫn cuộn được khi outer đang NeverScrollableScrollPhysics
      _outerScrollController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChartBloc, ChartState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: state.isDark
              ? const Color(0xFF0B0E11)
              : Colors.white,
          appBar: AppBar(
            backgroundColor: state.isDark
                ? const Color(0xFF0B0E11)
                : Colors.white,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  MarketEnv.symbol,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: state.isDark ? Colors.white : Colors.black,
                  ),
                ),
                if (state.data.isNotEmpty)
                  Text(
                    // Ưu tiên giá tick WS (thumb/kline) — cùng nguồn với
                    // đường now-price trên chart.
                    '${(state.livePrice ?? state.data.last.close).toStringAsFixed(2)} USDT',
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          (state.livePrice ?? state.data.last.close) >=
                              state.data.last.open
                          ? const Color(0xFF0ECB81)
                          : const Color(0xFFF6465D),
                    ),
                  ),
              ],
            ),
            actions: [
              Row(
                children: [
                  Text(
                    'Depth',
                    style: TextStyle(
                      fontSize: 12,
                      color: state.isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  Switch(
                    value: state.showDepth,
                    onChanged: (v) => context.read<ChartBloc>().add(
                      ChartDepthVisibilityChanged(v),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(
                  state.isDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  color: state.isDark ? Colors.white70 : Colors.black54,
                ),
                onPressed: () =>
                    context.read<ChartBloc>().add(const ChartThemeToggled()),
              ),
            ],
          ),
          body: state.data.isEmpty
              ? _buildEmptyBody(context, state)
              : SingleChildScrollView(
                  controller: _outerScrollController,
                  physics: (_scaleYActive && _pointerOnChart)
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      state.showDepth
                          ? _buildDepthChartSection(context, state)
                          : _buildChart(context, state),
                      const SizedBox(height: 8),
                      _buildControls(context, state),
                      const SizedBox(height: 8),
                      _sectionHeader('Order Book', state),
                      _buildOrderBook(state),
                    ],
                  ),
                ),
        );
      },
    );
  }

  /// Chưa có nến nào (đang bootstrap REST hoặc lỗi mạng) — spinner / retry.
  Widget _buildEmptyBody(BuildContext context, ChartState state) {
    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off,
              size: 40,
              color: state.isDark ? Colors.white38 : Colors.black38,
            ),
            const SizedBox(height: 12),
            Text(
              MarketEnv.isConfigured
                  ? 'Không tải được dữ liệu từ ${MarketEnv.apiBaseUrl}'
                  : 'Chưa cấu hình endpoint API',
              style: TextStyle(
                fontSize: 13,
                color: state.isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                state.error!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: state.isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  context.read<ChartBloc>().add(const ChartStarted()),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  Widget _sectionHeader(String title, ChartState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: state.isDark ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildOrderBook(ChartState state) {
    final upColor = const Color(0xFF0ECB81);
    final dnColor = const Color(0xFFF6465D);
    final textColor = state.isDark ? Colors.white70 : Colors.black87;
    final mutedColor = state.isDark ? Colors.white38 : Colors.black38;

    final book = state.orderBook;
    if (book == null || !book.hasBothSides) {
      // Chưa nhận đủ 2 phía BUY/SELL từ WS trade-plate
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            state.isLive
                ? 'Đang chờ dữ liệu sổ lệnh realtime...'
                : 'Bật Live để nhận dữ liệu sổ lệnh',
            style: TextStyle(fontSize: 12, color: mutedColor),
          ),
        ),
      );
    }

    const maxRows = 15;
    // Asks hiển thị từ giá cao → giá thấp (gần spread nhất ở dưới)
    final asks = book.asks.take(maxRows).toList().reversed.toList();
    final bids = book.bids.take(maxRows).toList();

    // Scale depth bar theo maxAmount server gửi từng phía; fallback max
    // quantity của các mức đang hiển thị nếu thiếu.
    double maxQtyOf(List<OrderBookLevel> levels) =>
        levels.fold<double>(0, (m, l) => max(m, l.quantity.toDouble()));
    final bidMax = book.maxBidQuantity?.toDouble() ?? maxQtyOf(bids);
    final askMax = book.maxAskQuantity?.toDouble() ?? maxQtyOf(asks);

    final midPrice = state.livePrice ?? state.data.last.close;
    final isUp = midPrice >= state.data.last.open;

    // Gộp asks + spread + bids thành 1 list duy nhất
    final items = <_OrderBookItem>[
      ...asks.map((l) => _OrderBookItem.row(l, dnColor, askMax)),
      _OrderBookItem.spread(),
      ...bids.map((l) => _OrderBookItem.row(l, upColor, bidMax)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  'Price (USDT)',
                  style: TextStyle(fontSize: 11, color: mutedColor),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Amount',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: mutedColor),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Total',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: mutedColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Inline list (không tự cuộn — cuộn theo scroll cha)
          ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              if (item.isSpread) {
                return _spreadRow(midPrice, isUp, upColor, dnColor, mutedColor);
              }
              return _orderBookRow(
                item.level!,
                item.sideMax,
                item.sideColor!,
                textColor,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _spreadRow(
    double midPrice,
    bool isUp,
    Color upColor,
    Color dnColor,
    Color mutedColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: mutedColor.withValues(alpha: 0.2), width: 0.5),
          bottom: BorderSide(
            color: mutedColor.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isUp ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: isUp ? upColor : dnColor,
          ),
          const SizedBox(width: 4),
          Text(
            midPrice.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isUp ? upColor : dnColor,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '≈ \$${midPrice.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 11, color: mutedColor),
          ),
        ],
      ),
    );
  }

  Widget _orderBookRow(
    OrderBookLevel level,
    double maxQty,
    Color sideColor,
    Color textColor,
  ) {
    final amount = level.quantity.toDouble();
    final ratio = maxQty == 0 ? 0.0 : (amount / maxQty).clamp(0.0, 1.0);
    return Stack(
      children: [
        // Bar nền theo volume (vẽ từ phải sang trái)
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: ratio,
              child: Container(color: sideColor.withValues(alpha: 0.12)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  // Chuỗi wire gốc — không mất số 0 cuối (vd "0.09800")
                  level.priceText,
                  style: TextStyle(
                    fontSize: 12,
                    color: sideColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  amount.toStringAsFixed(4),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  (level.price.toDouble() * amount).toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChart(BuildContext context, ChartState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner trạng thái load
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: state.isFetching ? 28 : 0,
          color: const Color(0xFFF0B90B),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Đang tải thêm ${ChartState.loadMoreBatchSize} nến...',
                style: const TextStyle(color: Colors.black, fontSize: 12),
              ),
            ],
          ),
        ),
        // Timeframe + scale đã lưu
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              for (final tf in ChartTimeframe.values) ...[
                _chip(
                  tf.label,
                  state.timeframe == tf,
                  state.isDark,
                  () =>
                      context.read<ChartBloc>().add(ChartTimeframeChanged(tf)),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Text(
            'Pinch zoom rồi đổi timeframe — scaleX giữ nguyên '
            '(${state.savedChartScale.scaleX.toStringAsFixed(2)}×)',
            style: TextStyle(
              fontSize: 10,
              color: state.isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
        // Số nến + trạng thái
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Text(
                '${state.data.length} nến · ${state.timeframe.label}'
                '${state.hasMoreHistory ? ' · Kéo trái để tải thêm' : ' · Đã tải hết'}',
                style: TextStyle(
                  fontSize: 11,
                  color: state.isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _scaleYActive
                      ? const Color(0xFFF0B90B).withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _scaleYActive ? 'Chart focused' : 'Scroll mode',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _scaleYActive
                        ? const Color(0xFFF0B90B)
                        : (state.isDark ? Colors.white38 : Colors.black38),
                  ),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (ctx, constraints) {
            _chartWidth = constraints.maxWidth;
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onChartPointerDown,
              onPointerMove: _onChartPointerMove,
              onPointerUp: _onChartPointerUp,
              onPointerCancel: _onChartPointerCancel,
              child: _buildKChart(context, state),
            );
          },
        ),
      ],
    );
  }

  /// Palette kiểu Binance: xanh #0ECB81 / đỏ #F6465D cho up/down, vàng
  /// #F0B90B làm màu nhấn chính (đường giá, MA1, RSI...), teal #35CDAC và
  /// tím #B48EE3 làm màu phụ cho các đường thứ 2/3 — cùng bộ tông đã dùng
  /// làm default trong lib/. bg/text/grid vẫn lấy từ `state.colors` (theo
  /// dark/light mode thật), chỉ đổi màu vẽ (nến/volume/indicator).
  KChartColors _demoColors(ChartState state) {
    const upColor = Color(0xFF0ECB81);
    const dnColor = Color(0xFFF6465D);
    const accentColor = Color(0xFFF0B90B);
    const tealColor = Color(0xFF35CDAC);
    const purpleColor = Color(0xFFB48EE3);
    final textColor = state.isDark
        ? const Color(0xFFEAECEF)
        : const Color(0xFF1E2329);
    final textStyle = TextStyle(color: textColor);

    return state.colors.copyWith(
      livePriceStyle: LivePriceStyle(
        upColor: upColor,
        dnColor: dnColor,
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      candleStyle: CandleStyle(
        upColor: upColor,
        dnColor: dnColor,
        kLineColor: accentColor,
        kLineFillColors: const [Color(0x33F0B90B), Color(0x00F0B90B)],
        textStyle: TextStyle(fontSize: 10, color: textColor),
      ),
      volumeStyle: VolumeStyle(
        upColor: upColor,
        dnColor: dnColor,
        ma5Color: accentColor,
        ma10Color: purpleColor,
        // forceColor bảo vệ ma5Color/ma10Color — chỉ "VOL:" prefix đổi màu.
        textStyle: TextStyle(fontSize: 10, color: textColor),
      ),
      // Mọi indicator dưới đây: textStyle.color = textColor đồng nhất — chỉ
      // áp cho prefix/label chung (vd "KDJ(9,1,3) "); các màu riêng từng giá
      // trị (kColor/dColor/macdColor/...) LUÔN giữ nguyên nhờ forceColor,
      // không bị textStyle.color đè — xem indicator_template.dart getTextStyle().
      avlStyle: AVLStyle(avlColor: accentColor, textStyle: textStyle),
      maStyle: MAStyle(
        maColors: const [accentColor, tealColor, purpleColor, dnColor],
        textStyle: textStyle,
      ),
      emaStyle: MAStyle(
        maColors: const [accentColor, tealColor, purpleColor],
        textStyle: textStyle,
      ),
      bollStyle: BOLLStyle(
        bollColor: accentColor,
        ubColor: tealColor,
        lbColor: purpleColor,
        textStyle: textStyle,
      ),
      sarStyle: SARStyle(
        upColor: upColor,
        dnColor: dnColor,
        textStyle: textStyle,
      ),
      zigzagStyle: ZigZagStyle(zigzagColor: accentColor, textStyle: textStyle),
      superTrendStyle: SuperTrendStyle(
        upColor: upColor,
        dnColor: dnColor,
        textStyle: textStyle,
      ),
      rsiStyle: RSIStyle(rsiColor: accentColor, textStyle: textStyle),
      macdStyle: MACDStyle(
        macdColor: accentColor,
        difColor: tealColor,
        deaColor: purpleColor,
        textStyle: textStyle,
      ),
      kdjStyle: KDJStyle(
        kColor: accentColor,
        dColor: tealColor,
        jColor: purpleColor,
        textStyle: textStyle,
      ),
      wrStyle: WRStyle(wrColor: accentColor, textStyle: textStyle),
      cciStyle: CCIStyle(cciColor: tealColor, textStyle: textStyle),
      obvStyle: OBVStyle(
        obvColor: accentColor,
        signalColor: purpleColor,
        textStyle: textStyle,
      ),
      trixStyle: TRIXStyle(
        trixColor: accentColor,
        trixMaColor: tealColor,
        textStyle: textStyle,
      ),
      mtmStyle: MTMStyle(
        mtmColor: accentColor,
        mtmMaColor: tealColor,
        textStyle: textStyle,
      ),
      stochRsiStyle: StochRSIStyle(
        kColor: accentColor,
        dColor: tealColor,
        textStyle: textStyle,
      ),
      brarStyle: BRARStyle(
        arColor: accentColor,
        brColor: tealColor,
        textStyle: textStyle,
      ),
      biasStyle: BIASStyle(
        biasColors: const [accentColor, tealColor, purpleColor],
        textStyle: textStyle,
      ),
      psyStyle: PSYStyle(
        psyColor: accentColor,
        maPsyColor: tealColor,
        textStyle: textStyle,
      ),
      atrStyle: ATRStyle(
        atrColor: accentColor,
        atrMaColor: tealColor,
        textStyle: textStyle,
      ),
    );
  }

  Widget _buildKChart(BuildContext context, ChartState state) {
    return KChartWidget(
      state.data,
      const KChartStyle(),
      _demoColors(state),
      key: ValueKey(state.timeframe),
      isTrendLine: false,
      isLine: state.isLine,
      volHidden: state.volHidden,
      mainIndicators: _mainIndicatorsFor(state),
      secondaryIndicators: _secondaryIndicatorsFor(state),
      controller: _controller,
      chartScale: state.savedChartScale,
      onChartScaleChanged: (scale) =>
          context.read<ChartBloc>().add(ChartScaleSaved(scale)),
      livePrice: state.livePrice,
      showNowPrice: true,
      showInfoDialog: true,
      mBaseHeight: 280,
      // Chọn phút/giờ (15m, 1H, 4H) → luôn hiện ngày-tháng giờ:phút; chọn
      // ngày (1D) → luôn hiện ngày-tháng-năm. Ép cố định theo khung đang
      // chọn, không dùng thuật toán thích ứng theo zoom của CHART_AXES.md.
      timeFormat: state.timeframe == ChartTimeframe.d1
          ? const [dd, '-', mm, '-', yyyy]
          : const [dd, '-', mm, ' ', hour24Padded, ':', nn],
      onLoadMore: (isLeft) =>
          context.read<ChartBloc>().add(ChartMoreDataRequested(isLeft)),
      isLoadingMore: state.isFetching,
      detailBuilder: (entity) => _buildInfoCard(entity, state.isDark),
      onVerticalOverscroll: _onChartVerticalOverscroll,
      backgroundLogo: Builder(
        builder: (context) {
          final size = MediaQuery.sizeOf(context).width / 12;
          return SvgPicture.asset(
            'assets/logo_jk.svg',
            width: size,
            height: size,
          );
        },
      ),
      backgroundLogoOpacity: 1,
    );
  }

  /// DepthEntity list tích luỹ từ snapshot — bids theo giá tốt→xa (desc),
  /// asks theo giá tốt→xa (asc), vol cộng dồn dần theo hướng xa spread.
  static List<DepthEntity> _cumulativeDepth(List<OrderBookLevel> levels) {
    double cum = 0;
    return [
      for (final l in levels)
        DepthEntity(l.price.toDouble(), cum += l.quantity.toDouble()),
    ];
  }

  Widget _buildDepthChartSection(BuildContext context, ChartState state) {
    final book = state.orderBook;
    if (book == null || !book.hasBothSides) {
      return SizedBox(
        height: 280,
        child: Center(
          child: Text(
            state.isLive
                ? 'Đang chờ dữ liệu sổ lệnh realtime...'
                : 'Bật Live để nhận dữ liệu sổ lệnh',
            style: TextStyle(
              fontSize: 12,
              color: state.isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
      );
    }
    final depth = (
      bids: _cumulativeDepth(book.bids),
      asks: _cumulativeDepth(book.asks),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Bộ chọn số mốc giá ở trục dưới
          Row(
            children: [
              Text(
                'Bottom labels:',
                style: TextStyle(
                  fontSize: 11,
                  color: state.isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(width: 8),
              for (final n in const [3, 5, 7, 9]) ...[
                _chip(
                  '$n',
                  state.depthBottomLabelCount == n,
                  state.isDark,
                  () => context.read<ChartBloc>().add(
                    ChartDepthBottomLabelCountChanged(n),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 280,
            child: DepthChart(
              depth.bids,
              depth.asks,
              DepthChartColors(
                defaultTextColor: state.isDark
                    ? const Color(0xFF8E8E93)
                    : const Color(0xFF909196),
              ),
              bottomLabelCount: state.depthBottomLabelCount,
              backgroundLogo: Builder(
                builder: (context) {
                  final size = MediaQuery.sizeOf(context).width / 12;
                  return SvgPicture.asset(
                    'assets/logo_jk.svg',
                    width: size,
                    height: size,
                  );
                },
              ),
              backgroundLogoOpacity: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(KLineEntity entity, bool isDark) {
    final isUp = entity.close >= entity.open;
    final color = isUp ? const Color(0xFF0ECB81) : const Color(0xFFF6465D);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2329) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _infoRow('Open', entity.open.toStringAsFixed(2)),
            _infoRow('High', entity.high.toStringAsFixed(2)),
            _infoRow('Low', entity.low.toStringAsFixed(2)),
            _infoRow(
              'Close',
              entity.close.toStringAsFixed(2),
              valueColor: color,
            ),
            _infoRow('Vol', entity.vol.toStringAsFixed(2)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 38,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(color: valueColor)),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, ChartState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: chart type + zoom controls
          Row(
            children: [
              _chip(
                'Candle',
                !state.isLine,
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartLineModeChanged(false),
                ),
              ),
              const SizedBox(width: 6),
              _chip(
                'Line',
                state.isLine,
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartLineModeChanged(true),
                ),
              ),
              const SizedBox(width: 6),
              _chip(
                'Volume',
                !state.volHidden,
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartVolumeVisibilityToggled(),
                ),
              ),
              const SizedBox(width: 6),
              _liveChip(context, state),
              const Spacer(),
              _iconBtn(
                Icons.zoom_in,
                () => _controller.zoomIn(),
                'Zoom In',
                state.isDark,
              ),
              _iconBtn(
                Icons.zoom_out,
                () => _controller.zoomOut(),
                'Zoom Out',
                state.isDark,
              ),
              _iconBtn(
                Icons.refresh,
                () => _controller.reset(),
                'Reset',
                state.isDark,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionLabel('Main Indicator', state.isDark),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                'MA',
                state.mainTypes.contains(MainIndicatorType.ma),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartMainIndicatorToggled(MainIndicatorType.ma),
                ),
              ),
              _chip(
                'BOLL',
                state.mainTypes.contains(MainIndicatorType.boll),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartMainIndicatorToggled(MainIndicatorType.boll),
                ),
              ),
              _chip(
                'EMA',
                state.mainTypes.contains(MainIndicatorType.ema),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartMainIndicatorToggled(MainIndicatorType.ema),
                ),
              ),
              _chip(
                'SAR',
                state.mainTypes.contains(MainIndicatorType.sar),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartMainIndicatorToggled(MainIndicatorType.sar),
                ),
              ),
              _chip(
                'SUPER',
                state.mainTypes.contains(MainIndicatorType.superTrend),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartMainIndicatorToggled(MainIndicatorType.superTrend),
                ),
              ),
              _chip(
                'ZigZag',
                state.mainTypes.contains(MainIndicatorType.zigzag),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartMainIndicatorToggled(MainIndicatorType.zigzag),
                ),
              ),
              _chip(
                'AVL',
                state.mainTypes.contains(MainIndicatorType.avl),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartMainIndicatorToggled(MainIndicatorType.avl),
                ),
              ),
              _chip(
                'Ichimoku',
                state.mainTypes.contains(MainIndicatorType.ichimoku),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartMainIndicatorToggled(MainIndicatorType.ichimoku),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionLabel('Secondary Indicator', state.isDark),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                'MACD',
                state.secondaryTypes.contains(SecondaryIndicatorType.macd),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.macd,
                  ),
                ),
              ),
              _chip(
                'KDJ',
                state.secondaryTypes.contains(SecondaryIndicatorType.kdj),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.kdj,
                  ),
                ),
              ),
              _chip(
                'RSI',
                state.secondaryTypes.contains(SecondaryIndicatorType.rsi),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.rsi,
                  ),
                ),
              ),
              _chip(
                'WR',
                state.secondaryTypes.contains(SecondaryIndicatorType.wr),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.wr,
                  ),
                ),
              ),
              _chip(
                'CCI',
                state.secondaryTypes.contains(SecondaryIndicatorType.cci),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.cci,
                  ),
                ),
              ),
              _chip(
                'OBV',
                state.secondaryTypes.contains(SecondaryIndicatorType.obv),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.obv,
                  ),
                ),
              ),
              _chip(
                'TRIX',
                state.secondaryTypes.contains(SecondaryIndicatorType.trix),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.trix,
                  ),
                ),
              ),
              _chip(
                'MTM',
                state.secondaryTypes.contains(SecondaryIndicatorType.mtm),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.mtm,
                  ),
                ),
              ),
              _chip(
                'StochRSI',
                state.secondaryTypes.contains(SecondaryIndicatorType.stochRsi),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.stochRsi,
                  ),
                ),
              ),
              _chip(
                'BRAR',
                state.secondaryTypes.contains(SecondaryIndicatorType.brar),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.brar,
                  ),
                ),
              ),
              _chip(
                'BIAS',
                state.secondaryTypes.contains(SecondaryIndicatorType.bias),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.bias,
                  ),
                ),
              ),
              _chip(
                'PSY',
                state.secondaryTypes.contains(SecondaryIndicatorType.psy),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.psy,
                  ),
                ),
              ),
              _chip(
                'ATR',
                state.secondaryTypes.contains(SecondaryIndicatorType.atr),
                state.isDark,
                () => context.read<ChartBloc>().add(
                  const ChartSecondaryIndicatorToggled(
                    SecondaryIndicatorType.atr,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white38 : Colors.black38,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _chip(String label, bool selected, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFF0B90B)
              : (isDark ? const Color(0xFF1E2329) : const Color(0xFFF2F3F5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected
                ? Colors.black
                : (isDark ? Colors.white60 : Colors.black54),
          ),
        ),
      ),
    );
  }

  Widget _liveChip(BuildContext context, ChartState state) {
    return GestureDetector(
      onTap: () => context.read<ChartBloc>().add(const ChartLiveToggled()),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: state.isLive
              ? const Color(0xFFF6465D)
              : (state.isDark
                    ? const Color(0xFF1E2329)
                    : const Color(0xFFF2F3F5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.isLive) ...[
              // Dot nhấp nháy khi đang live
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.3, end: 1.0),
                duration: const Duration(milliseconds: 600),
                builder: (_, v, __) => Opacity(
                  opacity: v,
                  child: const Icon(Icons.circle, size: 6, color: Colors.white),
                ),
                // setState rỗng chỉ để rebuild local widget → TweenAnimationBuilder
                // dựng lại Tween mới → animation lặp lại. Thuần UI, không liên quan Bloc.
                onEnd: () => setState(() {}),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              'Live',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: state.isLive
                    ? Colors.white
                    : (state.isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(
    IconData icon,
    VoidCallback onTap,
    String tooltip,
    bool isDark,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 20,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ),
    );
  }
}
