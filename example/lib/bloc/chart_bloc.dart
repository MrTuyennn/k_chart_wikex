import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:k_chart_jk/k_chart_plus.dart';

import '../market/market_env.dart';
import '../market/market_history_api.dart';
import '../market/market_kline.dart';
import '../market/market_stomp_transport.dart';
import '../market/order_book.dart';
import '../market/realtime_frame.dart';
import 'chart_event.dart';
import 'chart_state.dart';
import 'kline_merge.dart';

// ── Event nội bộ — chỉ ChartBloc tự dispatch từ listener WS/timer bên trong.
// Private theo file (Dart library-level) nên View không thấy và không gọi được.

/// Buffer coalesce 250ms đã đến hạn — merge các bar chờ vào series.
class _ChartRealtimeFlushed extends ChartEvent {
  const _ChartRealtimeFlushed();
}

/// Giá tick mới nhất từ thumb/kline (event tới sau thắng).
class _ChartLivePriceChanged extends ChartEvent {
  const _ChartLivePriceChanged(this.price);
  final double price;

  @override
  List<Object?> get props => [price];
}

/// Snapshot sổ lệnh mới sau khi merge BUY/SELL trade-plate (đã coalesce).
class _ChartOrderBookUpdated extends ChartEvent {
  const _ChartOrderBookUpdated(this.snapshot);
  final OrderBookSnapshot snapshot;

  @override
  List<Object?> get props => [snapshot.version];
}

/// Tham số gửi sang isolate nền để tính indicator — chỉ gồm dữ liệu thuần
/// (KLineEntity là các field double/int) và enum loại indicator. KHÔNG gửi
/// instance MainIndicator/SecondaryIndicator qua isolate vì chúng khởi tạo
/// sẵn Paint trong constructor — Paint/Shader không đảm bảo an toàn khi
/// serialize qua isolate boundary.
class _IndicatorCalcRequest {
  const _IndicatorCalcRequest(this.data, this.mainTypes, this.secondaryTypes);

  final List<KLineEntity> data;
  final List<MainIndicatorType> mainTypes;
  final List<SecondaryIndicatorType> secondaryTypes;
}

/// Entry point của worker isolate — spawn MỘT LẦN, sống suốt vòng đời
/// [ChartBloc] (khác với `compute()` spawn isolate mới mỗi lần gọi: với
/// data nhỏ (~200-500 nến) và tần suất gọi dày (realtime flush mỗi 250ms),
/// chi phí spawn lặp lại còn tốn hơn chính phép tính, gây jank định kỳ dù
/// UI đứng yên). Dựng lại indicator instance tại chỗ (Paint tạo trong
/// isolate này, không bao giờ rời khỏi nó) rồi tính trên bản copy của
/// `data`, gửi list đã tính về qua [mainSendPort].
void _indicatorWorkerMain(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);
  commandPort.listen((message) {
    final request = message as _IndicatorCalcRequest;
    try {
      DataUtil.calculateAll(
        request.data,
        request.mainTypes.map(buildMainIndicator).toList(),
        request.secondaryTypes.map(buildSecondaryIndicator).toList(),
      );
    } catch (_) {
      // Không để lỗi tính indicator treo completer chờ mãi ở phía bloc —
      // trả data gốc (chưa tính) để chart vẫn hiển thị thay vì đứng hình.
    }
    mainSendPort.send(request.data);
  });
}

