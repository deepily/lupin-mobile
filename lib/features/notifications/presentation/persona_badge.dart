import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../shared/painters/dashed_border_painter.dart';
import '../data/voice_persona.dart';

/// Small round badge showing a session's voice persona emoji on its colour.
///
/// An overflow persona gets a dotted border and an asterisk overlay.
/// A borrowed persona that is not overflow gets a dashed border.
/// Any other persona gets a plain badge.
/// The persona colour always paints, even when the emoji fails to render.
/// A null persona renders nothing.
class PersonaBadge extends StatelessWidget {
  /// Persona to show, or null for no badge.
  final VoicePersona? persona;

  /// Suffix appended to `TestKeys.personaBadgePrefix` so widget tests can find the badge.
  ///
  /// Usually the sender id of the badge's session.
  final String? senderId;

  /// Diameter in logical pixels; tile surfaces use the default and in-card surfaces use 24.
  final double diameter;

  /// Creates a badge for [persona].
  const PersonaBadge( {
    super.key,
    required this.persona,
    this.senderId,
    this.diameter = 40.0,
  } );

  /// The persona's own colour, or null when it has none or the hex is malformed.
  ///
  /// Public because focus-mode bubbles are tinted with the sender's colour too.
  static Color? colorOf( VoicePersona? persona ) => _parseHex( persona?.color );

  /// The same parse for callers holding only the raw hex string.
  ///
  /// The broadcast roster carries `persona_color` without a [VoicePersona].
  static Color? colorOfHex( String? hex ) => _parseHex( hex );

  /// Parses `#RRGGBB` or `#AARRGGBB` into a colour, or null for malformed input.
  ///
  /// The caller falls back to the theme primary colour on null.
  static Color? _parseHex( String? hex ) {
    if ( hex == null ) return null;
    var s = hex.trim();
    if ( s.startsWith( "#" ) ) s = s.substring( 1 );
    if ( s.length == 6 ) s = "FF$s";
    if ( s.length != 8 ) return null;
    final v = int.tryParse( s, radix: 16 );
    return v == null ? null : Color( v );
  }

  @override
  Widget build( BuildContext context ) {
    final p = persona;
    if ( p == null ) return const SizedBox.shrink();

    final theme        = Theme.of( context );
    final bgColor      = _parseHex( p.color ) ?? theme.colorScheme.primary;
    final luminance    = bgColor.computeLuminance();
    final foregroundColor = luminance > 0.5
        ? Colors.black
        : Colors.white;

    final radius = diameter / 2;
    final keyId  = senderId ?? p.voiceId ?? p.name ?? "anon";
    final keyStr = p.overflow
        ? "${TestKeys.personaBadgeDottedPrefix}$keyId"
        : p.borrowed
            ? "${TestKeys.personaBadgeDashedPrefix}$keyId"
            : "${TestKeys.personaBadgePrefix}$keyId";

    final avatar = CircleAvatar(
      key             : Key( keyStr ),
      radius          : radius,
      backgroundColor : bgColor,
      child           : Text(
        p.icon ?? "",
        style: TextStyle(
          fontSize : diameter * 0.5,
          color    : foregroundColor,
        ),
      ),
    );

    final tooltipMessage = p.displayName ?? p.name ?? "";

    Widget content = avatar;
    if ( p.overflow ) {
      // Overflow variant: dotted border plus an asterisk overlay. Overflow wins over
      // borrowed, matching `.persona-badge.overflow` in `notifications.js`. The asterisk
      // keeps the variant identifiable where dotted and dashed look alike at 40px or 24px.
      content = SizedBox(
        width  : diameter,
        height : diameter,
        child  : Stack(
          alignment    : Alignment.center,
          clipBehavior : Clip.none,
          children     : [
            avatar,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: DashedBorderPainter(
                    color      : foregroundColor,
                    cap        : StrokeCap.round,
                    dashLength : 1.5,  // ≈ strokeWidth → round-dot appearance
                  ),
                ),
              ),
            ),
            // Overflow asterisk, top-right of the badge.
            Positioned(
              right : -2,
              top   : -2,
              child : IgnorePointer(
                child: Text(
                  "✱",
                  style: TextStyle(
                    fontSize : diameter * 0.35,
                    color    : foregroundColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else if ( p.borrowed ) {
      content = SizedBox(
        width  : diameter,
        height : diameter,
        child  : Stack(
          alignment: Alignment.center,
          children : [
            avatar,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: DashedBorderPainter(
                    color: foregroundColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if ( tooltipMessage.isEmpty ) return content;
    return Tooltip(
      message       : tooltipMessage,
      triggerMode   : TooltipTriggerMode.longPress,
      preferBelow   : true,
      child         : content,
    );
  }
}
