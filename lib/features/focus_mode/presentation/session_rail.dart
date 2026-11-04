import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../../notifications/data/voice_persona.dart';
import '../../notifications/presentation/persona_badge.dart';
import '../domain/focus_chat_bloc.dart';
import '../domain/focus_chat_event.dart';
import '../domain/focus_chat_state.dart';

/// Always-visible vertical rail of persona badges, one per visible sender.
///
/// Persona senders come first, oldest session first, then a thin divider, then system
/// senders in arrival order. The Live or History lens and the Personas or All scope decide
/// who is listed. Non-focused senders show an unread dot or count. The focused sender has a
/// selection ring, and a status dot shows recency: green for live, yellow for history.
/// A tap sends `FocusSenderSelected`, the only thing on this surface that moves
/// `focusedSender`, so focus changes only by the user's hand.
/// Design: src/docs/decisions/README.md (R-FM-rail-order)
class SessionRail extends StatelessWidget {
  /// Rail width in logical pixels.
  static const double width = 56;

  /// Creates the rail.
  const SessionRail( { super.key } );

  /// Avatar initial for a sender with no persona glyph.
  ///
  /// It uses the persona name, never the repo id, which would give a rail of identical
  /// letters. The order is persona display name, persona name, then the sender id's local
  /// part before `@` or `#`; `deep.research@lupin` gives "D".
  static String railInitial( String sid, VoicePersona? persona ) {
    final name = persona?.displayName ?? persona?.name;
    if ( name != null && name.trim().isNotEmpty ) return name.trim().substring( 0, 1 ).toUpperCase();
    final local = sid.split( RegExp( r'[@#]' ) ).first.trim();
    if ( local.isEmpty ) return '?';
    return local.substring( 0, 1 ).toUpperCase();
  }

  @override
  Widget build( BuildContext context ) {
    return SizedBox(
      key   : const Key( TestKeys.focusRail ),
      width : width,
      child : BlocBuilder<FocusChatBloc, FocusChatState>(
        builder: ( context, state ) {
          final personas = state.visiblePersonas;
          final system   = state.visibleSystem;
          final visible  = [ ...personas, ...system ];
          if ( visible.isEmpty && state.filter == FocusFilter.live && state.senderOrder.isNotEmpty ) {
            return _EmptyLiveHint( historyCount: state.historyCount );
          }
          // A divider row sits between the two groups only when BOTH have
          // members (no orphan line under a personas-only rail).
          final hasDivider = personas.isNotEmpty && system.isNotEmpty;
          final rows       = visible.length + ( hasDivider ? 1 : 0 );
          return ListView.builder(
            padding     : const EdgeInsets.symmetric( vertical: 8 ),
            itemCount   : rows,
            itemBuilder : ( context, i ) {
              if ( hasDivider && i == personas.length ) {
                return Padding(
                  key     : const Key( TestKeys.focusRailGroupDivider ),
                  padding : const EdgeInsets.symmetric( horizontal: 12, vertical: 6 ),
                  child   : Divider( height: 1, thickness: 1, color: Theme.of( context ).colorScheme.outlineVariant ),
                );
              }
              final sid     = visible[ hasDivider && i > personas.length ? i - 1 : i ];
              final persona = state.personasBySender[ sid ];
              final unread  = state.unreadBySender[ sid ] ?? 0;
              final focused = state.focusedSender == sid;
              final exited  = state.exitedSenders.contains( sid );
              return _RailEntry(
                senderId : sid,
                unread   : focused ? 0 : unread,
                focused  : focused,
                band     : exited ? FocusBand.history : state.bandFor( sid ),
                child    : _badgeFor( context, sid, persona ),
              );
            },
          );
        },
      ),
    );
  }

