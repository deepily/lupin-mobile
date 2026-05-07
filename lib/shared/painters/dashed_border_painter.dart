import 'package:flutter/material.dart';

/// Draws a dashed circular stroke around its boundary `Rect`. Used by
/// `PersonaBadge` (Phase 3 §4) to render the `borrowed=true` variant per
/// `Q2` (FROZEN 2026-05-06).
///
/// Per `Q9` (FROZEN at REUSE pre-pass 2026-05-06) — confirmed genuinely-new:
/// no existing `CustomPainter` subclass in the mobile tree and no
/// dashed-border package in `pubspec.yaml`.
class DashedBorderPainter extends CustomPainter {
  final Color  color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  const DashedBorderPainter( {
    required this.color,
    this.strokeWidth = 1.5,
    this.dashLength  = 4.0,
    this.gapLength   = 3.0,
  } );

  @override
  void paint( Canvas canvas, Size size ) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = strokeWidth
      ..style       = PaintingStyle.stroke;

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
      || old.gapLength   != gapLength;
}
