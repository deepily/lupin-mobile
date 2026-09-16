import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/auth/server_context_service.dart';
import '../../auth/domain/auth_bloc.dart';
import '../../auth/domain/auth_event.dart';

/// Green for any dev server ("dev", "lan-dev"), orange for everything else.
Color serverContextColor( String id ) =>
  id.endsWith( "dev" ) ? Colors.green : Colors.orange;

/// A drop-in widget that switches between every server context listed in
/// `server-contexts.json` (DEV, TEST, LAN DEV, LAN TEST, ...).
/// Prompts for confirmation, then asks AuthBloc to log out of the current
/// server and switch; the widget redraws when the service reports the switch.
///
/// Renders in EVERY build mode, release included, and deliberately so.
///
/// The login screen is this widget's only mount, and it is the only surface a
/// phone sees before it has signed in: Settings lives behind AuthGate
/// (auth_gate.dart:50-51 -> app.dart:272), which needs a reachable server to
/// get past. `assets/config/server-contexts.json` ships "dev" as the default,
/// which is 10.0.2.2 — the emulator's alias for the host, meaningless on a
/// handset. So a release APK with no picker here boots pointing at an address
/// it can never reach, with no screen anywhere that lets it point elsewhere.
///
/// That is not hypothetical: `.github/workflows/release.yml` attaches a
/// release APK and AAB to every `v*.*.*` tag, and `.github/workflows/
/// flutter-ci.yml:144` uploads a release APK on every run. Those are the
/// builds people actually install on a phone.
///
/// A host picker on a sign-in screen does look like a development affordance,
/// and a build-mode gate here was tried (ca07b57) and reverted for the reason
/// above. If it should ever be hidden from strangers, hide it behind
/// something the app can still reach without a server — a long-press, a
/// build-time --dart-define, a first-run setup step — never behind a build
/// mode that leaves the phone with no way back.
class ServerContextToggle extends StatefulWidget {
  final ServerContextService service;

  /// Called after a confirmed switch, so a parent showing the active
  /// context elsewhere (e.g. the login screen's badge) can rebuild.
  final ValueChanged<String>? onChanged;

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

  /// A parent that hands this widget a DIFFERENT service (a rebuild after
  /// ServiceLocator.reset, a screen that swaps the service it was given)
  /// keeps the same State object. Without this, the subscription would still
  /// be on the old service: the new one's switches would never redraw the
  /// segments, and the old one would keep calling a listener nobody wants.
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

    // AuthBloc clears the CURRENT server's session, then switches; the
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
