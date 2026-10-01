import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../domain/focus_chat_bloc.dart';
import '../domain/focus_chat_event.dart';
import '../domain/focus_chat_state.dart';

/// Slim toolbar above the rail and pane with the Live and 24h lens controls.
///
/// A segmented button shows Live or 24h history with per-band counts. It lives here because
/// the 56px rail is too narrow for a horizontal control. Beside it sits the Personas or All
/// sender-scope control, which affects the rail only and defaults to Personas.
/// The filter changes visibility only: the bloc never prunes senders.
/// Design: src/docs/decisions/README.md (R-FM-filter-scope)
class FocusFilterBar extends StatelessWidget {
  /// Creates the toolbar.
  const FocusFilterBar( { super.key } );

  @override
  Widget build( BuildContext context ) {
    return BlocBuilder<FocusChatBloc, FocusChatState>(
      buildWhen: ( a, b ) =>
          a.filter != b.filter || a.liveCount != b.liveCount || a.historyCount != b.historyCount ||
          a.senderScope != b.senderScope || a.personaCount != b.personaCount || a.allCount != b.allCount,
      builder: ( context, state ) {
        return Padding(
          key     : const Key( TestKeys.focusFilterBar ),
          padding : const EdgeInsets.symmetric( horizontal: 12, vertical: 6 ),
          child   : Wrap(
            spacing     : 8,
            runSpacing  : 4,
            alignment   : WrapAlignment.start,
            children    : [
              SegmentedButton<FocusFilter>(
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
              SegmentedButton<FocusSenderScope>(
                showSelectedIcon : false,
                style            : const ButtonStyle( visualDensity: VisualDensity.compact ),
                segments         : [
                  ButtonSegment(
                    value : FocusSenderScope.personas,
                    label : Text( 'Personas (${state.personaCount})', key: const Key( TestKeys.focusScopePersonas ) ),
                    icon  : const Icon( Icons.face, size: 14 ),
                  ),
                  ButtonSegment(
                    value : FocusSenderScope.all,
                    label : Text( 'All (${state.allCount})', key: const Key( TestKeys.focusScopeAll ) ),
                    icon  : const Icon( Icons.apps, size: 14 ),
                  ),
                ],
                selected          : { state.senderScope },
                onSelectionChanged: ( sel ) =>
                    context.read<FocusChatBloc>().add( FocusSenderScopeChanged( sel.first ) ),
              ),
            ],
          ),
        );
      },
    );
  }
}
