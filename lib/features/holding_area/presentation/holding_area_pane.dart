import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../../fleet/data/task_row_model.dart';
import '../../fleet/data/task_verbs.dart';
import '../../fleet/presentation/task_row.dart';
import '../data/holding_area_models.dart';
import '../domain/holding_area_bloc.dart';
import 'filer_group_header.dart';

/// The Holding Area pane — held rows, grouped by the PERSONA who filed them, each
/// group folded until the operator opens it.
///
/// 🔴 IT IS NOW AN ACCORDION, AND IT USED NOT TO BE. Rick's ruling of 2026-09-22, on
/// hardware, replaced always-open blocks keyed on `created_by` with folded groups keyed
/// on the persona. See [FilerGroupHeader] for what stays visible while folded and why.
///
/// ⚠️ THE ROUTE OWNS THE VISIBILITY SIGNAL. `onPaneVisible` / `onPaneHidden` are what
/// make foreground-pane-only polling a mechanism rather than an instruction — without
/// them this pane's timer runs whichever destination is showing.
class HoldingAreaPane extends StatefulWidget {
  const HoldingAreaPane( { super.key } );

  @override
  State<HoldingAreaPane> createState() => _HoldingAreaPaneState();
}

class _HoldingAreaPaneState extends State<HoldingAreaPane> {
  /// 🔴 HELD, NOT LOOKED UP IN `dispose()`. `context.read` walks the element tree, and by
  /// the time `dispose` runs that element is being torn down — the lookup can throw, and
  /// a throw there SKIPS the rest of dispose. The timer then survives the pane that owned
  /// it: a poll firing against a screen nobody is looking at, for the life of the
  /// process. Found in Phase 1 and it generalises to every pane that polls.
  late final HoldingAreaBloc _bloc;

  @override
  void initState() {
    super.initState();
    // 🔴 THIS PANE DID NOT POLL AT ALL UNTIL NOW (gap G3), AND THE REASON IS WORTH
    // NAMING: the bloc already mixed in `PanePollingMixin` and already overrode
    // `pollInterval` to read the connection, so every part of polling existed except the
    // call that starts it. Nothing under `lib/features/holding_area` invoked
    // `startPolling` or `onPaneVisible`, so held work updated only on mount, on
    // pull-to-refresh, or on a reconnect — in the pane whose whole job is showing what is
    // waiting on the operator.
    //
    // ⚠️ AND IT LOOKED FINISHED FROM EVERY ANGLE BUT THE RIGHT ONE. A reviewer reading
    // the bloc sees a poll interval, a cancel token and a lifecycle rule; only the pane
    // shows that nobody ever pulled the cord.
    _bloc = context.read<HoldingAreaBloc>()
      ..startPolling()
      ..startConnectivityRefresh();
    // This pane is on screen the moment it is built, because it is route-scoped. The
    // visible edge fires the first fetch, which is why there is no explicit refresh here
    // any more — one would be a second request for the same page.
    _bloc.onPaneVisible();
    // The owner control's options. A courtesy read: it degrades the dropdown, never the
    // pane, and it is NOT on the poll — the fleet roster changes far more slowly than
    // held work, and pulling it every interval would cost the arbiter a request per
    // pane per minute to learn the same six names.
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

  /// One persona's block: the header with its fold control and batch controls, then —
  /// only while unfolded — that persona's rows.
  ///
  /// 🔴 THE ROWS ARE NOT BUILT AT ALL WHILE FOLDED, not built-and-hidden. Folding is
  /// progressive disclosure, which is Rick's word for it, and a disclosure that still
  /// builds every row buys none of what he asked for: *"it's just an enormous amount of
  /// text to scroll through."* Building them and hiding them also leaves them in the
  /// semantics tree, where a TalkBack user would walk rows that are not on screen.
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
            // 🔴 INDENTED UNDER ITS PERSONA, NOT FLUSH LEFT. Rick, walking the sibling
            // pane on the emulator 2026-09-23: rows *"crushed up against the left hand
            // side … they should be indented to reflect containment by each persona."*
            // The left inset is the header's own text start, so a row lines up under the
            // name it belongs to rather than under the chevron. Same finding, same
            // constant, and this pane now has the containment to express.
            padding : const EdgeInsets.fromLTRB( FilerGroupHeader.textInset, 4, 16, 4 ),
            // ⚠️ THE SHARED ROW, WITH NO PANE DISCRIMINATOR. The verbs are DATA — a list,
            // which both panes may pass identically and neither can use to make the row
            // lay itself out differently.
            child : TaskRow(
              model        : row,
              verbs        : _heldRowVerbs( row ),
              ownerOptions : state.reassignTargets,
              // G6: the row wears what the operator did that has not landed. The batch
              // notice says how MANY rows did not move; this says WHICH.
              unsentLabel  : state.unsentLabelFor( row.id ),
              // G6: the row wears what the operator did that has not landed. The batch
              // notice says how MANY rows did not move; this says WHICH.
              onVerb : ( verb ) => bloc.add(
                HoldingAreaRowVerbPressed( id: row.id, verb: verb ),
              ),
              // 🔴 THE OTHER DOOR, AND ITS OWN EVENT — gap G2. Priority and owner are a
              // PATCH, not a transition; routing them through the verb callback would
              // post a field change to the status endpoint.
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

  /// The verbs a held row offers — gap G5, closed.
  ///
  /// 🔴 THIS WAS `[ verbNeeds( 'approve' )! ]`, HARD-CODED, AND THE REASON IT WAS IS
  /// WORTH KEEPING. Four of the seven verbs carry a REQUIRED reason and the row had no
  /// surface to collect one, so offering them meant passing `TaskVerb.wontFix( reason:
  /// '' )` — *"a button whose every press is a guaranteed 422."* This pane named that
  /// trap and declined the verbs rather than fall into it. The shared sheet is that
  /// surface, so the reason is gone and so is the restriction.
  ///
  /// 🔴 THE LEGALITY IS `verbLegality`'s, NOT THIS METHOD'S, and that is the web's rule
  /// carried verbatim: *"Two derivations of one rule agree until the day they do not,
  /// and the day they do not the cell offers a move the server refuses — which reads to
  /// the operator as the board being broken rather than as the move being illegal."*
  /// A hand-written `status == 'not_approved'` here would be a second derivation, and
  /// this pane is single-status by definition, which is exactly the shape that makes one
  /// look harmless.
  ///
  /// ⚠️ AND IT TAKES THE ROW. Every row on this pane is `not_approved` today, so a
  /// no-argument version would give the same answer — until a row arrives mid-poll
  /// having just been approved elsewhere, at which point the pane would offer approve on
  /// a queued row. Asking the row is free; assuming the pane's invariant is not.
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
