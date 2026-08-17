import 'package:flutter/material.dart' show Color, TextStyle;

class DepthChartColors {
  /// depth color
  final Color upColor;
  final Color upFillPathColor;
  final Color dnColor;
  final Color dnFillPathColor;

  /// default text color: apply for text at grid
  final Color defaultTextColor;

  ///value border color after selection
  final Color selectBorderColor;

  ///background color when value selected
  final Color selectFillColor;

  ///color of annotation content
  final Color annotationColor;

  ///color of cross dash line
  final Color crossColor;

  /// barrier color
  final Color barrierColor;

  /// constructor chart color
  const DepthChartColors({
    ///depth color
    this.upColor = const Color(0xFF0ECB81),
    this.upFillPathColor = const Color(0x230ECB81),
    this.dnColor = const Color(0xFFF6465D),
    this.dnFillPathColor = const Color(0x23F6465D),

    ///value border color after selection
    this.selectBorderColor = const Color(0xFF909196),
    ///background color when value selected
    this.selectFillColor = const Color(0xFFFFFFFF),

    ///color of annotation content
    this.defaultTextColor = const Color(0xFF909196),
    this.annotationColor = const Color(0xFF222223),
    this.crossColor = const Color(0xFF191919),
    this.barrierColor = const Color(0x21AFAFAF),
  });
}

class DepthChartStyle {
  final double lineWidth;
  final double radius;
  final double strokeWidth;

  final double space;
  final double padding;

  final double dotRadius;

  final double crossWidth;

  /// text style cho nhãn trục (volume bên phải, giá bên dưới). Mặc định
  /// fontSize 10 — cùng convention với `CandleStyle.textStyle`/`VolumeStyle.textStyle`.
  final TextStyle textStyle;

  /// text style cho popup giá/khối lượng khi long-press. Mặc định fontSize 9
  /// (nhỏ hơn [textStyle] vì hiển thị trong popup chật).
  final TextStyle annotationTextStyle;

  const DepthChartStyle({
    this.lineWidth = 1.0,
    this.radius = 4.0,
    this.strokeWidth = 0.6,
    this.space = 2.0,
    this.padding = 6.0,
    this.dotRadius = 5.0,
    this.crossWidth = 0.5,
    this.textStyle = const TextStyle(fontSize: 10),
    this.annotationTextStyle = const TextStyle(fontSize: 9),
  });
}
