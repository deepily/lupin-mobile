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
/// The route owns the visibility signal. `onPaneVisible` and `onPaneHidden` make
/// foreground-pane-only polling a mechanism, and without them this pane's timer runs
/// whichever destination is showing.
class TaskListPane extends StatefulWidget {
  /// Creates the pane; it reads its [TaskListBloc] from the route.
  const TaskListPane( { super.key } );

  @override
  State<TaskListPane> createState() => _TaskListPaneState();
}

class _TaskListPaneState extends State<TaskListPane> {
  // Held as a field, not looked up in `dispose()`. `context.read` walks the element tree,
  // which is being torn down by then, so the lookup can throw and skip the rest of
  // dispose. The timer would then survive the pane, polling a screen nobody is looking at
  // for the life of the process, with no visible symptom beyond battery and data.
  late final TaskListBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<TaskListBloc>()
      ..startPolling()
      ..startConnectivityRefresh();
    // The pane is on screen the moment it is built, because it is route-scoped.
    _bloc.onPaneVisible();
    // Read the roster once on mount, not on every poll. It changes only when a seat is
    // spawned or reaped, while the board polls every 60 s on Wi-Fi, so riding the poll
    // would double the request count for a list that almost never moves.
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

        // The header sits above the list and above the empty state, because a lookup is
        // most useful when the ticket is not on the board.
        final header = TaskListHeader(
          countLabel   : model == null ? null : taskListCountLabel( model, DateTime.now() ),
          lookup       : context.read<TaskListBloc>().lookupTask,
          createTicket : context.read<TaskListBloc>().createTicket,
          assignees    : context.read<TaskListBloc>().newTicketAssignees,
        );

        // An empty list renders an empty state, not a blank screen, because a blank pane
        // and a broken pane look identical.
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

  // What the operator is told when a write did not land. A rolled-back write that says
  // nothing is a row that silently un-happens: the bloc sets `state.error` on a failed or
  // 202'd write, and without this notice the row would come back with no explanation on
  // a populated board. It matters more now that most verbs ask the operator for a reason,
  // since a 202 on a park throws away a quoted decisive sentence and would look like a
  // tap that missed. The 202 is not a failure: the request succeeded and the change did
  // not happen, so the operator is told it is pending review, neither failed nor done.
  // The notice is a live region, because it appears after a press and a TalkBack user
  // whose focus is still on the pressed button would otherwise hear nothing. The flag must
  // sit on the node that carries the words, hence `MergeSemantics` over `Semantics` over
  // the container, as `TaskRow._verbButton` does; the widget test asserts the flag on the
  // node the notice's key resolves to.
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

  // A short page must say so. `truncated` and `has_more` exist so a partial board cannot
  // pass for a complete one, and the web guards its row cap with a visible banner
  // instead of hoping the board stays small. Pagination was ruled out.
  Widget _incompleteBanner( BuildContext context, TaskListState state ) {
    return Container(
      key     : const Key( TestKeys.taskListIncompleteBanner ),
      width   : double.infinity,
      color   : Theme.of( context ).colorScheme.secondaryContainer,
      padding : const EdgeInsets.symmetric( vertical: 8, horizontal: 16 ),
      child   : Text( 'Showing part of the board — ${state.total} rows match.' ),
    );
  }

  // A `ListView.builder`, not a column of 500 built widgets. The query asks for up to 500
  // rows and each carries a disclosure surface, so building them all costs frame budget
  // for rows nobody has scrolled to. Groups and rows are flattened into one index space
  // so the whole pane is lazy; a `ListView` of `Column`s would build every row of every
  // expanded group up front.
  Widget _list( BuildContext context, TaskListState state, TaskListModel model ) {
    final items = _flatten( model, state.collapsed );

    return RefreshIndicator(
      // Pull-to-refresh: the gesture a phone user reaches for.
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

    // Indented under its persona, not flush left: the left inset is the header's own text
    // start, so a row lines up under the name it belongs to and not under the chevron.
    return Padding(
      key     : Key( '${TestKeys.taskListRowIndentPrefix}${item.row!.id}' ),
      padding : const EdgeInsets.fromLTRB( TaskGroupHeader.textInset, 4, 16, 4 ),
      child   : TaskRow(
        model        : item.row!,
        verbs        : _verbsFor( item.row! ),
        ownerOptions : state.reassignTargets,
        // The row wears what the operator did that has not landed: visible state, not only
        // a notice, because the notice says "something failed" while they look at fifty
        // rows and their question is whether theirs landed.
        unsentLabel  : state.unsentLabelFor( item.row!.id ),
        // The row owns arming; the bloc owns the write and the rollback. Routing through an
        // event keeps the optimistic repaint and its undo in one place; a pane that wrote
        // directly would need a second rollback.
        onVerb : ( verb ) => context
            .read<TaskListBloc>()
            .add( TaskListVerbPressed( taskId: item.row!.id, verb: verb ) ),
        // The other door has its own event. Routing a field change through
        // `TaskListVerbPressed` would post it to the transition endpoint, which does not
        // understand a priority.
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

  // Which verbs a row offers, passed as data; both task panes may pass the same list. The
  // legality lives in `verbLegality`, not here, because two derivations of one rule agree
  // until they do not, and then the row offers a move the server refuses, which reads as a
  // broken board. Only the legal verbs are rendered, where the web greys the illegal
  // ones. A greyed option in a web select costs nothing, but a greyed button in a 360 dp
  // `Wrap` costs a line of height on every row and puts a dead 48 dp target beside a live
  // one, on the surface where a mis-tap is likelier than a mis-click. The reason each verb
  // is unavailable is still computed and tested.
  List<VerbNeeds> _verbsFor( TaskRowModel row ) {
    return verbLegality( row.status )
        .where( ( entry ) => entry.enabled )
        .map( ( entry ) => entry.needs )
        .toList( growable: false );
  }

  // Flattens groups and rows into one lazy index space, honouring collapse.
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

// One entry in the flattened list: a group header or a row.
class _Item {
  final TaskGroup? group;
  final TaskRowModel? row;

  const _Item.group( this.group ) : row = null;
  const _Item.row( this.row ) : group = null;
}
