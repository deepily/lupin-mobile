import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';

/// The fleet-size cap dial — the one write this pane owns.
///
/// 🔴 THE PLAN CALLED THIS PANE READ-ONLY, IN TWO PLACES, AND IT IS NOT.
/// `FleetStatusStore.setSizeCap()` issues `PUT /api/arbiter/fleet-size-cap`
/// (`FleetStatusStore.ts:189`) wired to a live slider
/// (`FleetStatusRenderer.ts:200-203`, `:315`). Shipping Fleet Status without
/// the dial would drop the pane's only operator lever.
///
/// 🔴 THE NUMBER ON SCREEN IS THE SERVER'S RE-READ, NEVER THE VALUE POSTED
/// (`FleetStatusStore.ts:185-188`). This was proven live on 2026-09-19: the cap
/// sat at 5 with the fleet already at 6, so no reviewer could be spawned at
/// all; it was moved to 9 and three spawns then succeeded. The spawn path reads
/// the cap FRESH FROM DISK, so a dial move bites without restarting anything —
/// and a dial that echoed what it sent would show a number the fleet is not
/// enforcing. [onSetCap] must therefore resolve with the server's answer, and
/// this widget renders whatever the parent then hands back as [cap].
///
/// ⚠️ THERE IS NO CLIENT-SIDE UPPER CLAMP, AND THAT IS DELIBERATE. The ceiling
/// is `cc session fleet size cap maximum`, read at call time
/// (`arbiter.py:236-239`), so a constant compiled into this app would drift
/// from the value actually enforced and would refuse numbers the server would
/// have accepted. [capMaximum] is the server's own reported ceiling when it
/// supplied one, used only to size the slider; the server still gets the final
/// word and a refusal is surfaced rather than pre-empted.
///
/// The floor IS enforced here, because it is in the body model rather than in
/// config: `cap : int = Field( ge=1 )` (`arbiter.py:241`).
class FleetCapDial extends StatefulWidget {
  final int?                          cap;
  final int?                          capMaximum;
  final Future<void> Function( int )  onSetCap;

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

  /// The slider's ceiling. The server's reported maximum when it gave one,
  /// else a display-only fallback — never a validation rule.
  int get _max {
    final m = widget.capMaximum;
    if ( m != null && m >= 1 ) return m;
    final c = widget.cap ?? 1;
    return c < 20 ? 20 : c;
  }

  /// What the handle sits on: the operator's un-applied drag, else the
  /// server's number, else the floor.
  int get _handle => _pending ?? widget.cap ?? 1;

  @override
  void didUpdateWidget( FleetCapDial old ) {
    super.didUpdateWidget( old );
    // The parent handed us a new server value — drop any stale drag so the
    // handle snaps to what is actually enforced.
    if ( old.cap != widget.cap ) _pending = null;
  }

  Future<void> _apply() async {
    final target = _handle;
    setState( () { _saving = true; _error = null; } );
    try {
      await widget.onSetCap( target );
      // Do NOT write `target` into local state. The parent re-reads and hands
      // back the server's number; anything else would paint a value the fleet
      // may not be enforcing.
      if ( mounted ) setState( () { _pending = null; } );
    } catch ( e ) {
      // On a refusal the handle must snap back to the live value rather than
      // sit on a number the operator never got (FleetStatusStore.ts:203-206).
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