class ChartBloc extends Bloc<ChartEvent, ChartState> {
  ChartBloc({MarketStompTransport? transport})
    : _transport =
          transport ?? MarketStompTransport(stompUrl: MarketEnv.stompUrl),
      super(_initialState()) {
    on<ChartStarted>(_onStarted);
    on<ChartTimeframeChanged>(_onTimeframeChanged);
    on<ChartMainIndicatorToggled>(_onMainIndicatorToggled);
    on<ChartSecondaryIndicatorToggled>(_onSecondaryIndicatorToggled);
    on<ChartLineModeChanged>(_onLineModeChanged);
    on<ChartCandleBodyStyleChanged>(_onCandleBodyStyleChanged);
    on<ChartVolumeVisibilityToggled>(_onVolumeVisibilityToggled);
    on<ChartBidAskVisibilityToggled>(_onBidAskVisibilityToggled);
    on<ChartThemeToggled>(_onThemeToggled);
    on<ChartDepthVisibilityChanged>(_onDepthVisibilityChanged);
    on<ChartDepthBottomLabelCountChanged>(_onDepthBottomLabelCountChanged);
    on<ChartScaleSaved>(_onScaleSaved);
    on<ChartMoreDataRequested>(_onMoreDataRequested);
    on<ChartLiveToggled>(_onLiveToggled);
    on<_ChartRealtimeFlushed>(_onRealtimeFlushed);
    on<_ChartLivePriceChanged>(_onLivePriceChanged);
    on<_ChartOrderBookUpdated>(_onOrderBookUpdated);

    _workerResponsePort.listen(_onWorkerMessage);
    _workerSpawn = Isolate.spawn(
      _indicatorWorkerMain,
      _workerResponsePort.sendPort,
    ).then((isolate) => _workerIsolate = isolate);

    add(const ChartStarted());
  }

  final MarketStompTransport _transport;

  // Worker isolate thường trú tính indicator — xem [_indicatorWorkerMain].
  final ReceivePort _workerResponsePort = ReceivePort();
  final Completer<SendPort> _workerCommandPort = Completer();
  final Queue<Completer<List<KLineEntity>>> _pendingRecalcs = Queue();
  Isolate? _workerIsolate;
  late final Future<void> _workerSpawn;

  void _onWorkerMessage(dynamic message) {
    if (message is SendPort) {
      _workerCommandPort.complete(message);
      return;
    }
    if (_pendingRecalcs.isEmpty) return;
    _pendingRecalcs.removeFirst().complete(message as List<KLineEntity>);
  }

  StreamSubscription<RealtimeFrame>? _klineSub;
  StreamSubscription<RealtimeFrame>? _klineLiveSub;
  StreamSubscription<RealtimeFrame>? _thumbSub;
  StreamSubscription<RealtimeFrame>? _tradePlateSub;

  // Số lần tối đa mở rộng cửa sổ fetch lịch sử khi gặp gap (xem _loadHistory)
  // — ×4 mỗi lần nên 4 lần đã phủ 4^4 = 256x cửa sổ gốc, đủ vượt qua downtime
  // vài ngày mà không loop mãi nếu symbol thật sự chỉ có ít data.
  static const int _kMaxHistoryWidenAttempts = 4;

  // Coalesce WS: buffer bar đến trong cửa sổ ngắn rồi flush 1 lần —
  // không rebuild chart theo từng message.
  static const Duration _coalesceWindow = Duration(milliseconds: 250);
  final List<MarketKline> _pending = [];
  Timer? _throttle;

  // Order book: merge service giữ snapshot 2 phía; coalesce riêng vì
  // trade-plate bắn dày hơn kline.
  final OrderBookMergeService _orderBookMerge = OrderBookMergeService();
  Timer? _orderBookThrottle;
  static const Duration _orderBookCoalesce = Duration(milliseconds: 200);

  // livePrice: bắn từ CẢ `topicKline`/`topicKlineLive` (mỗi bar) LẪN
  // `topicThumb` (mỗi tick ticker) — 2 nguồn cộng dồn, trên cặp giao dịch
  // sôi động có thể tới hàng chục lần/giây. Trước đây `add(_ChartLivePriceChanged)`
  // gọi THẲNG, không coalesce như kline/order book ở trên — mỗi tick ép
  // `BlocBuilder` gốc (bọc cả trang, không `buildWhen`) rebuild toàn bộ
  // Scaffold + `ChartPainter` repaint lại toàn bộ nến/indicator visible,
  // độc lập với style nến đang chọn. Đây là nguồn jank LỚN HƠN nhiều so với
  // chi phí vẽ thêm của candle_style (vốn chỉ ăn theo mỗi lần repaint này,
  // không tự nó gây repaint) — coalesce cùng kiểu với kline/order book để
  // giới hạn tần suất rebuild UI, không đổi tần suất xử lý dữ liệu.
  Timer? _livePriceThrottle;
  double? _pendingLivePrice;
  static const Duration _livePriceCoalesce = Duration(milliseconds: 150);

