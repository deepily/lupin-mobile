import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../shared/painters/dashed_border_painter.dart';
import '../data/voice_persona.dart';

/// Renders the per-session voice persona as a small badge — emoji glyph on
/// a colored circular background. Wraps `CircleAvatar` per the REUSE pre-pass
/// `extend-existing` finding (sibling pattern at `inbox_screen.dart:141`).
///
/// **Three render variants** (based on `VoicePersona` flags):
/// - `overflow=true` (any `borrowed`): **dotted** border + `✱` glyph overlay
///   (Section C / Phase 3, 2026-05-23 notif-client-sync). Overflow takes
///   precedence over borrowed per the web composition rule (mirrors
///   `.persona-badge.overflow` precedence in `notifications.js`). The ✱ glyph
///   (AC-C2) is the load-bearing disambiguator; the perceptual dotted-vs-dashed
///   distinctness at small diameters is AC-C5 (on-device VP, deferred to the
///   laptop pipeline per `feedback_dev_server_laptop_split`).
/// - `borrowed=true, overflow=false`: **dashed** border via `DashedBorderPainter`
///   per `Q2` (FROZEN 2026-05-06).
/// - both false: plain badge.
///
/// **Failure-mode contract** (per Pass 1 finding F9, applied 2026-05-06):
/// the badge ALWAYS renders with the persona color background regardless of
/// emoji glyph rendering success. If the emoji codepoint is broken/tofu/
/// substituted, the badge still presents the persona color (the primary
/// disambiguator). No crash. No fallback to letter substitution — color-only
/// is acceptable degradation.
///
/// Null persona → renders `SizedBox.shrink()` (no badge in tree, per test 3.2).
class PersonaBadge extends StatelessWidget {
  final VoicePersona? persona;

  /// Stable identifier suffix appended to `TestKeys.personaBadgePrefix` for
  /// widget-test finders. Typically the `senderId` for the badge's session.
  final String? senderId;

  /// Diameter in logical pixels. `CircleAvatar` default radius is 20 (40px
  /// diameter); badges in tile-sized surfaces use the default; in-card
  /// surfaces (by-date item) shrink to 24.
  final double diameter;

  const PersonaBadge( {
    super.key,
    required this.persona,
    this.senderId,
    this.diameter = 40.0,
  } );

  /// Convert `#RRGGBB` or `#AARRGGBB` hex strings to `Color`. Returns null on
  /// any malformed input — caller falls back to the theme primary color so
  /// the badge still renders per the failure-mode contract.
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
      // Section C (Phase 3, 2026-05-23 notif-client-sync) — overflow variant:
      // dotted border + ✱ glyph overlay. Overflow takes precedence over
      // borrowed per the web composition rule (mirrors `.persona-badge.overflow`
      // precedence in `notifications.js`). The ✱ glyph (AC-C2) is the
      // load-bearing disambiguator — guarantees the variant is identifiable
      // even if AC-C5's perceptual dotted-vs-dashed distinction fails at
      // small badge diameters (40px / 24px).
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
            // ✱ overflow glyph — top-right of the badge.
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
