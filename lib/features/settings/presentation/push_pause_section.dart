import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/push_pause_repository.dart';

/// "Pause push from server" (row 67ee93b0, Rick 2026-09-29): stop the server
/// sending wake-up pushes for a chosen length of time.
///
/// 🔴 The state is never cached. The pause lives in server memory and a restart
/// clears it, so it is re-read when the screen opens and every time the app
/// returns to the foreground.
class PushPauseSection extends StatefulWidget {
  final PushPauseRepository repository;
  const PushPauseSection( { super.key, required this.repository } );

  /// The durations offered; null minutes means until resumed.
  static const List<( String, int? )> durations = [
    ( "30 min",           30 ),
    ( "1 h",              60 ),
    ( "2 h",             120 ),
    ( "8 h",             480 ),
    ( "24 h",           1440 ),
    ( "Until I resume", null ),
  ];

  @override
  State<PushPauseSection> createState() => _PushPauseSectionState();
}

class _PushPauseSectionState extends State<PushPauseSection>
    with WidgetsBindingObserver {

  PushPauseState? _state;
  String?         _error;
  bool            _adminOnly = false;
  bool            _busy      = true;

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

  Future<void> _pause( int? minutes ) => _run( () async {
    await widget.repository.pause( minutes: minutes );
    _state = await widget.repository.getState();
  } );

  Future<void> _resume() => _run( () async {
    await widget.repository.resume();
    _state = await widget.repository.getState();
  } );

  /// One place for busy / error / 403 handling, so no path can crash the screen.
  Future<void> _run( Future<void> Function() action ) async {
    setState( () { _busy = true; _error = null; } );
    try {
      await action();
      if ( mounted ) setState( () => _adminOnly = false );
    } on PushPauseException catch ( e ) {
      if ( !mounted ) return;
      setState( () {
        _adminOnly = e.isAdminOnly;
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
    if ( s == null )   return _busy ? "Checking…" : "Unknown";
    if ( !s.paused )   return "On";
    if ( s.resumesAt == null ) return "Paused until resumed";
    final t = MaterialLocalizations.of( context )
        .formatTimeOfDay( TimeOfDay.fromDateTime( s.resumesAt! ) );
    return "Paused until $t";
  }

  @override
  Widget build( BuildContext context ) {
    final enabled = !_adminOnly && !_busy;
    final paused  = _state?.paused ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading  : const Icon( Icons.pause_circle_outline ),
          title    : const Text( "Pause push from server" ),
          subtitle : Text( _statusText( context ), key: const Key( TestKeys.pushPauseStatus ) ),
        ),
        if ( _adminOnly )
          const Padding(
            padding : EdgeInsets.symmetric( horizontal: 16 ),
            child   : Text( "Admin only — this account cannot pause push.",
                            key: Key( TestKeys.pushPauseAdminOnly ) ),
          ),
        if ( _error != null )
          Padding(
            padding : const EdgeInsets.symmetric( horizontal: 16 ),
            child   : Text( _error!,
                key   : const Key( TestKeys.pushPauseError ),
                style : TextStyle( color: Theme.of( context ).colorScheme.error ) ),
          ),
        Padding(
          padding : const EdgeInsets.symmetric( horizontal: 16 ),
          child   : Wrap(
            spacing: 8,
            children: [
              for ( final d in PushPauseSection.durations )
                ActionChip(
                  key       : Key( TestKeys.pushPauseDuration( d.$2 ) ),
                  label     : Text( d.$1 ),
                  onPressed : enabled ? () => _pause( d.$2 ) : null,
                ),
            ],
          ),
        ),
        Padding(
          padding : const EdgeInsets.fromLTRB( 16, 8, 16, 0 ),
          child   : Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key       : const Key( TestKeys.pushPauseResume ),
              onPressed : enabled && paused ? _resume : null,
              child     : const Text( "Resume" ),
            ),
          ),
        ),
        const Divider(),
      ],
    );
  }
}