  /// A `PersonaBadge` when the registry has a glyph, else a name-initial avatar.
  ///
  /// `PersonaBadge` renders nothing for a null persona, but every sender needs a tappable
  /// entry.
  Widget _badgeFor( BuildContext context, String sid, VoicePersona? persona ) {
    if ( persona != null && ( persona.icon ?? '' ).isNotEmpty ) {
      return PersonaBadge( persona: persona, senderId: sid, diameter: 28 );
    }
    return CircleAvatar(
      radius          : 14,
      backgroundColor : Theme.of( context ).colorScheme.surfaceContainerHighest,
      child           : Text(
        railInitial( sid, persona ),
        key   : Key( '${TestKeys.focusRailInitialPrefix}$sid' ),
        style : const TextStyle( fontSize: 12 ),
      ),
    );
  }
}

/// Empty state for the Live lens when senders exist only in History.
///
/// It says so instead of rendering a blank rail.
class _EmptyLiveHint extends StatelessWidget {
  final int historyCount;
  const _EmptyLiveHint( { required this.historyCount } );

  @override
  Widget build( BuildContext context ) {
    return Padding(
      key     : const Key( TestKeys.focusRailEmptyHint ),
      padding : const EdgeInsets.all( 4 ),
      child   : Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon( Icons.nightlight_round, size: 18, color: Theme.of( context ).colorScheme.outline ),
          const SizedBox( height: 4 ),
          Text( 'No live\nsessions', textAlign: TextAlign.center,
                style: Theme.of( context ).textTheme.labelSmall ),
          if ( historyCount > 0 )
            TextButton(
              key       : const Key( TestKeys.focusRailEmptyHintButton ),
              style     : TextButton.styleFrom( padding: EdgeInsets.zero, minimumSize: const Size( 48, 28 ) ),
              onPressed : () => context.read<FocusChatBloc>().add( const FocusFilterChanged( FocusFilter.history ) ),
              child     : Text( '24h ($historyCount)', style: const TextStyle( fontSize: 10 ) ),
            ),
        ],
      ),
    );
  }
}

class _RailEntry extends StatelessWidget {
  final String    senderId;
  final Widget    child;
  final int       unread;
  final bool      focused;
  final FocusBand band;

  const _RailEntry( {
    required this.senderId,
    required this.child,
    required this.unread,
    required this.focused,
    required this.band,
  } );

  static const Color liveDot    = Color( 0xFF2E7D32 );   // 🟢 web parity
  static const Color historyDot = Color( 0xFFF9A825 );   // 🟡

  @override
  Widget build( BuildContext context ) {
    final ring = Theme.of( context ).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric( vertical: 4 ),
      child: Center(
        child: InkWell(
          key          : Key( '${TestKeys.focusRailBadgePrefix}$senderId' ),
          customBorder : const CircleBorder(),
          onTap        : () => context
              .read<FocusChatBloc>()
              .add( FocusSenderSelected( senderId ) ),
          child: Container(
            padding    : const EdgeInsets.all( 2 ),
            decoration : focused
                ? BoxDecoration(
                    shape  : BoxShape.circle,
                    border : Border.all( color: ring, width: 2 ),
                  )
                : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                child,
                if ( band != FocusBand.stale )
                  Positioned(
                    right  : -2,
                    bottom : -2,
                    child  : Container(
                      key        : Key( '${TestKeys.focusRailStatusDotPrefix}$senderId' ),
                      width      : 9,
                      height     : 9,
                      decoration : BoxDecoration(
                        color  : band == FocusBand.live ? liveDot : historyDot,
                        shape  : BoxShape.circle,
                        border : Border.all( color: Theme.of( context ).colorScheme.surface, width: 1.5 ),
                      ),
                    ),
                  ),
                if ( unread > 0 )
                  Positioned(
                    right : -4,
                    top   : -4,
                    child : Container(
                      padding    : const EdgeInsets.all( 3 ),
                      decoration : BoxDecoration(
                        color : Theme.of( context ).colorScheme.error,
                        shape : BoxShape.circle,
                      ),
                      constraints: const BoxConstraints( minWidth: 16, minHeight: 16 ),
                      child: Text(
                        '$unread',
                        textAlign : TextAlign.center,
                        style     : const TextStyle( fontSize: 9, color: Colors.white ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