  static String get _topicPath => MarketEnv.symbol; // đã đúng dạng BASE/QUOTE

  /// true = bật sẵn TOÀN BỘ indicator lúc mở app (demo xem hết cùng lúc);
  /// false = tắt hết, user tự bật qua chip. Đổi 1 chỗ duy nhất ở đây, không
  /// cần sửa lại 2 `Set` bên dưới.
  static const bool _kIndicatorsEnabledByDefault = false;

  static ChartState _initialState() {
    return const ChartState(
      data: [],
      timeframe: ChartTimeframe.h1,
      mainTypes: _kIndicatorsEnabledByDefault
          ? {
              MainIndicatorType.ma,
              MainIndicatorType.boll,
              MainIndicatorType.ema,
              MainIndicatorType.sar,
              MainIndicatorType.superTrend,
              MainIndicatorType.zigzag,
              MainIndicatorType.avl,
              MainIndicatorType.ichimoku,
            }
          : {},
      secondaryTypes: _kIndicatorsEnabledByDefault
          ? {
              SecondaryIndicatorType.macd,
              SecondaryIndicatorType.kdj,
              SecondaryIndicatorType.rsi,
              SecondaryIndicatorType.wr,
              SecondaryIndicatorType.cci,
              SecondaryIndicatorType.obv,
              SecondaryIndicatorType.trix,
              SecondaryIndicatorType.mtm,
              SecondaryIndicatorType.stochRsi,
              SecondaryIndicatorType.brar,
              SecondaryIndicatorType.bias,
              SecondaryIndicatorType.psy,
              SecondaryIndicatorType.atr,
            }
          : {},
      savedChartScale: KChartScaleState(),
      isLine: false,
      candleBodyStyle: CandleBodyStyle.solid,
      volHidden: false,
      isDark: false,
      showDepth: false,
      depthBottomLabelCount: 3,
      isFetching: true,
      hasMoreHistory: true,
      isLive: true,
      showBidAsk: false,
    );
  }

  /// Tính indicator trong worker isolate thường trú, tránh block UI thread
  /// khi list nến lớn hoặc tính lại dồn dập (realtime flush mỗi 250ms, toggle
  /// indicator). Trả về list ĐÃ tính — không mutate [state.data] in-place như
  /// bản đồng bộ cũ, vì worker chạy trên bản copy ở isolate khác.
  Future<List<KLineEntity>> _recalculateState(ChartState state) async {
    final commandPort = await _workerCommandPort.future;
    final completer = Completer<List<KLineEntity>>();
    _pendingRecalcs.add(completer);
    commandPort.send(
      _IndicatorCalcRequest(
        state.data,
        state.mainTypes.toList(),
        state.secondaryTypes.toList(),
      ),
    );
    return completer.future;
  }

  // Hàng đợi tuần tự hoá các đoạn "đọc state mới nhất → recalc qua worker
  // isolate → emit". Không có await ở bản đồng bộ cũ nên các handler không
  // bao giờ chen ngang nhau; giờ có await (chờ worker), nếu 2 handler khác
  // event type (vd toggle main indicator và realtime flush) cùng chạy, handler
  // xong sau có thể emit đè lên field mà handler kia vừa cập nhật, làm MẤT
  // hẳn thay đổi đó (không phải chỉ trễ 1 nhịp). Khoá này đảm bảo tại một thời
  // điểm chỉ một đoạn recalc+emit chạy, và state đọc bên trong luôn mới nhất.
  Future<void> _recalcLock = Future.value();

