import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';

/// The fleet-size cap dial, the one write this pane owns.
///
/// The number on screen is the server's re-read, never the value posted. The spawn path
/// reads the cap fresh from disk. A dial that echoed its input could show a number the
/// fleet is not enforcing. The `onSetCap` callback resolves with the server's answer, and
/// the widget renders whatever the parent hands back as `cap`.
///
/// There is no client-side upper clamp. The ceiling is the server's
/// `cc session fleet size cap maximum` setting, read at call time, and a constant here
/// would drift. The `capMaximum` value only sizes the slider. The floor of 1 is enforced
/// here, because it is in the server's body model.
class FleetCapDial extends StatefulWidget {
  /// The server's enforced cap, or null when unknown.
  final int?                          cap;

  /// The server's reported ceiling, or null; used only to size the slider.
  final int?                          capMaximum;

  /// Applies a new cap; resolves once the parent holds the server's re-read.
  final Future<void> Function( int )  onSetCap;

  /// Creates the dial.
  const FleetCapDial( {
    super.key,
    required this.cap,
    required this.capMaximum,
    required this.onSetCap,
  } );

  @override
  State<FleetCapDial> createState() => _FleetCapDialState();
}

class _FleetCapDialState extends State<FleetCapDial> {
  int?   _pending;
  bool   _saving = false;
  String? _error;

  // The slider's ceiling: the server's reported maximum when given, else a display-only
  // fallback that is never a validation rule.
  int get _max {
    final m = widget.capMaximum;
    if ( m != null && m >= 1 ) return m;
    final c = widget.cap ?? 1;
    return c < 20 ? 20 : c;
  }

  // What the handle sits on: the operator's unapplied drag, else the server's number,
  // else the floor.
  int get _handle => _pending ?? widget.cap ?? 1;

  @override
  void didUpdateWidget( FleetCapDial old ) {
    super.didUpdateWidget( old );
    // The parent handed over a new server value: drop any stale drag so the handle snaps
    // to what is enforced.
    if ( old.cap != widget.cap ) _pending = null;
  }

  Future<void> _apply() async {
    final target = _handle;
    setState( () { _saving = true; _error = null; } );
    try {
      await widget.onSetCap( target );
      // Do not write `target` into local state. The parent re-reads and hands back the
      // server's number; anything else could paint a value the fleet is not enforcing.
      if ( mounted ) setState( () { _pending = null; } );
    } catch ( e ) {
      // On a refusal the handle snaps back to the live value instead of sitting on a
      // number the operator never got.
      if ( mounted ) setState( () { _pending = null; _error = "$e"; } );
    } finally {
      if ( mounted ) setState( () => _saving = false );
    }
  }

  @override
  Widget build( BuildContext context ) {
    final theme   = Theme.of( context );
    final changed = widget.cap != null && _handle != widget.cap;

    return Padding(
      key     : const Key( TestKeys.fleetStatusCapDial ),
      padding : const EdgeInsets.symmetric( vertical: 4 ),
      child   : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text( "Fleet size cap", style: theme.textTheme.labelMedium ),
              const SizedBox( width: 8 ),
              Text(
                key   : const Key( TestKeys.fleetStatusCapValue ),
                "$_handle",
                style : theme.textTheme.titleMedium,
              ),
              const Spacer(),
              if ( _saving )
                const SizedBox(
                  width  : 16,
                  height : 16,
                  child  : CircularProgressIndicator( strokeWidth: 2 ),
                )
              else
                TextButton(
                  key      : const Key( TestKeys.fleetStatusCapApply ),
                  onPressed: changed ? _apply : null,
                  child    : const Text( "Apply" ),
                ),
            ],
          ),
          Semantics(
            label : "Fleet size cap",
            value : "$_handle",
            child : Slider(
              value     : _handle.toDouble().clamp( 1, _max.toDouble() ),
              min       : 1,
              max       : _max.toDouble(),
              divisions : _max > 1 ? _max - 1 : null,
              label     : "$_handle",
              onChanged : _saving
                  ? null
                  : ( v ) => setState( () => _pending = v.round() ),
            ),
          ),
          if ( _error != null )
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith( color: theme.colorScheme.error ),
            ),
        ],
      ),
    );
  }
}
