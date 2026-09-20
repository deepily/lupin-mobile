import 'package:dio/dio.dart';

import '../../task_list/data/task_list_repository.dart' show TaskListPage;

/// Reads the Holding Area page.
///
/// ⚠️ WRITES ARE NOT HERE. Both task panes press the same seven verbs through the same
/// two doors, and they live once in the shared `TaskWriteRepository`. A per-pane copy of
/// the 202 check is the one defect that is completely silent — the pane paints a row
/// approved that the server only queued.
///
/// ⚠️ THE ENVELOPE TYPE IS IMPORTED FROM THE TASK LIST RATHER THAN COPIED, and that
/// import is the lesser of two wrongs. Reading `truncated` / `total` / `has_more` is not
/// pane-specific, and a second reader of the same four keys is exactly how one of them
/// later stops reading `truncated`. [TaskListPage] belongs in `fleet/data/` as shared
/// plumbing beside the row model and the write door — it is Sam's file, so that move is
/// reported to the manager rather than made here.
class HoldingAreaRepository {
  final Dio _dio;

  const HoldingAreaRepository( this._dio );

  /// 🔴 `status=not_approved` IS THE WHOLE PANE. The Holding Area is not a filter over
  /// the board — it IS the held set, work awaiting an approver. Rows here are neither
  /// terminal nor abandoned, and the store's own query defaults exclude them, which is
  /// why the pane has to name the status rather than inherit it.
  ///
  /// `char_budget=0` and `terse=true` carry over from the Task List for the reason
  /// measured there: dropping `char_budget=0` does not trim rows gently, it applies the
  /// default 100,000-char budget against ~4,242-char rows and admits about 23 of 500.
  /// `terse=true` is the lever that makes rows SMALLER rather than FEWER.
  ///
  /// ⚠️ `hide_parked` is deliberately absent. It is meaningful only when the query spans
  /// statuses; here the status is pinned and a parked row is by definition not held.
  static const path =
      '/api/tasks?limit=500&unscoped_audit=true&status=not_approved'
      '&char_budget=0&terse=true';

  Future<TaskListPage> fetch( { CancelToken? cancelToken } ) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.get<Map<String, dynamic>>( path, cancelToken: cancelToken );
    } on DioException catch ( e ) {
      // A cancellation is the lifecycle rule working, not a failure. It goes through
      // untranslated so the bloc can tell the two apart and stay quiet about one.
      if ( CancelToken.isCancel( e ) ) rethrow;
      throw HoldingAreaFetchException( 'holding area fetch failed', cause: e );
    }

    return TaskListPage.fromJson( res.data ?? const <String, dynamic>{} );
  }
}

class HoldingAreaFetchException implements Exception {
  final String message;
  final Object? cause;

  const HoldingAreaFetchException( this.message, { this.cause } );

  @override
  String toString() => 'HoldingAreaFetchException: $message'
      '${cause == null ? '' : ' (caused by $cause)'}';
}
