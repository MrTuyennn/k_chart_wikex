import 'package:equatable/equatable.dart';
import 'package:k_chart_jk/k_chart_plus.dart';

import 'chart_state.dart';

/// Event public — View dispatch qua `context.read<ChartBloc>().add(...)`.
/// Event nội bộ của luồng realtime (flush buffer WS, live price...) nằm
/// private trong `chart_bloc.dart` — View không thấy và không gọi được.
abstract class ChartEvent extends Equatable {
  const ChartEvent();

  @override
  List<Object?> get props => [];
}

/// Bootstrap dữ liệu (REST history + subscribe WS) — dispatch khi khởi tạo
/// Bloc và khi user bấm "Thử lại" sau lỗi mạng.
class ChartStarted extends ChartEvent {
  const ChartStarted();
}

/// Đổi khung thời gian (15m/1H/4H/1D) — refetch REST theo resolution mới.
class ChartTimeframeChanged extends ChartEvent {
  const ChartTimeframeChanged(this.timeframe);
  final ChartTimeframe timeframe;

  @override
  List<Object?> get props => [timeframe];
}

/// Bật/tắt 1 main indicator (multi-select, giống secondary).
class ChartMainIndicatorToggled extends ChartEvent {
  const ChartMainIndicatorToggled(this.type);
  final MainIndicatorType type;

  @override
  List<Object?> get props => [type];
}

/// Bật/tắt 1 secondary indicator (multi-select).
class ChartSecondaryIndicatorToggled extends ChartEvent {
  const ChartSecondaryIndicatorToggled(this.type);
  final SecondaryIndicatorType type;

  @override
  List<Object?> get props => [type];
}

/// Đổi chế độ hiển thị nến/line.
class ChartLineModeChanged extends ChartEvent {
  const ChartLineModeChanged(this.isLine);
  final bool isLine;

  @override
  List<Object?> get props => [isLine];
}

/// Đổi kiểu vẽ thân nến (Solid/Hollow Up/Hollow Down/Hollow) — xem
/// [CandleBodyStyle]. Không ảnh hưởng `isLine = true` (line chart không có
/// khái niệm thân nến).
class ChartCandleBodyStyleChanged extends ChartEvent {
  const ChartCandleBodyStyleChanged(this.bodyStyle);
  final CandleBodyStyle bodyStyle;

  @override
  List<Object?> get props => [bodyStyle];
}

/// Bật/tắt panel volume.
class ChartVolumeVisibilityToggled extends ChartEvent {
  const ChartVolumeVisibilityToggled();
}

/// Bật/tắt dark mode.
class ChartThemeToggled extends ChartEvent {
  const ChartThemeToggled();
}

/// Bật/tắt xem depth chart thay vì candle chart.
class ChartDepthVisibilityChanged extends ChartEvent {
  const ChartDepthVisibilityChanged(this.show);
  final bool show;

  @override
  List<Object?> get props => [show];
}

/// Đổi số mốc giá hiển thị ở trục dưới depth chart.
class ChartDepthBottomLabelCountChanged extends ChartEvent {
  const ChartDepthBottomLabelCountChanged(this.count);
  final int count;

  @override
  List<Object?> get props => [count];
}

/// Lưu lại scaleX/scaleY/scrollX — bắn từ `KChartWidget.onChartScaleChanged`.
class ChartScaleSaved extends ChartEvent {
  const ChartScaleSaved(this.scale);
  final KChartScaleState scale;

  @override
  List<Object?> get props => [scale];
}

/// Kéo trái để load thêm nến cũ — bắn từ `KChartWidget.onLoadMore`.
class ChartMoreDataRequested extends ChartEvent {
  const ChartMoreDataRequested(this.isLeft);
  final bool isLeft;

  @override
  List<Object?> get props => [isLeft];
}

/// Bật/tắt realtime WebSocket (subscribe/unsubscribe STOMP topics).
class ChartLiveToggled extends ChartEvent {
  const ChartLiveToggled();
}
