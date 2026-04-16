import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/auth/server_context_service.dart';
import '../../auth/domain/auth_bloc.dart';
import '../../auth/domain/auth_event.dart';

/// A drop-in list tile for Settings that switches Dev ↔ Test.
/// Prompts for confirmation, then forces logout (via AuthBloc) before
/// flipping the context so the next login lands on the chosen server.
class ServerContextToggle extends StatefulWidget {
  final ServerContextService service;
  const ServerContextToggle( { super.key, required this.service } );

  @override
  State<ServerContextToggle> createState() => _ServerContextToggleState();
}

class _ServerContextToggleState extends State<ServerContextToggle> {
  late ServerContext _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.service.active;
  }

  Future<void> _onPick( ServerContext ctx ) async {
    if ( ctx == _selected ) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: ( ctx2 ) => AlertDialog(
        title   : const Text( "Switch server?" ),
        content : Text(
          "This will log you out and clear the cached WebSocket session "
          "before switching to ${widget.service.configFor( ctx ).label}.",
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
    if ( confirmed != true ) return;

    // Force logout locally, then flip the stored context.
    context.read<AuthBloc>().add( const AuthLogoutRequested() );
    await widget.service.setActive( ctx );
    context.read<AuthBloc>().add( const AuthServerContextChanged() );
    if ( mounted ) setState( () => _selected = ctx );
  }

  @override
  Widget build( BuildContext context ) {
    final active = widget.service.configFor( _selected );
    final color  = _selected == ServerContext.dev ? Colors.green : Colors.orange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading : Icon( Icons.dns, color: color ),
          title   : const Text( "Active server" ),
          subtitle: Text( "${active.label} · ${active.baseUrl}" ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric( horizontal: 16 ),
          child: SegmentedButton<ServerContext>(
            segments: widget.service.all.map( ( c ) =>
              ButtonSegment<ServerContext>(
                value: c.id == "dev" ? ServerContext.dev : ServerContext.test,
                label: Text( c.label ),
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
