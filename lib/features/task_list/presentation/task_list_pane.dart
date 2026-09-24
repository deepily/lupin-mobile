import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../../fleet/data/task_row_model.dart';
import '../../fleet/data/task_verbs.dart';
import '../../fleet/presentation/task_row.dart';
import '../data/task_list_model.dart';
import '../domain/task_list_bloc.dart';
import 'task_group_header.dart';
import 'task_list_header.dart';

/// The Task List pane.
///
/// ⚠️ THE ROUTE OWNS THE VISIBILITY SIGNAL. `onPaneVisible` / `onPaneHidden` are what
/// make foreground-pane-only polling a mechanism rather than an instruction — without
/// them this pane's timer runs whichever destination is showing.
class TaskListPane extends StatefulWidget {
  const TaskListPane( { super.key } );

  @override
  State<TaskListPane> createState() => _TaskListPaneState();
}

class _TaskListPaneState extends State<TaskListPane> {
  /// 🔴 HELD, NOT LOOKED UP IN `dispose()`. `context.read` walks the element tree, and by
  /// the time `dispose` runs that element is being torn down — the lookup can throw, and
  /// a throw there SKIPS the rest of dispose. The timer then survives the pane that owned
  /// it: a poll firing against a screen nobody is looking at, for the life of the
  /// process.
  ///
  /// ⚠️ THAT BUG IS ALMOST UNATTRIBUTABLE IN THE FIELD. It costs battery and data with no
  /// visible symptom, on a pane the user has already left, and every pane in this plan
  /// can grow its own copy. Found by Chloé in Phase 1 and it generalised straight to
  /// here.
  late final TaskListBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<TaskListBloc>()
      ..startPolling()
      ..startConnectivityRefresh();
    // This pane is on screen the moment it is built, because it is route-scoped.
    _bloc.onPaneVisible();
    // 🔴 ONCE ON MOUNT, NOT ON EVERY POLL. The roster changes when a seat is spawned or
    // reaped — rare — while the board polls every 60 s on Wi-Fi. Riding the poll would
    // double this pane's request count for a list that almost never moves, on the
    // connection §6.5 costed in megabytes.
    _bloc.add( const TaskListRosterRequested() );
  }

  @override
  void dispose() {
    _bloc.onPaneHidden();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    return BlocBuilder<TaskListBloc, TaskListState>(
      builder : ( context, state ) {
        final model = state.model;

        if ( model == null && state.loading ) {
          return const Center( child: CircularProgressIndicator() );
        }
        if ( state.error != null && model == null ) {
          return Center( child: Text( state.error! ) );
        }

        // M1/M3/M4 sit above the list AND above the empty state: a lookup is most
        // useful exactly when the ticket is not on the board.
        final header = TaskListHeader(
          countLabel : model == null ? null : taskListCountLabel( model, DateTime.now() ),
          lookup     : context.read<TaskListBloc>().lookupTask,
        );

        // An empty list renders an EMPTY STATE, not a blank screen. A blank pane and a
        // broken pane look identical, and only one of them is fine.
        if ( model == null || model.groups.isEmpty ) {
          return Column(
            children : [
              header,
              const Expanded(
                child : Center(
                  key   : Key( TestKeys.taskListEmptyState ),
                  child : Text( 'Nothing owed.' ),
                ),
              ),
            ],
          );
        }

        return Column(
          children : [
            header,
            if ( state.incomplete ) _incompleteBanner( context, state ),
            if ( state.error != null ) _writeNotice( context, state.error! ),
            Expanded( child: _list( context, state, model ) ),
          ],
        );
      },
    );
  }

  /// What the operator is told when a write did not land.
  ///
  /// 🔴 A ROLLED-BACK WRITE THAT SAYS NOTHING IS A ROW THAT SILENTLY UN-HAPPENS. The
  /// bloc has always set `state.error` on a failed or 202'd write, and this pane rendered
  /// it ONLY when there were no rows — so every write error on a populated board was
  /// invisible. The row came back, the operator's typing was gone, and nothing on screen
  /// said why.
  ///
  /// ⚠️ THAT WAS SURVIVABLE WHILE TWO VERBS COULD FAIL AND IS NOT NOW. Before this row
  /// the only reachable writes were approve and un-park, neither of which asks the
  /// operator for anything. Five of the seven now do, and each one costs a reason they
  /// composed — a 202 on a park throws away a quoted decisive sentence and, without this,
  /// looks exactly like a tap that missed.
  ///
  /// The 202 is the case that matters most: `TaskAwaitingApprovalException` is not a
  /// failure. The request SUCCEEDED and the change did not happen, so the operator must
  /// be told it is pending review — not that it failed, and not that it worked.
  ///
  /// A live region, because the notice appears in response to a press and a TalkBack user
  /// whose focus is still on the button they pressed is told nothing otherwise.
  /// ⚠️ THE FLAG MUST END UP ON THE NODE THAT CARRIES THE WORDS, which is why this is
  /// `MergeSemantics` over `Semantics` over the container rather than a bare `Semantics`
  /// around the text. A live region on a node with no label of its own fires on something
  /// that says nothing while the sentence the user needs sits one level down. The same
  /// trap `TaskRow._verbButton` documents, and the widget test asserts the flag on the
  /// node the notice's own key resolves to.
  Widget _writeNotice( BuildContext context, String message ) {
    return MergeSemantics(
      child : Semantics(
        liveRegion : true,
        child      : Container(
          key     : const Key( TestKeys.taskListWriteNotice ),
          width   : double.infinity,
          color   : Theme.of( context ).colorScheme.errorContainer,
          padding : const EdgeInsets.symmetric( vertical: 8, horizontal: 16 ),
          child   : Text( message ),
        ),
      ),
    );
  }

  /// 🔴 A SHORT PAGE MUST SAY SO. `truncated` / `has_more` exist precisely so a partial
  /// board cannot pass for a complete one, and the web learned the same lesson the hard
  /// way — *"the row cap is now guarded by a VISIBLE banner rather than by hoping the
  /// board stays small … Pagination was ruled out; noticing was not."*
  Widget _incompleteBanner( BuildContext context, TaskListState state ) {
    return Container(
      key     : const Key( TestKeys.taskListIncompleteBanner ),
      width   : double.infinity,
      color   : Theme.of( context ).colorScheme.secondaryContainer,
      padding : const EdgeInsets.symmetric( vertical: 8, horizontal: 16 ),
      child   : Text( 'Showing part of the board — ${state.total} rows match.' ),
    );
  }

  /// 🔴 `ListView.builder`, NOT A COLUMN OF 500 BUILT WIDGETS. The query asks for up to
  /// 500 rows and each carries a disclosure surface; building them all eagerly costs the
  /// frame budget for rows nobody has scrolled to.
  ///
  /// Groups and their rows are flattened into ONE index space so the whole pane is lazy —
  /// a `ListView` of `Column`s would build every row of every expanded group up front and
  /// look identical from the outside.
  Widget _list( BuildContext context, TaskListState state, TaskListModel model ) {
    final items = _flatten( model, state.collapsed );

    return RefreshIndicator(
      // Pull-to-refresh: the gesture a phone user reaches for, and it costs nothing.
      onRefresh : () async =>
          context.read<TaskListBloc>().add( const TaskListRefreshRequested() ),
      child     : ListView.builder(
        key         : const Key( TestKeys.taskListView ),
        itemCount   : items.length,
        itemBuilder : ( context, i ) => _buildItem( context, state, items[ i ] ),
      ),
    );
  }

  Widget _buildItem( BuildContext context, TaskListState state, _Item item ) {
    if ( item.group != null ) {
      final label = item.group!.ownerPersona ?? 'Unassigned';
      return TaskGroupHeader(
        ownerLabel : label,
        count      : item.group!.tasks.length,
        expanded   : !state.collapsed.contains( label ),
        onToggle   : () =>
            context.read<TaskListBloc>().add( TaskListGroupToggled( label ) ),
      );
    }

    // 🔴 INDENTED UNDER ITS PERSONA, NOT FLUSH LEFT. Rick, walking it on the emulator
    // 2026-09-23: rows *"crushed up against the left hand side … they should be indented
    // to reflect containment by each persona."* The left inset is the header's own text
    // start, so a row lines up under the name it belongs to rather than under the chevron.
    return Padding(
      key     : Key( '${TestKeys.taskListRowIndentPrefix}${item.row!.id}' ),
      padding : const EdgeInsets.fromLTRB( TaskGroupHeader.textInset, 4, 16, 4 ),
      child   : TaskRow(
        model        : item.row!,
        verbs        : _verbsFor( item.row! ),
        ownerOptions : state.reassignTargets,
        // G6: the row wears what the operator did that has not landed. Visible state,
        // not only a notice — the notice says "something failed" while they are looking
        // at fifty rows, and the question they are asking is whether THEIRS landed.
        unsentLabel  : state.unsentLabelFor( item.row!.id ),
        // The row owns arming; the BLOC owns the write and the rollback. Routing it through
        // an event rather than calling the repository from here keeps the optimistic
        // repaint and its undo in one place — a pane that wrote directly would have to
        // reimplement rollback, and a second rollback is a second thing to get wrong.
        onVerb : ( verb ) => context
            .read<TaskListBloc>()
            .add( TaskListVerbPressed( taskId: item.row!.id, verb: verb ) ),
        // 🔴 THE OTHER DOOR, AND ITS OWN EVENT. `TaskListFieldChanged` has had a handler
        // in the bloc since Phase 3 and NOTHING DISPATCHED IT — gap G2, a write path
        // built, tested, and unreachable from the UI. Routing a field change through
        // `TaskListVerbPressed` instead would post it to the TRANSITION endpoint, which
        // is §4.2's named failure read backwards.
        onFieldChanged : ( { String? priority, String? ownerPersona } ) => context
            .read<TaskListBloc>()
            .add( TaskListFieldChanged(
              taskId       : item.row!.id,
              priority     : priority,
              ownerPersona : ownerPersona,
            ) ),
      ),
    );
  }

  /// Which verbs a row offers. Passed as DATA — a list of verbs is not a pane
  /// discriminator, and both task panes may pass the same list.
  ///
  /// 🔴 THE LEGALITY LIVES IN `verbLegality`, NOT HERE, and that is the web's rule
  /// carried verbatim: *"Two derivations of one rule agree until the day they do not, and
  /// the day they do not the cell offers a move the server refuses — which reads to the
  /// operator as the board being broken rather than as the move being illegal."* This
  /// method used to BE a second derivation — two hand-written `row.status ==` tests — and
  /// it offered two of the seven verbs.
  ///
  /// ⚠️ ONLY THE LEGAL VERBS ARE RENDERED, WHERE THE WEB GREYS THE ILLEGAL ONES, AND THE
  /// DIVERGENCE IS DELIBERATE. A greyed `<option>` inside a select costs nothing: it is
  /// not on screen until the select is opened, and it teaches the operator why the move
  /// is unavailable when it is. A greyed BUTTON in a 360 dp `Wrap` costs a line of
  /// vertical space on every row and puts a dead 48 dp target next to a live one — on the
  /// surface where §7.4 says a mis-tap is likelier than a mis-click. The reason each verb
  /// is unavailable is still computed and still tested; what changes is that a phone does
  /// not pay row height to display four sentences about moves the operator did not ask
  /// for.
  List<VerbNeeds> _verbsFor( TaskRowModel row ) {
    return verbLegality( row.status )
        .where( ( entry ) => entry.enabled )
        .map( ( entry ) => entry.needs )
        .toList( growable: false );
  }

  /// Flatten groups + rows into one lazy index space, honouring collapse.
  List<_Item> _flatten( TaskListModel model, Set<String> collapsed ) {
    final out = <_Item>[];
    for ( final group in model.groups ) {
      final label = group.ownerPersona ?? 'Unassigned';
      out.add( _Item.group( group ) );
      if ( collapsed.contains( label ) ) continue;
      for ( final row in group.tasks ) {
        out.add( _Item.row( row ) );
      }
    }
    return out;
  }
}

class _Item {
  final TaskGroup? group;
  final TaskRowModel? row;

  const _Item.group( this.group ) : row = null;
  const _Item.row( this.row ) : group = null;
}