  Future<void> _withRecalcLock(Future<void> Function() action) {
    final completer = Completer<void>();
    final result = _recalcLock
        .then((_) => action())
        .whenComplete(completer.complete);
    _recalcLock = completer.future;
    return result;
  }

  // ── Bootstrap + timeframe ─────────────────────────────────────────────────

  Future<void> _onStarted(ChartStarted event, Emitter<ChartState> emit) async {
    await _loadHistory(state.timeframe, emit);
    if (state.isLive && state.error == null) {
      _subscribeRealtime();
    }
  }

  Future<void> _onTimeframeChanged(
    ChartTimeframeChanged event,
    Emitter<ChartState> emit,
  ) async {
    if (state.timeframe == event.timeframe) return;
    // Đổi khung → clear buffer WS của khung cũ rồi refetch REST.
    // Subscription giữ nguyên (cùng symbol) — chỉ filter `period` đổi.
    _pending.clear();
    emit(state.copyWith(timeframe: event.timeframe));
    await _loadHistory(event.timeframe, emit);
  }

  Future<void> _loadHistory(
    ChartTimeframe timeframe,
    Emitter<ChartState> emit,
  ) async {
    if (!MarketEnv.isConfigured) {
      emit(
        state.copyWith(
          isFetching: false,
          error: 'missing_env: chạy với --dart-define-from-file=env.dev.json',
        ),
      );
      return;
    }
    emit(state.copyWith(isFetching: true, error: null));
    try {
      final toMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final intervalMs = timeframe.interval.inMilliseconds;
      // Cửa sổ ban đầu (`initialBatchSize × interval`) giả định data liên
      // tục. Sàn có thể có downtime/gap gần đây (hay gặp ở môi trường dev —
      // vd 15m từng bị hở ~2 ngày ngay trước "hiện tại") khiến server trả về
      // ÍT hơn initialBatchSize dù KHÔNG rỗng (còn lịch sử xa hơn gap). Mở
      // rộng cửa sổ lùi xa hơn (×4 mỗi lần) tới khi đủ nến hoặc server trả
      // rỗng thật (hết lịch sử) — tối đa _kMaxHistoryWidenAttempts lần để
      // không loop mãi nếu symbol thật sự chỉ có ít data.
      var windowMultiplier = 1;
      List<MarketKline> bars = const [];
      for (var attempt = 0; attempt < _kMaxHistoryWidenAttempts; attempt++) {
        final fromMs = toMs - windowMultiplier * ChartState.initialBatchSize * intervalMs;
        bars = await fetchMarketHistory(
          apiBaseUrl: MarketEnv.apiBaseUrl,
          historyPath: MarketEnv.historyPath,
          symbol: MarketEnv.symbol,
          resolution: timeframe.restResolution,
          period: timeframe.wsPeriod,
          fromMs: fromMs,
          toMs: toMs,
        );
        if (isClosed || state.timeframe != timeframe) return; // đã đổi khung khác
        if (bars.length >= ChartState.initialBatchSize || bars.isEmpty) break;
        windowMultiplier *= 4;
      }
      // Mở rộng có thể trả về nhiều hơn initialBatchSize (vd nhảy thẳng qua
      // gap tới vùng dữ liệu dày) — cắt về đúng batch size mong muốn, giữ
      // phần MỚI NHẤT (gần `toMs`).
      if (bars.length > ChartState.initialBatchSize) {
        bars = bars.sublist(bars.length - ChartState.initialBatchSize);
      }
      await _withRecalcLock(() async {
        if (isClosed || state.timeframe != timeframe) return;
        var next = state.copyWith(
          data: [for (final b in bars) b.toEntity()],
          isFetching: false,
          hasMoreHistory: bars.isNotEmpty,
          error: null,
        );
        final computed = await _recalculateState(next);
        if (isClosed || state.timeframe != timeframe)
          return; // đổi khung lúc chờ isolate
        next = next.copyWith(data: computed);
        emit(next);
      });
    } catch (e) {
      if (isClosed || state.timeframe != timeframe) return;
      emit(state.copyWith(isFetching: false, error: e.toString()));
    }
  }

