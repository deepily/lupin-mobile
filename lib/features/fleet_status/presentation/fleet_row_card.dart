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

  /// Open the Live Console for this seat. Null when this caller may not watch it.
  ///
  /// 🔴 NULL IS THE ONLY WAY THE BUTTON HIDES, AND THAT IS ON PURPOSE. The pane decides
  /// watchability by joining the roster projection; this widget does not re-derive the
  /// rule, does not read `transcript_watchable` itself, and has no opinion about admin.
  /// One field, one decision point — §3 says both watch affordances in this system read
  /// the server's single `transcript_watchable` so that neither client invents its own
  /// answer, and a widget that also had a say would be a third answer.
  ///
  /// ⚠️ AND A HIDDEN BUTTON IS NOT A SECURITY BOUNDARY. §5: "a refused watch is expected,
  /// not exceptional… the button only hides a refusal; the server is the gate." A stale
  /// roster, an admin role revoked between the poll and the tap, or a deep link into the
  /// route all still produce a refusal, which the console screen handles.
  final VoidCallback?      onWatchTap;

  const FleetRowCard( {
    super.key,
    required this.session,
    required this.context,
    this.onLivenessTap,
    this.onWatchTap,
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
        // A SIBLING in this Wrap, after the Window field — see `_watchButton`'s docstring
        // for why it cannot live inside `_livenessCell`.
        if ( onWatchTap != null ) _watchButton( theme ),
      ],
    );
  }

  /// Watch this seat's console. Ruling Q9's entry point, and the only one in v1.
  ///
  /// 🔴 IT IS A SIBLING IN BAND THREE, NOT A CHILD OF `_livenessCell`, AND AN EARLIER
  /// DRAFT PUT IT THERE. That draft said "beside `Icons.info_outline`" — which is inside
  /// [_livenessCell], whose wrapper is
  /// `Semantics( button: true, label: "Liveness …", excludeSemantics: true )` around an
  /// `InkWell` whose tap is `onLivenessTap`. Two things would have followed, both bad:
  /// `excludeSemantics: true` **drops every descendant's semantics**, so a screen-reader
  /// user would never have found the button at all; and it would have been inside the
  /// liveness hit target, so tapping it could open the liveness sheet instead.
  ///
  /// ⇒ Its own `Semantics( button: true, label: "Watch console for <who>" )`, its own hit
  /// target, its own key. C5.9's semantics arm asserts the node is **not** a descendant of
  /// the liveness `Semantics` node, and names moving it back inside as the negative
  /// control — so this is a decision with a test that fails if it is undone. (C-4.)
  ///
  /// The fleet row is the only entry point in v1: Focus-mode and Inbox headers are keyed
  /// on `sender_id` (`#<8hex>`), which cannot supply the full `cc_session_id` the stream
  /// needs, so they are out of v1 rather than half-designed (C-5).
  Widget _watchButton( ThemeData theme ) {
    return Semantics(
      button : true,
      label  : "Watch console for ${ session.whoLabel }",
      child  : IconButton(
        key       : Key( "${ TestKeys.fleetStatusWatchPrefix }${ session.whoLabel }" ),
        icon      : const Icon( Icons.terminal, size: 20 ),
        tooltip   : "Watch console",
        onPressed : onWatchTap,
        // The same 48 dp thumb floor the liveness cell takes: Android's minimum, and well
        // above WCAG 2.2 SC 2.5.8's 24x24. `IconButton`'s own default is 48, stated here
        // so a future `visualDensity` change cannot quietly shrink it.
        constraints : const BoxConstraints(
          minWidth  : kMinInteractiveDimension,
          minHeight : kMinInteractiveDimension,
        ),
        padding   : EdgeInsets.zero,
        color     : theme.colorScheme.primary,
      ),
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
