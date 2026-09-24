import 'package:dio/dio.dart';

import '../../fleet/data/task_row_model.dart';
import 'task_lookup.dart';

/// Reads the Task List page.
///
/// Writes are NOT here — they live in the shared `TaskWriteRepository`, because both
/// task panes press the same verbs through the same two doors and a per-pane copy of the
/// 202 check is the one defect that is completely silent.
class TaskListRepository {
  final Dio _dio;

  const TaskListRepository( this._dio );

  /// 🔴 THE QUERY, AND EVERY PARAMETER IN IT IS LOAD-BEARING.
  ///
  /// `char_budget=0` is **KEPT**, and `terse=true` is **ADDED**. That pairing is the one
  /// §12 landed on after reversing itself, and the reversal is worth carrying because the
  /// wrong version looks more careful:
  ///
  /// - `char_budget=0` opts OUT of the server's response byte budget (`tasks.py:3196`;
  ///   the serializer's own docstring — *"budget == 0 means UNBOUNDED (the explicit
  ///   caller opt-out)"*).
  /// - Dropping it therefore does NOT trim rows gently — it applies
  ///   `RESPONSE_CHAR_BUDGET = 100_000` against rows measuring ~4,242 chars each, which
  ///   admits about **23 of 500**. The router records the same measurement
  ///   independently: *"the default budget cut it from 1100 available rows to 30"*
  ///   (`tasks.py:3189-3193`).
  /// - ⇒ **`terse=true` is the lever: SMALLER ROWS, NOT FEWER ROWS.** 214 chars/row
  ///   against 4,242 — about 107 KB for the whole page instead of ~2.1 MB.
  ///
  /// ⚠️ `hide_parked=false` is deliberate: parked rows are OPEN work a human ruled
  /// not-now, and they rejoin the owed set when their chase expires. Hiding them makes
  /// the pane quietly incomplete.
  static const path =
      '/api/tasks?limit=500&unscoped_audit=true&hide_parked=false&char_budget=0&terse=true';

  Future<TaskListPage> fetch( { CancelToken? cancelToken } ) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.get<Map<String, dynamic>>( path, cancelToken: cancelToken );
    } on DioException catch ( e ) {
      // A cancellation is not a failure — it is the lifecycle rule working. Let it
      // through untranslated so the bloc can tell the two apart.
      if ( CancelToken.isCancel( e ) ) rethrow;
      throw TaskListFetchException( 'task list fetch failed', cause: e );
    }

    return TaskListPage.fromJson( res.data ?? const <String, dynamic>{} );
  }

  /// Fetch ONE row by a lookup path from `taskLookupPath` (walk-through item M3).
  ///
  /// ⚠️ THE FULL ROW, NOT TERSE. The lookup answers "what is this hash", and the status
  /// and body are the answer; the single-row endpoint has no terse projection anyway.
  ///
  /// Requires:
  ///   - [path] came from `taskLookupPath`, never assembled here
  ///
  /// Ensures:
  ///   - a 200 -> the row
  ///   - any failure -> [TaskLookupException] carrying the status (0 when nothing
  ///     answered) and the server's `detail` when it sent one
  Future<TaskRowModel> lookup( String path ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( path );
      final data = res.data;
      if ( data == null ) throw const TaskLookupException( 0 );
      return TaskRowModel.fromJson( data );
    } on DioException catch ( e ) {
      final response = e.response;
      final body     = response?.data;
      final detail   = body is Map && body[ 'detail' ] is String ? body[ 'detail' ] as String : null;
      throw TaskLookupException( response?.statusCode ?? 0, detail: detail );
    }
  }
}

/// One page, envelope included.
///
/// 🔴 `truncated` / `total` / `has_more` ARE READ, NOT DISCARDED. They exist precisely so
/// a short page cannot pass for a complete one — `tasks.py:2979-2990` adds them because
/// `count` alone was being read as the size of the result and never was. A pane that
/// renders `tasks` and drops these is the silent-truncation failure with extra steps.
class TaskListPage {
  final List<TaskRowModel> rows;

  /// True when the server's byte budget stopped serialization before the row bound did.
  final bool truncated;

  /// A true COUNT(*) over the same filters — page-independent, NOT `rows.length`.
  final int total;

  /// `offset + count < total`.
  final bool hasMore;

  /// Server-side notices meant for the caller, not for a log nobody reads.
  final List<String> warnings;

  const TaskListPage( {
    required this.rows,
    required this.truncated,
    required this.total,
    required this.hasMore,
    required this.warnings,
  } );

  /// True when the page the operator is looking at is not the whole board.
  ///
  /// The pane surfaces this as a visible banner. The web learned the same lesson —
  /// *"the row cap is now guarded by a VISIBLE banner rather than by hoping the board
  /// stays small … Pagination was ruled out; noticing was not."*
  bool get isIncomplete => truncated || hasMore;

  factory TaskListPage.fromJson( Map<String, dynamic> json ) {
    final raw = json[ 'tasks' ];
    return TaskListPage(
      rows      : raw is List
          ? raw.whereType<Map<String, dynamic>>().map( TaskRowModel.fromJson ).toList()
          : const <TaskRowModel>[],
      truncated : json[ 'truncated' ] == true,
      total     : ( json[ 'total' ] as num? )?.toInt() ?? 0,
      hasMore   : json[ 'has_more' ] == true,
      warnings  : ( json[ 'warnings' ] as List? )?.whereType<String>().toList()
                  ?? const <String>[],
    );
  }
}

class TaskListFetchException implements Exception {
  final String message;
  final Object? cause;

  const TaskListFetchException( this.message, { this.cause } );

  @override
  String toString() => 'TaskListFetchException: $message'
      '${cause == null ? '' : ' (caused by $cause)'}';
}