  // ── Load more (kéo trái) ──────────────────────────────────────────────────

  Future<void> _onMoreDataRequested(
    ChartMoreDataRequested event,
    Emitter<ChartState> emit,
  ) async {
    if (!event.isLeft) return; // chỉ xử lý load data cũ hơn
    if (state.isFetching) return; // đang fetch rồi, bỏ qua
    if (!state.hasMoreHistory) return; // server đã hết nến cũ
    if (state.data.isEmpty) return;

    final timeframe = state.timeframe;
    final oldestMs = state.data.first.time!;
    emit(state.copyWith(isFetching: true));
    try {
      final bars = await fetchMarketHistory(
        apiBaseUrl: MarketEnv.apiBaseUrl,
        historyPath: MarketEnv.historyPath,
        symbol: MarketEnv.symbol,
        resolution: timeframe.restResolution,
        period: timeframe.wsPeriod,
        fromMs:
            oldestMs -
            ChartState.loadMoreBatchSize * timeframe.interval.inMilliseconds,
        toMs: oldestMs - 1, // tránh trùng bar cũ nhất đang có
      );
      if (isClosed) return;
      if (state.timeframe != timeframe)
        return; // user đã đổi khung trong lúc chờ
      await _withRecalcLock(() async {
        if (isClosed || state.timeframe != timeframe) return;
        // state.data đọc lại BÊN TRONG khoá, SAU await fetch — không mất các
        // bar WS merge vào trong lúc chờ. Dedupe theo time phòng server trả
        // lấn biên.
        final older = [
          for (final b in bars)
            if (b.barCloseTime.millisecondsSinceEpoch < state.data.first.time!)
              b.toEntity(),
        ];
        var next = state.copyWith(
          data: [...older, ...state.data],
          isFetching: false,
          hasMoreHistory: bars.isNotEmpty,
        );
        final computed = await _recalculateState(next);
        if (isClosed || state.timeframe != timeframe)
          return; // đổi khung lúc chờ isolate
        next = next.copyWith(data: computed);
        emit(next);
      });
    } catch (_) {
      if (isClosed) return;
      // Load-more lỗi không phá chart đang hiển thị — chỉ gỡ cờ fetching
      // để lần kéo sau retry.
      emit(state.copyWith(isFetching: false));
    }
  }

  // ── Realtime WS ───────────────────────────────────────────────────────────

  void _subscribeRealtime() {
    if (_klineSub != null) return; // đã subscribe rồi
    _klineSub = _transport
        .subscribe(
          RealtimeSubscription(
            destination: '${MarketEnv.topicKline}/$_topicPath',
            stalePolicy: RealtimeStalePolicy.klineBar,
          ),
        )
        .listen(_onKlineFrame);
    _klineLiveSub = _transport
        .subscribe(
          RealtimeSubscription(
            destination: '${MarketEnv.topicKlineLive}/$_topicPath',
            stalePolicy: RealtimeStalePolicy.klineBar,
          ),
        )
        .listen(_onKlineFrame);
    _thumbSub = _transport
        .subscribe(
          const RealtimeSubscription(
            destination: MarketEnv.topicThumb,
            stalePolicy: RealtimeStalePolicy.fastStream,
          ),
        )
        .listen(_onThumbFrame);
    // Reset trước khi subscribe lại — tránh lẫn snapshot của phiên trước.
    _orderBookMerge.reset();
    _tradePlateSub = _transport
        .subscribe(
          RealtimeSubscription(
            destination: '${MarketEnv.topicTradePlate}/$_topicPath',
            stalePolicy: RealtimeStalePolicy.fastStream,
          ),
        )
        .listen(_onTradePlateFrame);
  }

