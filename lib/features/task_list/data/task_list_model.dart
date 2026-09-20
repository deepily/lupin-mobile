/// Grouping and ordering for the Task List pane.
///
/// Port of `multiplexer/render/taskListModel.ts`. Pure and degrade-safe: a malformed row
/// collapses into the Unassigned bucket rather than throwing, because one bad row must
/// not take down a 500-row pane.
///
/// 🔴 A BUILDER LEFT TO GUESS GROUPS BY PROJECT AND SORTS BY `created_ts`. The pane
/// renders, looks plausible, and is a different pane. Every rule below has a receipt.
library;

import '../../fleet/data/task_row_model.dart';

/// Statuses that mean the work is no longer owed (`taskListModel.ts:89`).
const terminalStatuses = <String>{ 'done', 'dropped', 'wont_fix' };

/// Sort rank: most-urgent first, terminal last (`taskListModel.ts:93-108`).
///
/// ⚠️ THE GAP AT 7 IS LOAD-BEARING. Unknown sits BETWEEN open and terminal so a typo'd
/// status never hides above blocked work — and never below it either.
///
/// ⚠️ `wont_fix` IS 9, AND ITS ABSENCE WAS A REAL BUG. Before that entry existed it fell
/// through to the unknown rank and therefore sorted ABOVE done and dropped — a
/// closed-as-will-not-do row rendering as more urgent than a finished one.
const statusRanks = <String, int>{
  'blocked'      : 0,
  'in_progress'  : 1,
  'claimed'      : 2,
  'review'       : 3,
  'queued'       : 4,
  // `parked` is OPEN work a human ruled not-now: below queued, above anything terminal.
  // It rejoins the owed set when its chase expires.
  'parked'       : 5,
  // `not_approved` has not started and is explicitly NOT terminal — it sits at the
  // open/terminal boundary rather than among finished work.
  'not_approved' : 6,
  'done'         : 8,
  'wont_fix'     : 9,
  'dropped'      : 10,
};

const unknownStatusRank = 7;

int statusRank( String? status ) {
  if ( status == null || status.isEmpty ) return unknownStatusRank;
  return statusRanks[ status ] ?? unknownStatusRank;
}

/// P0 highest; unknown sorts last (`taskListModel.ts:141-147`).
int priorityRank( String? priority ) {
  if ( priority == null || priority.isEmpty ) return 99;
  final m = RegExp( r'^P(\d+)$' ).firstMatch( priority );
  return m == null ? 99 : int.parse( m.group( 1 )! );
}

/// True when the status is non-terminal — work still owed.
/// A missing status defaults to OPEN, which is degrade-safe: a row with no status is
/// more safely shown than silently dropped.
bool isOpenStatus( String? status ) {
  if ( status == null || status.isEmpty ) return true;
  return !terminalStatuses.contains( status );
}

/// One owner's group.
class TaskGroup {
  /// null for the Unassigned bucket.
  final String? ownerPersona;
  final List<TaskRowModel> tasks;

  const TaskGroup( { required this.ownerPersona, required this.tasks } );

  bool get isUnassigned => ownerPersona == null;

  /// The label a screen reader reads. The COUNT IS IN THE LABEL deliberately — see
  /// `TaskGroupHeader`.
  String get label => '${ownerPersona ?? 'Unassigned'} (${tasks.length})';
}

class TaskListModel {
  /// Every row admitted to the pane, across all groups.
  final int totalCount;
  final List<TaskGroup> groups;

  const TaskListModel( { required this.totalCount, required this.groups } );
}

/// 🔴 PRIORITY FIRST, THEN STATUS, THEN TITLE — AND THIS IS RICK'S RULING, NOT A
/// PREFERENCE, WHICH IS WHY IT IS WRITTEN OUT HERE RATHER THAN LEFT TO THE CODE.
///
/// `taskListModel.ts:286-289`, verbatim:
///
/// > 🔨 PRIORITY FIRST — Rick's ruling, 2026-09-09, by voice: *"obviously it's going to
/// > be priority first, but I also want to make sure that this is implemented for both
/// > clients."* He reported seeing a P2 above a P0 and was right: this comparator read
/// > STATUS first, so priority was consulted only between rows already sharing a status.
/// > A blocked P2 outranked a queued P0.
///
/// ⚠️ THE PLAN SAYS THE OPPOSITE, AND THE PLAN IS DESCRIBING THE CODE AS IT WAS BEFORE
/// HE CORRECTED IT. Both §8.3's table and this phase's own row body say "status-rank then
/// priority-rank". They were written from the rank table without opening the comparator
/// beneath it. His correction names BOTH CLIENTS explicitly, and this is one of them.
///
/// ⇒ The two rules are not cosmetically different: a P0 `done` row and a P1 `blocked` row
/// land in opposite orders under each. Raised with the manager rather than resolved
/// silently; flipping it is one line if she rules the other way.
int compareByUrgency( TaskRowModel a, TaskRowModel b ) {
  final pr = priorityRank( a.priority ) - priorityRank( b.priority );
  if ( pr != 0 ) return pr;

  final sr = statusRank( a.status ) - statusRank( b.status );
  if ( sr != 0 ) return sr;

  return a.title.toLowerCase().compareTo( b.title.toLowerCase() );
}

/// Build the owner-grouped model.
///
/// 🔴 TERMINAL ROWS ARE DROPPED, NOT SORTED LAST. `taskListModel.ts:292-297` records why,
/// and it is Rick correcting the author on exactly this point:
///
/// > *"when something gets marked as done it actually literally gets removed from the
/// > task list. It is then displayed within the finished list, by order of what's
/// > finished."*
///
/// Both web renderers filter before sorting (`TaskListRenderer.ts:307`,
/// `EpicBoardRenderer.ts:236`), which is also why status is safe as the comparator's
/// SECOND key — the terminal ranks above exist for other callers, not for this pane.
///
/// ⚠️ Sorting them to the bottom instead would leave finished work sitting in a pane Rick
/// expects to hold only what is owed. Neither the plan nor this phase's row mentions the
/// filter at all.
TaskListModel groupTasksByOwner( List<TaskRowModel> rows ) {
  final open = rows.where( ( r ) => isOpenStatus( r.status ) ).toList( growable: false );

  final byOwner    = <String, List<TaskRowModel>>{};
  final unassigned = <TaskRowModel>[];

  for ( final row in open ) {
    // `owner_persona`, NOT `accountable_manager`. The row DISPLAYS accountable and does
    // not display owner at all, so reaching for the visible field is the easy mistake —
    // and it produces a pane that renders, looks plausible, and groups by the wrong
    // thing (`taskListModel.ts:251-252`).
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

  // The Unassigned bucket is ALWAYS LAST, and only present when it has rows —
  // an empty bucket is a header promising work that is not there.
  if ( unassigned.isNotEmpty ) {
    out.add( TaskGroup(
      ownerPersona : null,
      tasks        : unassigned..sort( compareByUrgency ),
    ) );
  }

  return TaskListModel( totalCount: open.length, groups: out );
}
