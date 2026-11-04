import 'package:dio/dio.dart';

import '../../fleet/data/task_row_model.dart';
import 'new_ticket.dart';
import 'task_lookup.dart';

/// Reads the Task List page.
///
/// Writes are not here. They live in the shared `TaskWriteRepository`. Both task panes
/// press the same verbs through the same two doors. A per-pane copy of the 202 check
/// would be a completely silent defect.
class TaskListRepository {
  final Dio _dio;

  /// Creates the repository over the shared Dio.
  const TaskListRepository( this._dio );

  /// The page query; every parameter in it matters.
  ///
  /// `char_budget=0` opts out of the server's response byte budget, and `terse=true` is
  /// what keeps the page small. Dropping `char_budget=0` would apply
  /// `RESPONSE_CHAR_BUDGET = 100_000` against rows of about 4,242 characters, admitting
  /// about 23 of 500 rows. So `terse=true` makes rows smaller, not fewer: 214 characters
  /// per row, about 107 KB for the page instead of about 2.1 MB.
  /// `hide_parked=false` keeps parked rows, which are open work a human ruled not-now.
  /// They rejoin the owed set when their chase expires, and hiding them would make the
  /// pane quietly incomplete.
  static const path =
      '/api/tasks?limit=500&unscoped_audit=true&hide_parked=false&char_budget=0&terse=true';

  /// Fetches the Task List page.
  ///
  /// A cancelled request rethrows the DioException untranslated, so the bloc can tell a
  /// lifecycle cancellation from a failure; any other failure raises
  /// [TaskListFetchException].
  Future<TaskListPage> fetch( { CancelToken? cancelToken } ) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.get<Map<String, dynamic>>( path, cancelToken: cancelToken );
    } on DioException catch ( e ) {
      // A cancellation is the lifecycle rule working, not a failure; let it through
      // untranslated.
      if ( CancelToken.isCancel( e ) ) rethrow;
      throw TaskListFetchException( 'task list fetch failed', cause: e );
    }

    return TaskListPage.fromJson( res.data ?? const <String, dynamic>{} );
  }

  /// Fetches one row by a lookup path from `taskLookupPath`.
  ///
  /// The row is the full row, not terse: the lookup answers "what is this hash", and the
  /// status and body are the answer. The single-row endpoint has no terse projection.
  ///
  /// Requires:
  ///   - [path] came from `taskLookupPath`, never assembled here
  ///
  /// Ensures:
  ///   - a 200 returns the row
  ///   - any failure raises [TaskLookupException] with the status (0 when nothing
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

  /// Files one ticket from the New Ticket card.
  ///
  /// It is here and not in `TaskWriteRepository`, which holds the verbs both task panes
  /// press on existing rows; creating belongs to the Task List alone.
  ///
  /// Requires:
  ///   - [payload] came from `buildNewTicketPayload`
  ///
  /// Ensures:
  ///   - never throws: every answer, including none, returns a [NewTicketResponse] for
  ///     `describeNewTicketResult` to word
  ///   - status 0 means nothing answered, which is not a refusal; the row may exist
  Future<NewTicketResponse> createTicket( Map<String, String> payload ) async {
    try {
      final res = await _dio.post<Object>( '/api/tasks', data: payload );
      return NewTicketResponse( res.statusCode ?? 0, res.data );
    } on DioException catch ( e ) {
      final response = e.response;
      return NewTicketResponse( response?.statusCode ?? 0, response?.data );
    }
  }
}

/// One page, envelope included.
///
/// The `truncated`, `total` and `has_more` fields are read, not discarded, so a short page
/// cannot pass for a complete one. The server added them because `count` alone was read as
/// the size of the result. A pane that renders `tasks` and drops them is a silent
/// truncation.
class TaskListPage {
  /// The rows on this page.
  final List<TaskRowModel> rows;

  /// True when the server's byte budget stopped serialization before the row bound did.
  final bool truncated;

  /// The true row count for the same filters; page-independent, not `rows.length`.
  final int total;

  /// `offset + count < total`.
  final bool hasMore;

  /// Server-side notices meant for the caller, not for a log nobody reads.
  final List<String> warnings;

  /// Creates a page.
  const TaskListPage( {
    required this.rows,
    required this.truncated,
    required this.total,
    required this.hasMore,
    required this.warnings,
  } );

  /// True when the page the operator is looking at is not the whole board.
  ///
  /// The pane surfaces this as a visible banner, because the web guards its row cap with
  /// a banner instead of hoping the board stays small. Pagination was ruled out.
  bool get isIncomplete => truncated || hasMore;

  /// Parses the `/api/tasks` envelope; a missing field takes an empty or false default.
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

/// A Task List fetch that failed.
class TaskListFetchException implements Exception {
  /// A short description.
  final String message;

  /// The underlying error, usually a `DioException`.
  final Object? cause;

  /// Creates the exception.
  const TaskListFetchException( this.message, { this.cause } );

  @override
  String toString() => 'TaskListFetchException: $message'
      '${cause == null ? '' : ' (caused by $cause)'}';
}
