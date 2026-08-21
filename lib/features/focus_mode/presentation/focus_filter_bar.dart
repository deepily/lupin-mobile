import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../domain/focus_chat_bloc.dart';
import '../domain/focus_chat_event.dart';
import '../domain/focus_chat_state.dart';

/// Slim toolbar above the rail+pane Row hosting the Live / 24h history
/// `SegmentedButton` with per-band counts (plan 2026.06.25 §4.1 — the rail
/// is 56px, too narrow for a horizontal control). Filter = VISIBILITY: the
/// bloc never prunes senders, this only moves the lens.
class FocusFilterBar extends StatelessWidget {
  const FocusFilterBar( { super.key } );

  @override
  Widget build( BuildContext context ) {
    return BlocBuilder<FocusChatBloc, FocusChatState>(
      buildWhen: ( a, b ) =>
          a.filter != b.filter || a.liveCount != b.liveCount || a.historyCount != b.historyCount,
      builder: ( context, state ) {
        return Padding(
          key     : const Key( TestKeys.focusFilterBar ),
          padding : const EdgeInsets.symmetric( horizontal: 12, vertical: 6 ),
          child   : Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<FocusFilter>(
              showSelectedIcon : false,
              style            : const ButtonStyle( visualDensity: VisualDensity.compact ),
              segments         : [
                ButtonSegment(
                  value : FocusFilter.live,
                  label : Text( 'Live (${state.liveCount})', key: const Key( TestKeys.focusFilterLive ) ),
                  icon  : const Icon( Icons.circle, size: 10, color: Color( 0xFF2E7D32 ) ),
                ),
                ButtonSegment(
                  value : FocusFilter.history,
                  label : Text( '24h (${state.historyCount})', key: const Key( TestKeys.focusFilterHistory ) ),
                  icon  : const Icon( Icons.history, size: 14 ),
                ),
              ],
              selected          : { state.filter },
              onSelectionChanged: ( sel ) =>
                  context.read<FocusChatBloc>().add( FocusFilterChanged( sel.first ) ),
            ),
          ),
        );
      },
    );
  }
}
