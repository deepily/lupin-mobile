import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../../fleet/data/task_row_model.dart';
import '../../fleet/data/task_write_repository.dart';
import '../../fleet/presentation/task_row.dart';
import '../data/task_list_model.dart';
import '../domain/task_list_bloc.dart';
import 'task_group_header.dart';

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

        // An empty list renders an EMPTY STATE, not a blank screen. A blank pane and a
        // broken pane look identical, and only one of them is fine.
        if ( model == null || model.groups.isEmpty ) {
          return const Center(
            key   : Key( TestKeys.taskListEmptyState ),
            child : Text( 'Nothing owed.' ),
          );
        }

        return Column(
          children : [
            if ( state.incomplete ) _incompleteBanner( context, state ),
            Expanded( child: _list( context, state, model ) ),
          ],
        );
      },
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
        model  : item.row!,
        verbs  : _verbsFor( item.row! ),
        // The row owns arming; the BLOC owns the write and the rollback. Routing it through
        // an event rather than calling the repository from here keeps the optimistic
        // repaint and its undo in one place — a pane that wrote directly would have to
        // reimplement rollback, and a second rollback is a second thing to get wrong.
        onVerb : ( verb ) => context
            .read<TaskListBloc>()
            .add( TaskListVerbPressed( taskId: item.row!.id, verb: verb ) ),
      ),
    );
  }

  /// Which verbs a row offers. Passed as DATA — a list of verbs is not a pane
  /// discriminator, and both task panes may pass the same list.
  List<TaskVerb> _verbsFor( TaskRowModel row ) {
    return <TaskVerb>[
      if ( row.status == 'not_approved' ) TaskVerb.approve(),
      if ( row.status == 'parked' ) TaskVerb.unpark(),
    ];
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
