import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/fleet_models.dart';

/// One seat, as a card rather than a table row.
///
/// Eight columns do not fit one line at 360 dp. Gutters and a 48 dp target leave about
/// 86 dp, roughly twelve characters, and two fields (`Who`, `Holding on`) are free text.
/// A horizontal layout would truncate every row to the same prefix. All eight facts stay
/// on screen, in three bands: Who and Role; State, Holding on and Stuck; Liveness,
/// % Window and Window. Only the raw liveness ages sit behind a tap.
class FleetRowCard extends StatelessWidget {
  /// The seat to show.
  final FleetSession       session;

  /// The seat's context-window figures.
  final FleetContextRecord context;

  /// Called when the Liveness cell is tapped, to show the raw ages.
  final VoidCallback?      onLivenessTap;

  /// Opens the Live Console for this seat; null when this caller may not watch it.
  ///
  /// Null is the only way the button hides. The pane decides watchability by joining the
  /// roster projection. This widget does not re-derive the rule or read
  /// `transcript_watchable`, because a widget with its own say would be a third answer.
  /// A hidden button is not a security boundary. A stale roster, a revoked admin role or
  /// a deep link still produces a refusal, which the console screen handles.
  final VoidCallback?      onWatchTap;

  /// Creates the card.
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

  // Band 1: Who, and the role badge.
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

  // Band 2: State, Holding on, Stuck.
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

  // Band 3: Liveness (tappable), % Window, Window. The two window cells are two facts
  // that disagree in live data: a seat can have a window size with a null percentage, an
  // idle persona reports null for both, and a row can have no persona. Each cell formats
  // its own nullable, so a row can show "1M" beside an em dash.
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
        // A sibling in this Wrap, after the Window field; see `_watchButton` for why it
        // cannot live inside `_livenessCell`.
        if ( onWatchTap != null ) _watchButton( theme ),
      ],
    );
  }

  // The Watch console button, the only entry point in v1. It is a sibling in band three,
  // not a child of `_livenessCell`. That cell is wrapped in
  // `Semantics( button: true, excludeSemantics: true )` around an `InkWell` whose tap is
  // `onLivenessTap`. `excludeSemantics: true` drops every descendant's semantics, so a
  // screen-reader user would never find a button placed there, and a tap on it could open
  // the liveness sheet. So it has its own `Semantics`, hit target and key. The semantics
  // test asserts the node is not a descendant of the liveness node. Focus-mode and Inbox
  // headers are keyed on `sender_id` (`#<8hex>`), which cannot supply the full
  // `cc_session_id` the stream needs, so they are not entry points in v1.
  Widget _watchButton( ThemeData theme ) {
    return Semantics(
      button : true,
      label  : "Watch console for ${ session.whoLabel }",
      child  : IconButton(
        key       : Key( "${ TestKeys.fleetStatusWatchPrefix }${ session.whoLabel }" ),
        icon      : const Icon( Icons.terminal, size: 20 ),
        tooltip   : "Watch console",
        onPressed : onWatchTap,
        // The same 48 dp thumb floor as the liveness cell: Android's minimum, well above
        // WCAG 2.2 SC 2.5.8's 24x24. `IconButton` defaults to 48; stating it keeps a future
        // `visualDensity` change from shrinking it.
        constraints : const BoxConstraints(
          minWidth  : kMinInteractiveDimension,
          minHeight : kMinInteractiveDimension,
        ),
        padding   : EdgeInsets.zero,
        color     : theme.colorScheme.primary,
      ),
    );
  }

  // The Liveness cell: verdict visible, raw ages one tap away. The web shows the raw ages
  // on a `title=` hover; a phone has no hover, so a tap opens a sheet. A sheet, not an
  // in-place expansion, because opening a route moves focus, so a screen-reader user
  // hears the detail. An in-place reveal changes the tree under a focus that does not
  // move and announces nothing. The `Semantics` wrapper gives the target a name and a
  // hint, because the visible text is a bare verdict word such as "LIVE".
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
        // A 48 dp minimum target: Android's floor, well above WCAG 2.2 SC 2.5.8's 24x24.
        // The web's cell is roughly 20 px, a mouse target and not a thumb one.
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

// A label-over-value pair, so every figure carries the name of what it is.
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

// The role badge. The word is the signal and the colour is only a tint: colour is always
// redundant with the verdict word or the numeric percent (WCAG 1.4.1).
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
