import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/fleet_models.dart';

/// One seat, as a card rather than a table row.
///
/// 🔴 EIGHT COLUMNS DO NOT FIT ON ONE LINE AT 360 dp, AND THAT IS ARITHMETIC
/// RATHER THAN TASTE. The cascade measured it for the shared task row: 360 dp
/// less 16 dp gutters less a 48 dp interactive target leaves ~86 dp — about
/// twelve characters — once four short fields have taken their share. Fleet
/// Status carries EIGHT fields, two of them free-form (`Who`, `Holding on`),
/// so a horizontal port would truncate every row to the same prefix and the
/// pane could not be read at all.
///
/// ⇒ The eight facts survive; the single-row packing does not. They are laid
/// out in three bands, most-identifying first:
///     1  Who · Role
///     2  State · Holding on · Stuck
///     3  Liveness · % Window · Window
///
/// ⚠️ NOTHING IS DROPPED. All eight are on screen without a scroll or a tap;
/// only the Liveness DETAIL — the raw four ages the web hangs on a hover —
/// lives behind a tap, because a phone has no hover to hang it on.
class FleetRowCard extends StatelessWidget {
  final FleetSession       session;
  final FleetContextRecord context;
  final VoidCallback?      onLivenessTap;

  const FleetRowCard( {
    super.key,
    required this.session,
    required this.context,
    this.onLivenessTap,
  } );

  @override
  Widget build( BuildContext buildContext ) {
    final theme = Theme.of( buildContext );

    return Card(
      key    : Key( "${ TestKeys.fleetStatusRowPrefix }${ session.whoLabel }" ),
      margin : const EdgeInsets.symmetric( horizontal: 8, vertical: 4 ),
      child  : Padding(
        padding : const EdgeInsets.all( 12 ),
        child   : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bandOne( theme ),
            const SizedBox( height: 6 ),
            _bandTwo( theme ),
            const SizedBox( height: 6 ),
            _bandThree( buildContext, theme ),
          ],
        ),
      ),
    );
  }

  /// Band 1 — Who, and the role badge.
  Widget _bandOne( ThemeData theme ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            session.whoLabel,
            style    : theme.textTheme.titleMedium?.copyWith( fontWeight: FontWeight.w600 ),
            overflow : TextOverflow.ellipsis,
          ),
        ),
        const SizedBox( width: 8 ),
        _Badge( label: session.roleLabel, theme: theme ),
      ],
    );
  }

  /// Band 2 — State, Holding on, Stuck.
  Widget _bandTwo( ThemeData theme ) {
    return Wrap(
      spacing     : 12,
      runSpacing  : 4,
      children    : [
        _Field( label: "State",      value: session.stateLabel,   theme: theme ),
        _Field( label: "Holding on", value: session.holdingLabel, theme: theme ),
        _Field( label: "Stuck",      value: session.stuckLabel,   theme: theme ),
      ],
    );
  }

  /// Band 3 — Liveness (tappable), % Window, Window.
  ///
  /// ⚠️ `% Window` AND `Window` ARE TWO FACTS, NOT ONE, and they disagree in
  /// live data. Measured 2026-09-19 against the captured fixture: of ten seats,
  /// seven were fully measured, ONE carried a window size with a null
  /// percentage, one was an IDLE persona reporting null for both, and one had
  /// no persona at all. Each cell therefore formats its own nullable and
  /// neither may stand in for the other — a row legitimately shows "1M" beside
  /// an em dash.
  Widget _bandThree( BuildContext buildContext, ThemeData theme ) {
    return Wrap(
      spacing    : 12,
      runSpacing : 4,
      children   : [
        _livenessCell( buildContext, theme ),
        _Field(
          label : "% Window",
          value : formatConsumptionPct( context.consumptionPctOfWindow ),
          theme : theme,
        ),
        _Field(
          label : "Window",
          value : formatWindowSize( context.windowSize ),
          theme : theme,
        ),
      ],
    );
  }

  /// The Liveness cell — verdict visible, raw ages one tap away.
  ///
  /// 🔴 THE WEB PUTS THE FOUR RAW AGES ON A `title=` HOVER. A phone has no
  /// hover, so the detail is reached by TAP and opens a sheet. A sheet rather
  /// than an in-place expansion is deliberate: opening a route MOVES FOCUS, so
  /// a screen-reader user is taken to the detail and hears it. An in-place
  /// reveal changes the tree under a focus that does not move, which announces
  /// nothing — the same failure mode the plan's arm-twice control has.
  ///
  /// The `Semantics` wrapper gives the target a name and a hint, because the
  /// visible text is a bare verdict word like "LIVE" and a screen reader would
  /// otherwise announce a button with no purpose.
  Widget _livenessCell( BuildContext buildContext, ThemeData theme ) {
    final verdict = session.liveness.verdictLabel;

    return Semantics(
      button          : true,
      label           : "Liveness $verdict for ${ session.whoLabel }",
      hint            : "Shows the raw ages behind this verdict",
      excludeSemantics: true,
      child: InkWell(
        key         : Key( "${ TestKeys.fleetStatusLivenessPrefix }${ session.whoLabel }" ),
        onTap       : onLivenessTap,
        // A 48 dp minimum target: Android's floor, and well above WCAG 2.2
        // SC 2.5.8's 24x24. The web's cell is roughly 20 px, which is a mouse
        // target rather than a thumb one.
        child: ConstrainedBox(
          constraints : const BoxConstraints( minHeight: kMinInteractiveDimension ),
          child       : Row(
            mainAxisSize : MainAxisSize.min,
            children     : [
              _Field( label: "Liveness", value: verdict, theme: theme ),
              const SizedBox( width: 4 ),
              Icon( Icons.info_outline, size: 16, color: theme.hintColor ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A label-over-value pair, so every figure carries the name of what it is.
class _Field extends StatelessWidget {
  final String    label;
  final String    value;
  final ThemeData theme;

  const _Field( { required this.label, required this.value, required this.theme } );

  @override
  Widget build( BuildContext context ) {
    return Column(
      crossAxisAlignment : CrossAxisAlignment.start,
      mainAxisSize       : MainAxisSize.min,
      children           : [
        Text( label, style: theme.textTheme.labelSmall?.copyWith( color: theme.hintColor ) ),
        Text( value, style: theme.textTheme.bodyMedium ),
      ],
    );
  }
}

/// The role badge.
///
/// ⚠️ THE WORD IS THE SIGNAL, NOT THE COLOUR. The web's own note says colour is
/// always redundant with the verdict word or the numeric percent (WCAG 1.4.1);
/// this keeps the word and lets the container carry the tint.
class _Badge extends StatelessWidget {
  final String    label;
  final ThemeData theme;

  const _Badge( { required this.label, required this.theme } );

  @override
  Widget build( BuildContext context ) {
    return Container(
      padding    : const EdgeInsets.symmetric( horizontal: 8, vertical: 2 ),
      decoration : BoxDecoration(
        color        : theme.colorScheme.secondaryContainer,
        borderRadius : BorderRadius.circular( 10 ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
