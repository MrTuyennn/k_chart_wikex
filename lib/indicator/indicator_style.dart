import 'package:flutter/material.dart' show Color, TextStyle;

class IndicatorStyle {
  final double lineWidth;
  final double strokeWidth;

  /// text style cho label indicator (vẽ qua `drawFigure`). Mặc định fontSize
  /// 10 — cùng convention với `CandleStyle.textStyle`/`VolumeStyle.textStyle`.
  final TextStyle textStyle;

  const IndicatorStyle({
    this.lineWidth = 1.0,
    this.strokeWidth = 0.8,
    this.textStyle = const TextStyle(fontSize: 10),
  });
}

class MAStyle extends IndicatorStyle {
  final List<Color> maColors;
  const MAStyle({
    this.maColors = const [
      Color(0xFFFFC634),
      Color(0xff35cdac),
      Color(0xffb48ee3),
      Color(0xffE11D74),
      Color(0xFFF7931A),
      Color(0xFF127ECC),
    ],
    super.textStyle,
  });

  /// get MA color via index
  Color getMAColor(int index) {
    if (index >= maColors.length) {
      return maColors[index % maColors.length];
    }
    return maColors[index];
  }
}

class BOLLStyle extends IndicatorStyle {
  final Color bollColor;
  final Color ubColor;
  final Color lbColor;
  final Color fillColor;

  const BOLLStyle({
    this.bollColor = const Color(0xFFF7931A),
    this.ubColor = const Color(0xFFFFC634),
    this.lbColor = const Color(0xFFFFC634),
    this.fillColor = const Color(0x12FFC634),
    super.textStyle,
  });
}

class SARStyle extends IndicatorStyle {
  /// Màu chấm/label khi SAR đang ở dưới giá (xu hướng tăng).
  final Color upColor;

  /// Màu chấm/label khi SAR đang ở trên giá (xu hướng giảm).
  final Color dnColor;

  final double radius;

  const SARStyle({
    this.upColor = const Color(0xFF0ECB81),
    this.dnColor = const Color(0xFFF6465D),
    this.radius = 2.0,
    super.strokeWidth = 0.8,
    super.textStyle,
  });
}

class SuperTrendStyle extends IndicatorStyle {
  final Color upColor;
  final Color dnColor;
  final Color upFillColor;
  final Color dnFillColor;

  const SuperTrendStyle({
    this.upColor = const Color(0xFF0ECB81),
    this.dnColor = const Color(0xFFF6465D),
    this.upFillColor = const Color(0x260ECB81),
    this.dnFillColor = const Color(0x26F6465D),
    super.lineWidth = 1.5,
    super.textStyle,
  });
}

class CCIStyle extends IndicatorStyle {
  final Color cciColor;

  const CCIStyle({this.cciColor = const Color(0xFFFFC634), super.textStyle});
}

class RSIStyle extends IndicatorStyle {
  final Color rsiColor;

  const RSIStyle({this.rsiColor = const Color(0xFFFFC634), super.textStyle});
}

class WRStyle extends IndicatorStyle {
  final Color wrColor;

  const WRStyle({this.wrColor = const Color(0xFFFFC634), super.textStyle});
}

class KDJStyle extends IndicatorStyle {
  final Color kColor;
  final Color dColor;
  final Color jColor;

  const KDJStyle({
    this.kColor = const Color(0xFFFFC634),
    this.dColor = const Color(0xff35cdac),
    this.jColor = const Color(0xffb48ee3),
    super.textStyle,
  });
}

class MACDStyle extends IndicatorStyle {
  final Color upColor;
  final Color dnColor;

  final Color macdColor;
  final Color difColor;
  final Color deaColor;

  final double macdWidth;

  const MACDStyle({
    this.upColor = const Color(0xFF0ECB81),
    this.dnColor = const Color(0xFFF6465D),
    this.macdColor = const Color(0xFFFFC634),
    this.difColor = const Color(0xff35cdac),
    this.deaColor = const Color(0xffb48ee3),
    this.macdWidth = 8.5,
    super.textStyle,
  });
}

