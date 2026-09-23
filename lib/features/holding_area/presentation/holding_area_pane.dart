import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../../fleet/data/task_verbs.dart';
import '../../fleet/presentation/task_row.dart';
import '../data/holding_area_models.dart';
import '../domain/holding_area_bloc.dart';
import 'filer_group_header.dart';

/// The Holding Area pane — held rows, grouped by filer, each group its own block.
///
/// 🔴 NOT AN ACCORDION, AND NOT A `CustomScrollView` OF COLLAPSIBLE SECTIONS. Each
/// filer's block renders open, always. See [FilerGroupHeader].
class HoldingAreaPane extends StatefulWidget {
  const HoldingAreaPane( { super.key } );

  @override
  State<HoldingAreaPane> createState() => _HoldingAreaPaneState();
}

class _HoldingAreaPaneState extends State<HoldingAreaPane> {
  @override
  void initState() {
    super.initState();
    final bloc = context.read<HoldingAreaBloc>();
    bloc.add( const HoldingAreaRefreshRequested() );
    bloc.startConnectivityRefresh();
  }

  @override
  Widget build( BuildContext context ) {
    return BlocBuilder<HoldingAreaBloc, HoldingAreaState>(
      builder : ( context, state ) {
        if ( state.error != null && state.groups.isEmpty ) return _error( context, state );
        if ( state.groups.isEmpty && !state.loading ) return _empty( context );

        return RefreshIndicator(
          onRefresh : () async =>
              context.read<HoldingAreaBloc>().add( const HoldingAreaRefreshRequested() ),
          child : ListView(
            key      : const Key( TestKeys.holdingView ),
            children : [
              // 🔴 THE BATCH NOTICE IS PINNED ABOVE THE ROWS, NOT SHOWN IN A SNACKBAR.
              // A partial batch — "1 of 3 rows did not move" — is a fact about the rows
              // directly beneath it, and a snackbar takes it away on a timer while the
              // rows it describes are still on screen. It is also the one message this
              // pane produces that the operator must act on.
              if ( state.batchNotice != null ) _notice( context, state.batchNotice! ),
              // An error WITH rows still showing is a banner, not a takeover: hiding the
              // rows it refers to would be the wrong half of the screen to replace.
              if ( state.error != null ) _notice( context, state.error! ),
              if ( state.incomplete ) _incompleteBanner( context, state ),
              for ( final group in state.groups ) ..._block( context, state, group ),
            ],
          ),
        );
      },
    );
  }

  /// One filer's block: the header with its batch controls, then that filer's rows.
  List<Widget> _block( BuildContext context, HoldingAreaState state, FilerGroup group ) {
    final bloc = context.read<HoldingAreaBloc>();

    return [
      FilerGroupHeader(
        group           : group,
        reason          : state.reasonFor( group.filer ),
        reasonError     : state.reasonErrors[ group.filer ],
        busy            : state.busyFilers.contains( group.filer ),
        onReasonChanged : ( text ) => bloc.add(
          HoldingAreaReasonChanged( filer: group.filer, reason: text ),
        ),
        onApproveAll : () => bloc.add( HoldingAreaApproveAllPressed( group.filer ) ),
        onWontFixAll : () => bloc.add( HoldingAreaWontFixAllPressed(
          filer  : group.filer,
          reason : state.reasonFor( group.filer ),
        ) ),
      ),
      for ( final row in group.rows )
        Padding(
          padding : const EdgeInsets.symmetric( horizontal: 16, vertical: 4 ),
          // ⚠️ THE SHARED ROW, WITH NO PANE DISCRIMINATOR. The verbs are DATA — a list,
          // which both panes may pass identically and neither can use to make the row
          // lay itself out differently.
          child : TaskRow(
            model : row,
            verbs : _heldRowVerbs(),
            onVerb : ( verb ) => bloc.add(
              HoldingAreaRowVerbPressed( id: row.id, verb: verb ),
            ),
          ),
        ),
      const Divider( height: 24 ),
    ];
  }

  /// The verbs a HELD row offers.
  ///
  /// ⚠️ STILL APPROVE ONLY, AND THAT IS NOW A SCOPE LINE RATHER THAN A CAPABILITY GAP.
  /// The reason this list was one verb long was that `wont_fix` carries a REQUIRED reason
  /// and the row had no surface to collect one — *"`TaskVerb.wontFix( reason: '' )` is a
  /// button whose every press is a guaranteed 422."* That surface now exists (the shared
  /// sheet), so the blocker is gone; widening this pane's per-row verbs is G5, its own
  /// row, and belongs to whoever holds it. Changing it here would be that row's work
  /// landing in this one's diff.
  List<VerbNeeds> _heldRowVerbs() => <VerbNeeds>[ verbNeeds( 'approve' )! ];

  Widget _incompleteBanner( BuildContext context, HoldingAreaState state ) {
    return Container(
      key       : const Key( TestKeys.holdingIncompleteBanner ),
      padding   : const EdgeInsets.all( 12 ),
      color     : Theme.of( context ).colorScheme.tertiaryContainer,
      // 🔴 A VISIBLE BANNER, BECAUSE PAGINATION WAS RULED OUT AND NOTICING WAS NOT.
      // Held rows off the end of the page are held work the operator cannot see, in the
      // pane whose job is showing exactly that.
      child : Text(
        'Showing part of the held set — ${state.total} rows held in total.',
      ),
    );
  }

  Widget _notice( BuildContext context, String text ) {
    return Container(
      key     : const Key( TestKeys.holdingNotice ),
      padding : const EdgeInsets.all( 12 ),
      color   : Theme.of( context ).colorScheme.errorContainer,
      // A live region: the notice appears in response to a press, and a TalkBack user
      // whose focus is still on the button they pressed is told nothing otherwise.
      child   : Semantics( liveRegion: true, child: Text( text ) ),
    );
  }

  Widget _error( BuildContext context, HoldingAreaState state ) {
    return Center(
      key   : const Key( TestKeys.holdingErrorView ),
      child : Padding(
        padding : const EdgeInsets.all( 24 ),
        child   : Column(
          mainAxisSize : MainAxisSize.min,
          children : [
            Text( state.error!, textAlign: TextAlign.center ),
            const SizedBox( height: 16 ),
            FilledButton(
              onPressed : () => context
                  .read<HoldingAreaBloc>()
                  .add( const HoldingAreaRefreshRequested() ),
              child : const Text( 'Retry' ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty( BuildContext context ) {
    return const Center(
      key   : Key( TestKeys.holdingEmptyState ),
      child : Padding(
        padding : EdgeInsets.all( 24 ),
        child   : Text( 'Nothing is held.', textAlign: TextAlign.center ),
      ),
    );
  }
}
