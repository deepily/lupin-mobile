import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../../fleet/data/task_row_model.dart';
import '../../fleet/data/task_verbs.dart';
import '../../fleet/presentation/task_row.dart';
import '../data/holding_area_models.dart';
import '../domain/holding_area_bloc.dart';
import 'filer_group_header.dart';

/// The Holding Area pane: held rows grouped by filing persona, folded until opened.
///
/// See [FilerGroupHeader] for what stays visible while a group is folded.
/// Design: src/docs/decisions/README.md
///
/// The route owns the visibility signal. It calls `onPaneVisible` and `onPaneHidden`, so
/// the pane's poll timer runs only while the pane is on screen.
class HoldingAreaPane extends StatefulWidget {
  const HoldingAreaPane( { super.key } );

  @override
  State<HoldingAreaPane> createState() => _HoldingAreaPaneState();
}

class _HoldingAreaPaneState extends State<HoldingAreaPane> {
  // Held here because `context.read` can throw inside `dispose()` while the element is
  // torn down. A throw there would skip the rest of dispose and leave the poll timer running.
  late final HoldingAreaBloc _bloc;

  @override
  void initState() {
    super.initState();
    // Starts polling. The bloc mixes in `PanePollingMixin` and sets `pollInterval`, but
    // nothing else starts the timer, so the pane must call `startPolling` itself.
    _bloc = context.read<HoldingAreaBloc>()
      ..startPolling()
      ..startConnectivityRefresh();
    // The pane is route-scoped, so it is on screen when built. The visible edge fires the
    // first fetch; an explicit refresh here would be a second request for the same page.
    _bloc.onPaneVisible();
    // The owner control's options. A failed read degrades the dropdown, not the pane. It is
    // not on the poll: the roster changes slowly and polling it would cost the arbiter a
    // request per pane per minute.
    _bloc.add( const HoldingAreaRosterRequested() );
  }

  @override
  void dispose() {
    _bloc.onPaneHidden();
    super.dispose();
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
              // The batch notice is pinned above the rows rather than shown in a snackbar. A
              // partial batch describes the rows beneath it, and a snackbar would vanish
              // on a timer while those rows are still on screen.
              if ( state.batchNotice != null ) _notice( context, state.batchNotice! ),
              // An error with rows showing is a banner, so the rows it refers to stay visible.
              if ( state.error != null ) _notice( context, state.error! ),
              if ( state.incomplete ) _incompleteBanner( context, state ),
              for ( final group in state.groups ) ..._block( context, state, group ),
            ],
          ),
        );
      },
    );
  }

  // One persona's block: the header, then that persona's rows only while unfolded.
  // Folded rows are not built, so a screen reader never walks rows that are not on screen.
  List<Widget> _block( BuildContext context, HoldingAreaState state, FilerGroup group ) {
    final bloc     = context.read<HoldingAreaBloc>();
    final expanded = state.isExpanded( group.filer );

    return [
      FilerGroupHeader(
        group           : group,
        expanded        : expanded,
        reason          : state.reasonFor( group.filer ),
        reasonError     : state.reasonErrors[ group.filer ],
        busy            : state.busyFilers.contains( group.filer ),
        onToggle        : () => bloc.add( HoldingAreaGroupToggled( group.filer ) ),
        onReasonChanged : ( text ) => bloc.add(
          HoldingAreaReasonChanged( filer: group.filer, reason: text ),
        ),
        onApproveAll : () => bloc.add( HoldingAreaApproveAllPressed( group.filer ) ),
        onWontFixAll : () => bloc.add( HoldingAreaWontFixAllPressed(
          filer  : group.filer,
          reason : state.reasonFor( group.filer ),
        ) ),
      ),
      if ( expanded )
        for ( final row in group.rows )
          Padding(
            // Indented to the header's text start, so a row lines up under the persona name
            // it belongs to rather than under the chevron.
            padding : const EdgeInsets.fromLTRB( FilerGroupHeader.textInset, 4, 16, 4 ),
            // The shared row, with no pane flag. The verbs are a plain list that both panes
            // pass the same way.
            child : TaskRow(
              model        : row,
              verbs        : _heldRowVerbs( row ),
              ownerOptions : state.reassignTargets,
              // The row shows what the operator did that has not landed. The batch notice
              // gives the count of rows that did not move; this says which.
              unsentLabel  : state.unsentLabelFor( row.id ),
              onVerb : ( verb ) => bloc.add(
                HoldingAreaRowVerbPressed( id: row.id, verb: verb ),
              ),
              // Priority and owner are a field change, not a transition, so they use their
              // own event instead of the verb callback.
              onFieldChanged : ( { String? priority, String? ownerPersona } ) => bloc.add(
                HoldingAreaFieldChanged(
                  id           : row.id,
                  priority     : priority,
                  ownerPersona : ownerPersona,
                ),
              ),
            ),
          ),
      const Divider( height: 24 ),
    ];
  }

  // The verbs a held row offers, taken from `verbLegality` for the row's own status.
  // Legality is that function's rule, so a hand-written status check here would be a
  // second copy. It takes the row because a row can change status between polls.
  List<VerbNeeds> _heldRowVerbs( TaskRowModel row ) {
    return verbLegality( row.status )
        .where( ( entry ) => entry.enabled )
        .map( ( entry ) => entry.needs )
        .toList( growable: false );
  }

  Widget _incompleteBanner( BuildContext context, HoldingAreaState state ) {
    return Container(
      key       : const Key( TestKeys.holdingIncompleteBanner ),
      padding   : const EdgeInsets.all( 12 ),
      color     : Theme.of( context ).colorScheme.tertiaryContainer,
      // A visible banner, because rows past the end of the page are held work the operator
      // cannot see.
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
      // A live region, so a screen reader announces the notice while focus is still on the
      // button that was pressed.
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