class ZigZagStyle extends IndicatorStyle {
  final Color zigzagColor;

  const ZigZagStyle({
    this.zigzagColor = const Color(0xFFFFC634),
    super.lineWidth = 1.0,
    super.textStyle,
  });
}

class AVLStyle extends IndicatorStyle {
  final Color avlColor;

  const AVLStyle({
    this.avlColor = const Color(0xFFFFC634),
    super.lineWidth = 1.0,
    super.textStyle,
  });
}

class TRIXStyle extends IndicatorStyle {
  final Color trixColor;
  final Color trixMaColor;

  const TRIXStyle({
    this.trixColor = const Color(0xFFFFC634),
    this.trixMaColor = const Color(0xff35cdac),
    super.textStyle,
  });
}

class StochRSIStyle extends IndicatorStyle {
  final Color kColor;
  final Color dColor;

  const StochRSIStyle({
    this.kColor = const Color(0xFFFFC634),
    this.dColor = const Color(0xff35cdac),
    super.textStyle,
  });
}

class MTMStyle extends IndicatorStyle {
  final Color mtmColor;
  final Color mtmMaColor;

  const MTMStyle({
    this.mtmColor = const Color(0xFFFFC634),
    this.mtmMaColor = const Color(0xff35cdac),
    super.textStyle,
  });
}

class BRARStyle extends IndicatorStyle {
  final Color arColor;
  final Color brColor;

  const BRARStyle({
    this.arColor = const Color(0xFFFFC634),
    this.brColor = const Color(0xff35cdac),
    super.textStyle,
  });
}

class BIASStyle extends IndicatorStyle {
  final List<Color> biasColors;

  const BIASStyle({
    this.biasColors = const [
      Color(0xFFFFC634),
      Color(0xff35cdac),
      Color(0xffb48ee3),
    ],
    super.textStyle,
  });

  /// get BIAS color via index — cùng pattern `MAStyle.getMAColor`.
  Color getBiasColor(int index) {
    if (index >= biasColors.length) {
      return biasColors[index % biasColors.length];
    }
    return biasColors[index];
  }
}

class PSYStyle extends IndicatorStyle {
  final Color psyColor;
  final Color maPsyColor;

  const PSYStyle({
    this.psyColor = const Color(0xFFFFC634),
    this.maPsyColor = const Color(0xff35cdac),
    super.textStyle,
  });
}

class IchimokuStyle extends IndicatorStyle {
  final Color tenkanColor;
  final Color kijunColor;
  final Color chikouColor;

  /// màu viền Span A — cũng dùng khi mây tăng (Span A > Span B).
  final Color spanAColor;

  /// màu viền Span B — cũng dùng khi mây giảm (Span B > Span A).
  final Color spanBColor;

  /// màu tô mây khi Span A > Span B (mây tăng).
  final Color cloudUpColor;

  /// màu tô mây khi Span B > Span A (mây giảm).
  final Color cloudDownColor;

  const IchimokuStyle({
    this.tenkanColor = const Color(0xFFFFC634),
    this.kijunColor = const Color(0xffb48ee3),
    this.chikouColor = const Color(0xff35cdac),
    this.spanAColor = const Color(0xFF0ECB81),
    this.spanBColor = const Color(0xFFF6465D),
    this.cloudUpColor = const Color(0x260ECB81),
    this.cloudDownColor = const Color(0x26F6465D),
    super.textStyle,
  });
}

class OBVStyle extends IndicatorStyle {
  final Color obvColor;
  final Color signalColor;

  const OBVStyle({
    this.obvColor = const Color(0xFF217AFF),
    this.signalColor = const Color(0xFFFFC634),
    super.textStyle,
  });
}

class ATRStyle extends IndicatorStyle {
  final Color atrColor;
  final Color atrMaColor;

  const ATRStyle({
    this.atrColor = const Color(0xFFFF9800),
    this.atrMaColor = const Color(0xFF00BCD4),
    super.textStyle,
  });
}
