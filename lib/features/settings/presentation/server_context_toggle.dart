import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/auth/server_context_service.dart';
import '../../auth/domain/auth_bloc.dart';
import '../../auth/domain/auth_event.dart';

/// Green for any dev server ("dev", "lan-dev"), orange for everything else.
Color serverContextColor( String id ) =>
  id.endsWith( "dev" ) ? Colors.green : Colors.orange;

/// A drop-in widget that switches between the server contexts in `server-contexts.json`.
///
/// It prompts for confirmation, then asks AuthBloc to log out of the current server and
/// switch. The widget redraws when the service reports the switch.
///
/// It renders in every build mode, release included, because it is the only way a phone
/// can reach another server before it has signed in.
/// The login screen is its only mount, and Settings sits behind the auth gate, which
/// needs a reachable server. The shipped default context is the emulator's alias for the
/// host, which is meaningless on a handset. A release APK without this picker would boot
/// pointing at an address it can never reach.
/// Release builds are the ones people install.
/// Gating the picker on a build mode (release, profile, debug or the product flag)
/// would leave the phone with no way back.
/// To hide it from strangers, use something reachable without a server instead, such as
/// a long-press, a build-time define or a first-run setup step.
class ServerContextToggle extends StatefulWidget {
  /// The service that lists the contexts and reports which one is active.
  final ServerContextService service;

  /// Called after a confirmed switch, so a parent showing the active context can rebuild.
  ///
  /// The login screen's badge is one such parent.
  final ValueChanged<String>? onChanged;

  /// Creates the picker over [service].
  const ServerContextToggle( {
    super.key,
    required this.service,
    this.onChanged,
  } );

  @override
  State<ServerContextToggle> createState() => _ServerContextToggleState();
}

class _ServerContextToggleState extends State<ServerContextToggle> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.service.active;
    widget.service.addListener( _onServiceSwitched );
  }

  /// Moves the listener when a parent hands this widget a different service.
  ///
  /// A rebuild after a service reset keeps the same State object. Without this, the
  /// subscription would stay on the old service, so the new one's switches would never
  /// redraw the segments.
  @override
  void didUpdateWidget( ServerContextToggle oldWidget ) {
    super.didUpdateWidget( oldWidget );
    if ( !identical( oldWidget.service, widget.service ) ) {
      oldWidget.service.removeListener( _onServiceSwitched );
      widget.service.addListener( _onServiceSwitched );
      _selected = widget.service.active;
    }
  }

  @override
  void dispose() {
    widget.service.removeListener( _onServiceSwitched );
    super.dispose();
  }

  void _onServiceSwitched( ServerContextConfig config ) {
    if ( !mounted ) return;
    setState( () => _selected = config.id );
    widget.onChanged?.call( config.id );
  }

  Future<void> _onPick( String id ) async {
    if ( id == _selected ) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: ( ctx2 ) => AlertDialog(
        title   : const Text( "Switch server?" ),
        content : Text(
          "This will log you out and clear the cached WebSocket session "
          "before switching to ${widget.service.configFor( id ).label}.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of( ctx2 ).pop( false ),
            child: const Text( "Cancel" ),
          ),
          FilledButton(
            onPressed: () => Navigator.of( ctx2 ).pop( true ),
            child: const Text( "Switch" ),
          ),
        ],
      ),
    );
    if ( confirmed != true || !mounted ) return;

    // AuthBloc clears the current server's session, then switches; the
    // service listener above redraws this widget once the switch lands.
    context.read<AuthBloc>().add( AuthServerContextSwitchRequested( id ) );
  }

  @override
  Widget build( BuildContext context ) {
    final active = widget.service.configFor( _selected );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The login form's spacing lives here, not at the call site, so the
        // widget carries its own lead-in wherever it is mounted.
        const SizedBox( height: 32 ),
        ListTile(
          leading : Icon( Icons.dns, color: serverContextColor( _selected ) ),
          title   : const Text( "Active server" ),
          subtitle: Text( "${active.label} · ${active.baseUrl}" ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric( horizontal: 16 ),
          child: SegmentedButton<String>(
            key              : const Key( TestKeys.serverContextToggle ),
            showSelectedIcon : false,
            segments: widget.service.all.map( ( c ) =>
              ButtonSegment<String>(
                value: c.id,
                label: Text(
                  c.label,
                  key       : Key( "${TestKeys.serverContextSegmentPrefix}${c.id}" ),
                  textAlign : TextAlign.center,
                ),
              ),
            ).toList(),
            selected: { _selected },
            onSelectionChanged: ( s ) => _onPick( s.first ),
          ),
        ),
      ],
    );
  }
}
