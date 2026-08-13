import 'package:flutter/material.dart' show Color, TextStyle;
import '../indicator/indicator_style.dart';
import 'live_price_style.dart';

export 'live_price_style.dart';

/// Kiểu vẽ thân nến (candlestick mode, không áp dụng cho line chart) — cùng
/// bộ tùy chọn "Candle style" của TradingView/Binance: tô đặc (mặc định) hay
/// để rỗng ruột (chỉ vẽ viền) theo chiều tăng/giảm.
///
/// "Rỗng ruột" xác định theo `close` so với `open` của CHÍNH nến đó (không
/// phải so với close phiên trước) — nến tăng = `close > open`. Bấc nến
/// (high-low) LUÔN vẽ đặc bất kể [CandleBodyStyle] là gì; chỉ phần thân
/// (open-close) đổi giữa tô đặc/chỉ viền.
enum CandleBodyStyle {
  /// Solid Candles — mặc định, luôn tô đặc cả 2 chiều (hành vi trước khi có
  /// field này).
  solid,

  /// Hollow Candles (Up) — nến tăng (`close > open`) chỉ vẽ viền, nến giảm
  /// vẫn tô đặc.
  hollowUp,

  /// Hollow Candles (Down) — nến giảm (`close < open`) chỉ vẽ viền, nến tăng
  /// vẫn tô đặc.
  hollowDown,

  /// Hollow Candles — cả nến tăng lẫn giảm đều chỉ vẽ viền.
  hollow,
}

/// Màu cho main chart (nến hoặc line chart — 2 cách vẽ khác nhau của cùng
/// 1 chuỗi giá, `isLine` chọn cái nào). Tách khỏi `KChartColors` để dễ custom
/// riêng, tương tự các `XxxStyle` của indicator.
class CandleStyle {
  /// màu nến tăng (candlestick mode) — cũng dùng lại cho chấm SAR khi trend tăng.
  final Color upColor;

  /// màu nến giảm (candlestick mode) — cũng dùng lại cho chấm SAR khi trend giảm.
  final Color dnColor;

  /// màu đường line chart (`isLine = true`).
  final Color kLineColor;

  /// gradient tô dưới đường line chart (`isLine = true`) — 2 màu, trên đậm dưới trong suốt.
  final List<Color> kLineFillColors;

  /// text style cho main chart: trục giá/thời gian, crosshair, label indicator,
  /// max/min, now-price. Mặc định fontSize 10.
  final TextStyle textStyle;

  /// kiểu vẽ thân nến — xem [CandleBodyStyle]. Mặc định `solid` (tô đặc,
  /// giữ nguyên hành vi cũ).
  final CandleBodyStyle bodyStyle;

  const CandleStyle({
    this.upColor = const Color(0xFF0ABE82),
    this.dnColor = const Color(0xFFF54B55),
    this.kLineColor = const Color(0xFF217AFF),
    this.kLineFillColors = const [Color(0x80217aff), Color(0x00217AFF)],
    this.textStyle = const TextStyle(fontSize: 10),
    this.bodyStyle = CandleBodyStyle.solid,
  });
}

/// Màu cho panel volume (`VolRenderer`). Tách khỏi `KChartColors` để dễ custom
/// riêng, tương tự các `XxxStyle` của indicator.
class VolumeStyle {
  /// màu cột volume khi nến tăng.
  final Color upColor;

  /// màu cột volume khi nến giảm.
  final Color dnColor;

  /// màu đường + label MA5 của volume.
  final Color ma5Color;

  /// màu đường + label MA10 của volume.
  final Color ma10Color;

  /// text style riêng cho panel volume (nhãn `VOL/MA5/MA10` + trục phải).
  /// Tách khỏi `CandleStyle.textStyle` vì volume là panel độc lập, có thể
  /// muốn fontSize khác main chart. Mặc định fontSize 10.
  final TextStyle textStyle;

  const VolumeStyle({
    this.upColor = const Color(0xFF0ABE82),
    this.dnColor = const Color(0xFFF54B55),
    this.ma5Color = const Color(0xFFFFC634),
    this.ma10Color = const Color(0xff35cdac),
    this.textStyle = const TextStyle(fontSize: 10),
  });
}

/// KChartColors
///
/// Note:
/// If you need to apply multi theme, you need to change at least the colors related to the text, border and background color
/// Ex:
/// Background: bgColor, selectFillColor
/// Border
/// Text
///
class KChartColors {
  /// the background color of base chart
  final Color bgColor;

  /// màu main chart (nến hoặc line chart) — xem [CandleStyle].
  final CandleStyle candleStyle;

  /// màu panel volume — xem [VolumeStyle].
  final VolumeStyle volumeStyle;

  /// default text color: apply for text at grid
  final Color defaultTextColor;

  /// màu now-price (đường + label giá hiện tại) — xem [LivePriceStyle].
  final LivePriceStyle livePriceStyle;

  /// trend color
  final Color trendLineColor;

  ///value border color after selection
  final Color selectBorderColor;

