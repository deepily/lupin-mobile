import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../../notifications/presentation/persona_badge.dart';
import '../domain/focus_chat_bloc.dart';
import '../domain/focus_chat_event.dart';
import '../domain/focus_chat_state.dart';

/// Always-visible vertical badge rail (Q11 Pattern A): PersonaBadges in
/// `senderOrder` (establishment order, Q7 — never re-sorts), unread
/// dot/count overlays on non-focused senders, selection highlight ring.
/// Tap → `FocusSenderSelected` — the ONLY thing in the surface that moves
/// `focusedSender` (Q4 manual-focus invariant).
class SessionRail extends StatelessWidget {
  static const double width = 56;

  const SessionRail( { super.key } );

  @override
  Widget build( BuildContext context ) {
    return SizedBox(
      key   : const Key( TestKeys.focusRail ),
      width : width,
      child : BlocBuilder<FocusChatBloc, FocusChatState>(
        builder: ( context, state ) {
          return ListView.builder(
            padding     : const EdgeInsets.symmetric( vertical: 8 ),
            itemCount   : state.senderOrder.length,
            itemBuilder : ( context, i ) {
              final sid     = state.senderOrder[ i ];
              final persona = state.personasBySender[ sid ];
              final unread  = state.unreadBySender[ sid ] ?? 0;
              final focused = state.focusedSender == sid;
              return _RailEntry(
                senderId : sid,
                unread   : focused ? 0 : unread,
                focused  : focused,
                child    : _badgeFor( context, sid, persona ),
              );
            },
          );
        },
      ),
    );
  }

  /// PersonaBadge when the registry has one; sender-initial fallback
  /// otherwise (PersonaBadge renders nothing for a null persona, but the
  /// rail must always show a tappable entry per sender).
  Widget _badgeFor( BuildContext context, String sid, dynamic persona ) {
    if ( persona != null ) {
      return PersonaBadge( persona: persona, senderId: sid, diameter: 28 );
    }
    final initial = sid.isEmpty ? '?' : sid.substring( 0, 1 ).toUpperCase();
    return CircleAvatar(
      radius          : 14,
      backgroundColor : Theme.of( context ).colorScheme.surfaceContainerHighest,
      child           : Text( initial, style: const TextStyle( fontSize: 12 ) ),
    );
  }
}

class _RailEntry extends StatelessWidget {
  final String senderId;
  final Widget child;
  final int    unread;
  final bool   focused;

  const _RailEntry( {
    required this.senderId,
    required this.child,
    required this.unread,
    required this.focused,
  } );

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