  Future<void> _unsubscribeRealtime() async {
    _throttle?.cancel();
    _throttle = null;
    _pending.clear();
    _orderBookThrottle?.cancel();
    _orderBookThrottle = null;
    _livePriceThrottle?.cancel();
    _livePriceThrottle = null;
    _pendingLivePrice = null;
    await _klineSub?.cancel();
    await _klineLiveSub?.cancel();
    await _thumbSub?.cancel();
    await _tradePlateSub?.cancel();
    _klineSub = null;
    _klineLiveSub = null;
    _thumbSub = null;
    _tradePlateSub = null;
  }

  void _onKlineFrame(RealtimeFrame frame) {
    if (isClosed) return;
    final kline = tryParseKlineFrame(frame, symbol: MarketEnv.symbol);
    if (kline == null) {
      return; // chỉ bỏ đúng frame lỗi — KHÔNG đụng vào _pending
    }
    // Live price từ kline mọi period (giá mới nhất của symbol).
    _queueLivePrice(kline.close.toDouble());
    if (kline.period != state.timeframe.wsPeriod) {
      return; // khác khung timeframe đang chọn
    }
    _pending.add(kline);
    _throttle ??= Timer(
      _coalesceWindow,
      () => add(const _ChartRealtimeFlushed()),
    );
  }

  void _onThumbFrame(RealtimeFrame frame) {
    if (isClosed) return;
    final thumb = tryParseThumbFrame(frame);
    // Stream global — tự lọc đúng cặp đang xem.
    if (thumb == null || thumb.symbol != MarketEnv.symbol) return;
    _queueLivePrice(thumb.close);
  }

  /// Coalesce `_ChartLivePriceChanged` — cùng pattern `_pending`/`_throttle`
  /// (kline) và `_orderBookMerge`/`_orderBookThrottle` (order book) ở trên:
  /// giữ giá MỚI NHẤT, chỉ `add()` 1 lần/cửa sổ thay vì mỗi frame WS. Gọi từ
  /// cả `_onKlineFrame` VÀ `_onThumbFrame` (2 nguồn cộng dồn tần suất).
  void _queueLivePrice(double price) {
    _pendingLivePrice = price;
    _livePriceThrottle ??= Timer(_livePriceCoalesce, () {
      _livePriceThrottle = null;
      final pending = _pendingLivePrice;
      _pendingLivePrice = null;
      if (pending != null && !isClosed) {
        add(_ChartLivePriceChanged(pending));
      }
    });
  }

  void _onTradePlateFrame(RealtimeFrame frame) {
    if (isClosed) return;
    final side = tryParseOrderBookSideFrame(
      frame,
      expectedSymbol: MarketEnv.symbol,
    );
    if (side == null) return; // chỉ bỏ đúng frame lỗi, snapshot giữ nguyên
    _orderBookMerge.apply(side);
    // Coalesce: emit snapshot mới nhất mỗi cửa sổ, không emit từng message.
    _orderBookThrottle ??= Timer(_orderBookCoalesce, () {
      _orderBookThrottle = null;
      if (!isClosed) add(_ChartOrderBookUpdated(_orderBookMerge.current));
    });
  }

  void _onOrderBookUpdated(
    _ChartOrderBookUpdated event,
    Emitter<ChartState> emit,
  ) {
    emit(state.copyWith(orderBook: event.snapshot));
  }

  Future<void> _onRealtimeFlushed(
    _ChartRealtimeFlushed event,
    Emitter<ChartState> emit,
  ) async {
    _throttle = null;
    if (_pending.isEmpty) return;
    final bars = List<MarketKline>.of(_pending);
    _pending.clear();
    await _withRecalcLock(() async {
      if (isClosed) return;
      // state.data đọc BÊN TRONG khoá — mới nhất tính đến lúc này, không bị
      // handler khác (toggle indicator, load more...) chen ngang đè mất.
      var data = state.data;
      final intervalMs = state.timeframe.interval.inMilliseconds;
      for (final k in bars) {
        // Re-check period: timeframe có thể đã đổi khi bar còn nằm buffer.
        if (k.period != state.timeframe.wsPeriod) continue;
        data = mergeKlineBar(data, k, intervalMs: intervalMs);
      }
      if (identical(data, state.data)) return;
      var next = state.copyWith(data: data);
      final computed = await _recalculateState(next);
      if (isClosed) return; // bloc đóng lúc chờ isolate
      next = next.copyWith(data: computed);
      emit(next);
    });
  }