  ///background color when value selected
  final Color selectFillColor;

  ///color of grid
  final Color gridColor;

  /// color of the horizontal & vertical cross line
  final Color crossColor;

  /// text color
  final Color crossTextColor;

  ///The color of the maximum and minimum values in the current display
  final Color maxColor;
  final Color minColor;

  // ── Style riêng từng indicator — gom lại 1 chỗ để dễ custom màu toàn bộ ──
  // Instance nào trong mainIndicators/secondaryIndicators tự truyền
  // `indicatorStyle` riêng (khác const mặc định) thì KHÔNG bị các field này
  // ghi đè — xem `applyIndicatorColorStyles` trong indicator_template.dart.

  /// Style cho `MAIndicator`.
  final MAStyle maStyle;

  /// Style cho `EMAIndicator` — cùng type `MAStyle` với [maStyle] nhưng field
  /// riêng để MA và EMA có thể tô màu khác nhau.
  final MAStyle emaStyle;

  /// Style cho `BOLLIndicator`.
  final BOLLStyle bollStyle;

  /// Style cho `SARIndicator`.
  final SARStyle sarStyle;

  /// Style cho `ZigZagIndicator`.
  final ZigZagStyle zigzagStyle;

  /// Style cho `SuperTrendIndicator`.
  final SuperTrendStyle superTrendStyle;

  /// Style cho `AVLIndicator`.
  final AVLStyle avlStyle;

  /// Style cho `IchimokuIndicator`.
  final IchimokuStyle ichimokuStyle;

  /// Style cho `MACDIndicator`.
  final MACDStyle macdStyle;

  /// Style cho `KDJIndicator`.
  final KDJStyle kdjStyle;

  /// Style cho `RSIIndicator`.
  final RSIStyle rsiStyle;

  /// Style cho `WRIndicator`.
  final WRStyle wrStyle;

  /// Style cho `CCIIndicator`.
  final CCIStyle cciStyle;

  /// Style cho `OBVIndicator`.
  final OBVStyle obvStyle;

  /// Style cho `TRIXIndicator`.
  final TRIXStyle trixStyle;

  /// Style cho `MTMIndicator`.
  final MTMStyle mtmStyle;

  /// Style cho `StochRSIIndicator`.
  final StochRSIStyle stochRsiStyle;

  /// Style cho `BRARIndicator`.
  final BRARStyle brarStyle;

  /// Style cho `BIASIndicator`.
  final BIASStyle biasStyle;

  /// Style cho `PSYIndicator`.
  final PSYStyle psyStyle;

  /// Style cho `ATRIndicator`.
  final ATRStyle atrStyle;

  /// constructor chart color
  const KChartColors({
    this.bgColor = const Color(0xffffffff),
    this.candleStyle = const CandleStyle(),
    this.volumeStyle = const VolumeStyle(),
    this.defaultTextColor = const Color(0xFF909196),
    this.livePriceStyle = const LivePriceStyle(),

    /// trend color
    this.trendLineColor = const Color(0xFFF89215),

    ///value border color after selection
    this.selectBorderColor = const Color(0xFF222223),

    ///background color when value selected
    this.selectFillColor = const Color(0xffffffff),

    ///color of grid
    this.gridColor = const Color(0xFFD1D3DB),

    ///color of annotation content
    this.crossColor = const Color(0xFF191919),
    this.crossTextColor = const Color(0xFF222223),

    ///The color of the maximum and minimum values in the current display
    this.maxColor = const Color(0xFF222223),
    this.minColor = const Color(0xFF222223),

    /// style riêng từng indicator
    this.maStyle = const MAStyle(),
    this.emaStyle = const MAStyle(),
    this.bollStyle = const BOLLStyle(),
    this.sarStyle = const SARStyle(),
    this.zigzagStyle = const ZigZagStyle(),
    this.superTrendStyle = const SuperTrendStyle(),
    this.avlStyle = const AVLStyle(),
    this.ichimokuStyle = const IchimokuStyle(),
    this.macdStyle = const MACDStyle(),
    this.kdjStyle = const KDJStyle(),
    this.rsiStyle = const RSIStyle(),
    this.wrStyle = const WRStyle(),
    this.cciStyle = const CCIStyle(),
    this.obvStyle = const OBVStyle(),
    this.trixStyle = const TRIXStyle(),
    this.mtmStyle = const MTMStyle(),
    this.stochRsiStyle = const StochRSIStyle(),
    this.brarStyle = const BRARStyle(),
    this.biasStyle = const BIASStyle(),
    this.psyStyle = const PSYStyle(),
    this.atrStyle = const ATRStyle(),
  });

