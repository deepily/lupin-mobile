import 'package:flutter/material.dart';

/// Draws a dashed circular stroke around its boundary rectangle.
///
/// `PersonaBadge` uses it for the borrowed variant, and for the overflow variant with round
/// caps. No other painter or dashed-border package exists in this app.
class DashedBorderPainter extends CustomPainter {
  /// Stroke colour.
  final Color     color;
  /// Stroke width in logical pixels.
  final double    strokeWidth;
  /// Length of each dash along the circle, in logical pixels.
  final double    dashLength;
  /// Length of each gap between dashes, in logical pixels.
  final double    gapLength;
  /// End shape of each dash.
  ///
  /// The default butt cap draws plain dashes. Round caps with a dash length near
  /// [strokeWidth] draw round dots, which the overflow badge uses.
  final StrokeCap cap;

  /// Creates a painter with the given colour and optional dash geometry.
  const DashedBorderPainter( {
    required this.color,
    this.strokeWidth = 1.5,
    this.dashLength  = 4.0,
    this.gapLength   = 3.0,
    this.cap         = StrokeCap.butt,
  } );

  @override
  void paint( Canvas canvas, Size size ) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = strokeWidth
      ..style       = PaintingStyle.stroke
      ..strokeCap   = cap;

    final radius     = ( size.shortestSide / 2 ) - ( strokeWidth / 2 );
    final center     = Offset( size.width / 2, size.height / 2 );
    final dashAngle  = dashLength / radius;
    final gapAngle   = gapLength / radius;
    final stepAngle  = dashAngle + gapAngle;
    const twoPi      = 2 * 3.141592653589793;

    var a = 0.0;
    while ( a < twoPi ) {
      canvas.drawArc(
        Rect.fromCircle( center: center, radius: radius ),
        a,
        dashAngle,
        false,
        paint,
      );
      a += stepAngle;
    }
  }

  @override
  bool shouldRepaint( covariant DashedBorderPainter old ) =>
      old.color       != color
      || old.strokeWidth != strokeWidth
      || old.dashLength  != dashLength
      || old.gapLength   != gapLength
      || old.cap         != cap;
}
