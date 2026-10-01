/// Grouping and ordering for the Task List pane.
///
/// This ports the web's `taskListModel.ts`. It is pure and degrade-safe. A malformed row
/// falls into the Unassigned bucket instead of throwing, because one bad row must not
/// take down a 500-row pane. A builder left to guess would group by project and sort by
/// `created_ts`, giving a pane that looks plausible but is a different pane.
library;

import '../../fleet/data/task_row_model.dart';

/// Statuses that mean the work is no longer owed.
const terminalStatuses = <String>{ 'done', 'dropped', 'wont_fix' };

/// Sort rank by status: most urgent first, terminal last.
///
/// The gap at 7 is needed. Unknown sits between open and terminal, so a mistyped status
/// never hides above blocked work or below finished work. `wont_fix` is 9. Without that
/// entry it would fall to the unknown rank and sort above done and dropped. A row closed
/// as will-not-do would then look more urgent than a finished one.
const statusRanks = <String, int>{
  'blocked'      : 0,
  'in_progress'  : 1,
  'claimed'      : 2,
  'review'       : 3,
  'queued'       : 4,
  // `parked` is open work a human ruled not-now: below queued, above anything terminal.
  // It rejoins the owed set when its chase expires.
  'parked'       : 5,
  // `not_approved` has not started and is not terminal; it sits at the open/terminal
  // boundary rather than among finished work.
  'not_approved' : 6,
  'done'         : 8,
  'wont_fix'     : 9,
  'dropped'      : 10,
};

/// The rank of a status the table does not know.
const unknownStatusRank = 7;

/// The sort rank of [status]; a missing or unknown status gets [unknownStatusRank].
int statusRank( String? status ) {
  if ( status == null || status.isEmpty ) return unknownStatusRank;
  return statusRanks[ status ] ?? unknownStatusRank;
}

/// The sort rank of a priority: P0 is highest and a missing or unknown one sorts last.
int priorityRank( String? priority ) {
  if ( priority == null || priority.isEmpty ) return 99;
  final m = RegExp( r'^P(\d+)$' ).firstMatch( priority );
  return m == null ? 99 : int.parse( m.group( 1 )! );
}

/// True when the status is non-terminal, meaning work is still owed.
///
/// A missing status counts as open, which is degrade-safe: a row with no status is better
/// shown than silently dropped.
bool isOpenStatus( String? status ) {
  if ( status == null || status.isEmpty ) return true;
  return !terminalStatuses.contains( status );
}

/// One owner's group.
class TaskGroup {
  /// The owner, or null for the Unassigned bucket.
  final String? ownerPersona;

  /// The group's rows, most urgent first.
  final List<TaskRowModel> tasks;

  /// Creates a group.
  const TaskGroup( { required this.ownerPersona, required this.tasks } );

  /// True for the Unassigned bucket.
  bool get isUnassigned => ownerPersona == null;

  /// The label a screen reader reads, with the count included; see `TaskGroupHeader`.
  String get label => '${ownerPersona ?? 'Unassigned'} (${tasks.length})';
}

/// The grouped Task List: owner groups plus the total count.
class TaskListModel {
  /// Every row admitted to the pane, across all groups.
  final int totalCount;

  /// The groups, alpha-sorted by owner, with Unassigned last.
  final List<TaskGroup> groups;

  /// Creates the model.
  const TaskListModel( { required this.totalCount, required this.groups } );
}

/// True when a row is parked and its park has not expired.
///
/// Parked is a status plus a live clock, not a flag, matching the web's `_taskIsParked`.
/// A parked row whose chase time has passed counts as live again, as the store counts it.
/// The headline can therefore move on a poll with no row changing. A parked row with no
/// chase time is not park-active either.
bool isParkActive( TaskRowModel row, DateTime now ) {
  if ( row.status != 'parked' ) return false;
  final chase = row.nextChaseTs;
  return chase != null && chase.isAfter( now );
}

/// The Task List headline, such as `Live: 7 · Parked: 1 · Total: 8`.
///
/// This matches the web's `_formatTaskListCount`. Live is unconditional and the parked
/// split appears only when there is something to disclose. Parked rows stay out of live
/// because counting them with live work makes the remaining-work figure fiction.
///
/// Requires:
///   - [model] holds open rows only, which `groupTasksByOwner` guarantees
///
/// Ensures:
///   - no park-active row gives `Live: L`
///   - otherwise `Live: L · Parked: P · Total: L+P`
String taskListCountLabel( TaskListModel model, DateTime now ) {
  var parked = 0;
  var total  = 0;
  for ( final group in model.groups ) {
    for ( final row in group.tasks ) {
      total++;
      if ( isParkActive( row, now ) ) parked++;
    }
  }
  final live = total - parked;
  if ( parked <= 0 ) return 'Live: $live';
  return 'Live: $live · Parked: $parked · Total: $total';
}

/// Orders rows by priority first, then status, then title; alpha order ignores case.
///
/// Priority comes first, so a blocked P2 never outranks a queued P0. A P0 `done` row and a
/// P1 `blocked` row land in opposite orders under the alternative. Both web clients use
/// this order.
/// Design: src/docs/decisions/README.md (R-TL-priority-first)
int compareByUrgency( TaskRowModel a, TaskRowModel b ) {
  final pr = priorityRank( a.priority ) - priorityRank( b.priority );
  if ( pr != 0 ) return pr;

  final sr = statusRank( a.status ) - statusRank( b.status );
  if ( sr != 0 ) return sr;

  return a.title.toLowerCase().compareTo( b.title.toLowerCase() );
}

/// Builds the owner-grouped model.
///
/// Terminal rows are dropped, not sorted last. Finished work leaves the Task List and
/// appears in the finished list, so the pane holds only what is owed. Both web renderers
/// filter before sorting, which is why status is safe as the comparator's second key.
/// The terminal ranks exist for other callers.
/// Design: src/docs/decisions/README.md (R-TL-terminal-dropped)
TaskListModel groupTasksByOwner( List<TaskRowModel> rows ) {
  final open = rows.where( ( r ) => isOpenStatus( r.status ) ).toList( growable: false );

  final byOwner    = <String, List<TaskRowModel>>{};
  final unassigned = <TaskRowModel>[];

  for ( final row in open ) {
    // Group by `owner_persona`, not `accountable_manager`. The row displays accountable
    // and not owner, so the visible field is the easy mistake, and it gives a pane that
    // looks plausible but groups by the wrong thing.
    final owner = row.ownerPersona;
    // An owner string that is present but blank is unowned, not a group named "".
    if ( owner == null || owner.trim().isEmpty ) {
      unassigned.add( row );
    } else {
      byOwner.putIfAbsent( owner, () => <TaskRowModel>[] ).add( row );
    }
  }

  final groups = byOwner.keys.toList( growable: false )
    ..sort( ( a, b ) => a.toLowerCase().compareTo( b.toLowerCase() ) );

  final out = groups
      .map( ( owner ) => TaskGroup(
            ownerPersona : owner,
            tasks        : byOwner[ owner ]!..sort( compareByUrgency ),
          ) )
      .toList();

  // The Unassigned bucket is always last and present only when it has rows; an empty
  // bucket would be a header promising work that is not there.
  if ( unassigned.isNotEmpty ) {
    out.add( TaskGroup(
      ownerPersona : null,
      tasks        : unassigned..sort( compareByUrgency ),
    ) );
  }

  return TaskListModel( totalCount: open.length, groups: out );
}
