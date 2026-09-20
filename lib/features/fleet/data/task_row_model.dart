import 'task_row_schema.dart';

/// One task-store row, as the shared row widget consumes it.
///
/// Maps the `/api/tasks` wire shape onto the twelve cells of [RowSchema]. Field names
/// are the SERVER's, not re-spelled: `item_class` stays `itemClass`, `created_by` stays
/// `createdBy`. One name at every layer is the rule the server's own terse projection
/// follows, and a rename here would make a wire-shape question un-greppable.
class TaskRowModel {
  final String  id;
  final String  title;
  final String? itemClass;
  final String  status;
  final String? priority;
  final List<TaskBlocker> blockedBy;
  final DateTime? nextChaseTs;
  final String? accountableManager;
  final String? createdBy;
  final String? project;

  /// The task-store `body`. Absent on a terse pull — see the note on [fromJson].
  final String? detail;

  const TaskRowModel( {
    required this.id,
    required this.title,
    required this.status,
    this.itemClass,
    this.priority,
    this.blockedBy          = const <TaskBlocker>[],
    this.nextChaseTs,
    this.accountableManager,
    this.createdBy,
    this.project,
    this.detail,
  } );

  /// Build from one `/api/tasks` row.
  ///
  /// ⚠️ TERSE ROWS DO NOT CARRY EVERY CELL, AND THAT IS THE INTENDED QUERY SHAPE.
  /// The panes pull with `terse=true` because a full 500-row page measures ~2.1 MB
  /// against ~107 KB terse (`tasks.py:739` — *"21,379 chars terse and 424,209 chars
  /// full"*). The terse projection carries ten of the twelve cells; `detail` (`body`) is
  /// dropped deliberately because it is the multi-KB field that makes rows heavy, and
  /// `class` (`item_class`) is a genuine gap in the projection tracked as its own
  /// lupin-side row.
  ///
  /// ⇒ Both arrive as null and the row renders them as absent. `detail` is fetched on
  /// disclosure, which is the right phone shape regardless. A missing cell must never
  /// throw: a pane that crashes on the query shape it is specified to use is a pane that
  /// never ran.
  factory TaskRowModel.fromJson( Map<String, dynamic> json ) {
    return TaskRowModel(
      id                 : json[ 'id' ] as String,
      title              : ( json[ 'title' ] as String? ) ?? '',
      itemClass          : json[ 'item_class' ] as String?,
      status             : ( json[ 'status' ] as String? ) ?? '',
      priority           : json[ 'priority' ] as String?,
      blockedBy          : _blockers( json[ 'blocked_by' ] ),
      nextChaseTs        : _ts( json[ 'next_chase_ts' ] ),
      accountableManager : json[ 'accountable_manager' ] as String?,
      createdBy          : json[ 'created_by' ] as String?,
      project            : json[ 'project' ] as String?,
      detail             : json[ 'body' ] as String?,
    );
  }

  /// The value for one schema cell, or null when this row does not carry it.
  ///
  /// Keyed by [RowCell.key] so the widget can walk [RowSchema.all] rather than
  /// hand-listing fields — which is what keeps the two panes cell-for-cell identical
  /// without either of them knowing about the other.
  String? cell( String key ) {
    switch ( key ) {
      case 'id'          : return id;
      case 'title'       : return title;
      case 'class'       : return itemClass;
      case 'status'      : return status;
      case 'priority'    : return priority;
      case 'blocked'     : return blockedBy.isEmpty ? null : blockedBy.map( ( b ) => b.id ).join( ', ' );
      case 'chase'       : return nextChaseTs?.toIso8601String();
      case 'accountable' : return accountableManager;
      case 'filer'       : return createdBy;
      case 'project'     : return project;
      case 'detail'      : return detail;
      case 'actions'     : return null;   // rendered as controls, not text
      default            : return null;
    }
  }

  static List<TaskBlocker> _blockers( dynamic raw ) {
    if ( raw is! List ) return const <TaskBlocker>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map( TaskBlocker.fromJson )
        .toList( growable: false );
  }

  /// ⚠️ A BAD TIMESTAMP IS NULL, NOT A THROW. `next_chase_ts` is operator-set and has
  /// arrived malformed before; one unparseable date must not take down a 500-row pane.
  static DateTime? _ts( dynamic raw ) {
    if ( raw is! String || raw.isEmpty ) return null;
    return DateTime.tryParse( raw );
  }
}

/// A typed `blocked_by` reference — `{kind, id}`, where kind is item | persona | user.
class TaskBlocker {
  final String kind;
  final String id;

  const TaskBlocker( { required this.kind, required this.id } );

  factory TaskBlocker.fromJson( Map<String, dynamic> json ) => TaskBlocker(
        kind : ( json[ 'kind' ] as String? ) ?? '',
        id   : ( json[ 'id' ] as String? ) ?? '',
      );
}
