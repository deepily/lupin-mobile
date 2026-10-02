import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/heartbeat_poke_repository.dart';

/// The "Stop poke" switch: turn the fleet's heartbeat stop poke on or off.
///
/// The state is never cached, because any client can flip it.
/// It is re-read when the screen opens and on each foreground.
class HeartbeatPokeSection extends StatefulWidget {
  /// Where the switch is read and written.
  final HeartbeatPokeRepository repository;

  /// Creates the section over [repository].
  const HeartbeatPokeSection( { super.key, required this.repository } );

  @override
  State<HeartbeatPokeSection> createState() => _HeartbeatPokeSectionState();
}

class _HeartbeatPokeSectionState extends State<HeartbeatPokeSection>
    with WidgetsBindingObserver {

  HeartbeatPokeState? _state;
  String?             _error;
  bool                _adminOnly = false;
  bool                _busy      = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver( this );
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver( this );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState( AppLifecycleState state ) {
    if ( state == AppLifecycleState.resumed ) _refresh();
  }

  Future<void> _refresh() => _run( () async {
    _state = await widget.repository.getState();
  } );

  Future<void> _setPokeOn( bool on ) => _run( () async {
    _state = await widget.repository.setMuted( !on );
  } );

  /// Runs [action] with busy, error and 403 handling in one place.
  ///
  /// No path can crash the screen, and a refused write leaves the last state the server reported.
  /// Once a write is refused as admin-only, the switch stays disabled until the screen is reopened.
  /// A read succeeds for every user, so a later good read says nothing about the account's role.
  Future<void> _run( Future<void> Function() action ) async {
    setState( () { _busy = true; _error = null; } );
    try {
      await action();
    } on HeartbeatPokeException catch ( e ) {
      if ( !mounted ) return;
      setState( () {
        _adminOnly = _adminOnly || e.isAdminOnly;
        _error     = e.isAdminOnly ? null : e.message;
      } );
    } catch ( e ) {
      if ( mounted ) setState( () => _error = "$e" );
    } finally {
      if ( mounted ) setState( () => _busy = false );
    }
  }

  String _statusText( BuildContext context ) {
    final s = _state;
    if ( s == null ) return _busy ? "Checking…" : "Unknown";
    if ( !s.muted )  return "On";
    final who  = s.setBy == null ? "" : " by ${s.setBy}";
    final when = s.setAt == null ? "" : " at ${MaterialLocalizations.of( context )
        .formatTimeOfDay( TimeOfDay.fromDateTime( s.setAt! ) )}";
    return "Muted$who$when";
  }

  @override
  Widget build( BuildContext context ) {
    final known = _state != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key       : const Key( TestKeys.heartbeatPokeSwitch ),
          secondary : const Icon( Icons.monitor_heart_outlined ),
          title     : const Text( "Stop poke" ),
          subtitle  : Text( _statusText( context ),
                            key: const Key( TestKeys.heartbeatPokeStatus ) ),
          value     : known && !_state!.muted,
          onChanged : known && !_adminOnly && !_busy ? _setPokeOn : null,
        ),
        if ( _adminOnly )
          const Padding(
            padding : EdgeInsets.symmetric( horizontal: 16 ),
            child   : Text( "Admin only — this account cannot change the stop poke.",
                            key: Key( TestKeys.heartbeatPokeAdminOnly ) ),
          ),
        if ( _error != null )
          Padding(
            padding : const EdgeInsets.symmetric( horizontal: 16 ),
            child   : Text( _error!,
                key   : const Key( TestKeys.heartbeatPokeError ),
                style : TextStyle( color: Theme.of( context ).colorScheme.error ) ),
          ),
        const Divider(),
      ],
    );
  }
}