  void _onLivePriceChanged(
    _ChartLivePriceChanged event,
    Emitter<ChartState> emit,
  ) {
    if (state.livePrice == event.price) return;
    emit(state.copyWith(livePrice: event.price));
  }

  Future<void> _onLiveToggled(
    ChartLiveToggled event,
    Emitter<ChartState> emit,
  ) async {
    if (state.isLive) {
      emit(state.copyWith(isLive: false));
      await _unsubscribeRealtime();
    } else {
      emit(state.copyWith(isLive: true));
      _subscribeRealtime();
    }
  }

  // ── UI toggles ────────────────────────────────────────────────────────────

  Future<void> _onMainIndicatorToggled(
    ChartMainIndicatorToggled event,
    Emitter<ChartState> emit,
  ) {
    return _withRecalcLock(() async {
      if (isClosed) return;
      final types = Set<MainIndicatorType>.of(state.mainTypes);
      if (!types.remove(event.type)) types.add(event.type);
      var next = state.copyWith(mainTypes: types);
      final computed = await _recalculateState(next);
      if (isClosed) return;
      next = next.copyWith(data: computed);
      emit(next);
    });
  }

  Future<void> _onSecondaryIndicatorToggled(
    ChartSecondaryIndicatorToggled event,
    Emitter<ChartState> emit,
  ) {
    return _withRecalcLock(() async {
      if (isClosed) return;
      final types = Set<SecondaryIndicatorType>.of(state.secondaryTypes);
      if (!types.remove(event.type)) types.add(event.type);
      var next = state.copyWith(secondaryTypes: types);
      final computed = await _recalculateState(next);
      if (isClosed) return;
      next = next.copyWith(data: computed);
      emit(next);
    });
  }

  void _onLineModeChanged(
    ChartLineModeChanged event,
    Emitter<ChartState> emit,
  ) {
    emit(state.copyWith(isLine: event.isLine));
  }

  void _onCandleBodyStyleChanged(
    ChartCandleBodyStyleChanged event,
    Emitter<ChartState> emit,
  ) {
    emit(state.copyWith(candleBodyStyle: event.bodyStyle));
  }

  void _onVolumeVisibilityToggled(
    ChartVolumeVisibilityToggled event,
    Emitter<ChartState> emit,
  ) {
    emit(state.copyWith(volHidden: !state.volHidden));
  }

  void _onBidAskVisibilityToggled(
    ChartBidAskVisibilityToggled event,
    Emitter<ChartState> emit,
  ) {
    emit(state.copyWith(showBidAsk: !state.showBidAsk));
  }

  void _onThemeToggled(ChartThemeToggled event, Emitter<ChartState> emit) {
    emit(state.copyWith(isDark: !state.isDark));
  }

  void _onDepthVisibilityChanged(
    ChartDepthVisibilityChanged event,
    Emitter<ChartState> emit,
  ) {
    emit(state.copyWith(showDepth: event.show));
  }

  void _onDepthBottomLabelCountChanged(
    ChartDepthBottomLabelCountChanged event,
    Emitter<ChartState> emit,
  ) {
    emit(state.copyWith(depthBottomLabelCount: event.count));
  }

  void _onScaleSaved(ChartScaleSaved event, Emitter<ChartState> emit) {
    emit(state.copyWith(savedChartScale: event.scale));
  }

  @override
  Future<void> close() async {
    await _unsubscribeRealtime();
    await _transport.shutdown();
    await _workerSpawn;
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerResponsePort.close();
    return super.close();
  }
}
