import 'task_row_schema.dart';

/// One task-store row, as the shared row widget consumes it.
///
/// Maps the `/api/tasks` wire shape onto the twelve cells of [RowSchema].
/// Field names follow the server's: `item_class` becomes `itemClass`, `created_by`
/// becomes `createdBy`. Keeping one name per field makes a wire-shape question greppable.
class TaskRowModel {
  /// The task-store row id.
  final String  id;

  /// The row title; empty when the server sent none.
  final String  title;

  /// The row class (`item_class`); null on a terse pull.
  final String? itemClass;

  /// The stored status string; empty when the server sent none.
  final String  status;

  /// The priority label, or null.
  final String? priority;

  /// The typed `blocked_by` references; empty when the row is not blocked.
  final List<TaskBlocker> blockedBy;

  /// When the row is next due for a chase, or null when unset or unparseable.
  final DateTime? nextChaseTs;

  /// The accountable manager, shown in the `accountable` cell.
  final String? accountableManager;

  /// The persona that filed the row, shown in the `filer` cell.
  final String? createdBy;

  /// The project the row belongs to.
  final String? project;

  /// The owning persona (`owner_persona`).
  ///
  /// Not a schema cell, so it renders nowhere; the Task List groups by it. Grouping by
  /// [accountableManager] instead would group by a different person than the owner.
  final String? ownerPersona;

  /// The task-store `body`; null on a terse pull, see [TaskRowModel.fromJson].
  final String? detail;

  /// Creates a row from already-parsed fields.
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
    this.ownerPersona,
    this.detail,
  } );

  /// Builds a row from one `/api/tasks` row.
  ///
  /// The panes pull with `terse=true`: a full 500-row page is about 2.1 MB, a terse one
  /// about 107 KB. The terse projection drops `detail` (the multi-KB field) and `class`.
  ///
  /// Ensures:
  ///   - a missing `detail` or `class` arrives as null and renders as absent
  ///   - a missing cell never throws; `detail` is fetched when the row is disclosed
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
      ownerPersona       : json[ 'owner_persona' ] as String?,
      detail             : json[ 'body' ] as String?,
    );
  }

  /// The value for one schema cell, or null when this row does not carry it.
  ///
  /// Keyed by [RowCell.key], so a widget can walk [RowSchema.all] instead of listing
  /// fields by hand. That keeps the two panes cell-for-cell identical.
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

  // A malformed timestamp parses to null instead of throwing. `next_chase_ts` is
  // operator-set and can arrive malformed, and one bad date must not fail a 500-row pane.
  static DateTime? _ts( dynamic raw ) {
    if ( raw is! String || raw.isEmpty ) return null;
    return DateTime.tryParse( raw );
  }
}

/// A typed `blocked_by` reference, `{kind, id}`, where kind is item, persona or user.
class TaskBlocker {
  /// What the reference points at: `item`, `persona` or `user`.
  final String kind;

  /// The id of the thing the row is blocked on.
  final String id;

  /// Creates a blocker reference.
  const TaskBlocker( { required this.kind, required this.id } );

  /// Builds a blocker from one `blocked_by` entry; a missing field becomes empty.
  factory TaskBlocker.fromJson( Map<String, dynamic> json ) => TaskBlocker(
        kind : ( json[ 'kind' ] as String? ) ?? '',
        id   : ( json[ 'id' ] as String? ) ?? '',
      );
}