  /// Trả về bản sao, override đúng field được truyền vào, giữ nguyên phần
  /// còn lại — tránh phải liệt kê tay từng field khi chỉ muốn đổi 1-2 field
  /// (vd giữ theme màu nền/chữ, chỉ đổi màu 1 indicator).
  KChartColors copyWith({
    Color? bgColor,
    CandleStyle? candleStyle,
    VolumeStyle? volumeStyle,
    Color? defaultTextColor,
    LivePriceStyle? livePriceStyle,
    Color? trendLineColor,
    Color? selectBorderColor,
    Color? selectFillColor,
    Color? gridColor,
    Color? crossColor,
    Color? crossTextColor,
    Color? maxColor,
    Color? minColor,
    MAStyle? maStyle,
    MAStyle? emaStyle,
    BOLLStyle? bollStyle,
    SARStyle? sarStyle,
    ZigZagStyle? zigzagStyle,
    SuperTrendStyle? superTrendStyle,
    AVLStyle? avlStyle,
    IchimokuStyle? ichimokuStyle,
    MACDStyle? macdStyle,
    KDJStyle? kdjStyle,
    RSIStyle? rsiStyle,
    WRStyle? wrStyle,
    CCIStyle? cciStyle,
    OBVStyle? obvStyle,
    TRIXStyle? trixStyle,
    MTMStyle? mtmStyle,
    StochRSIStyle? stochRsiStyle,
    BRARStyle? brarStyle,
    BIASStyle? biasStyle,
    PSYStyle? psyStyle,
    ATRStyle? atrStyle,
  }) {
    return KChartColors(
      bgColor: bgColor ?? this.bgColor,
      candleStyle: candleStyle ?? this.candleStyle,
      volumeStyle: volumeStyle ?? this.volumeStyle,
      defaultTextColor: defaultTextColor ?? this.defaultTextColor,
      livePriceStyle: livePriceStyle ?? this.livePriceStyle,
      trendLineColor: trendLineColor ?? this.trendLineColor,
      selectBorderColor: selectBorderColor ?? this.selectBorderColor,
      selectFillColor: selectFillColor ?? this.selectFillColor,
      gridColor: gridColor ?? this.gridColor,
      crossColor: crossColor ?? this.crossColor,
      crossTextColor: crossTextColor ?? this.crossTextColor,
      maxColor: maxColor ?? this.maxColor,
      minColor: minColor ?? this.minColor,
      maStyle: maStyle ?? this.maStyle,
      emaStyle: emaStyle ?? this.emaStyle,
      bollStyle: bollStyle ?? this.bollStyle,
      sarStyle: sarStyle ?? this.sarStyle,
      zigzagStyle: zigzagStyle ?? this.zigzagStyle,
      superTrendStyle: superTrendStyle ?? this.superTrendStyle,
      avlStyle: avlStyle ?? this.avlStyle,
      ichimokuStyle: ichimokuStyle ?? this.ichimokuStyle,
      macdStyle: macdStyle ?? this.macdStyle,
      kdjStyle: kdjStyle ?? this.kdjStyle,
      rsiStyle: rsiStyle ?? this.rsiStyle,
      wrStyle: wrStyle ?? this.wrStyle,
      cciStyle: cciStyle ?? this.cciStyle,
      obvStyle: obvStyle ?? this.obvStyle,
      trixStyle: trixStyle ?? this.trixStyle,
      mtmStyle: mtmStyle ?? this.mtmStyle,
      stochRsiStyle: stochRsiStyle ?? this.stochRsiStyle,
      brarStyle: brarStyle ?? this.brarStyle,
      biasStyle: biasStyle ?? this.biasStyle,
      psyStyle: psyStyle ?? this.psyStyle,
      atrStyle: atrStyle ?? this.atrStyle,
    );
  }
}

/// `final` — không cho subclass override các hằng số layout (đặc biệt
/// [pointWidth]). Nhiều nơi trong renderer (vd `IchimokuIndicator.pointWidth`
/// trong lib/indicator/main/ichimoku_indicator.dart) giả định `pointWidth`
/// LUÔN là 11.0 bất kể instance nào; nếu cho phép subclass đổi giá trị này,
/// những chỗ đó sẽ lệch pixel âm thầm không có tín hiệu lỗi nào.
final class KChartStyle {
  final double topPadding = 20.0;

  final double bottomPadding = 16.0;

  final double childPadding = 12.0;

  final double space = 4.0;

  ///point-to-point distance
  final double pointWidth = 11.0;

  ///candle width
  final double candleWidth = 8.5;
  final double candleLineWidth = 1.0;

  ///vol column width
  final double volWidth = 8.5;

  /// Độ trong suốt của cột volume (0.0–1.0). Mặc định 1.0 = đặc.
  final double volBarOpacity;

  ///vertical-horizontal cross line width
  final double crossWidth = 0.8;

  ///(line length - space line - thickness) of the current price
  // final double nowPriceLineLength = 4.5;
  // final double nowPriceLineSpan = 3.5;
  final double nowPriceLineWidth = 0.8;

  /// Border width : apply for cross & now price
  final double borderWidth = 0.5;

  final int gridRows = 4;
  final int gridColumns = 6;

  ///customize the time below
  final List<String>? dateTimeFormat;

  const KChartStyle([this.dateTimeFormat, this.volBarOpacity = 1.0]);
}
