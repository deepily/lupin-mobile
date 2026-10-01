import 'package:dio/dio.dart';

import '../../task_list/data/task_list_repository.dart' show TaskListPage;

/// Reads the Holding Area page.
///
/// Writes are not here: both task panes use the shared `TaskWriteRepository`, which
/// checks the 202 response once. The envelope type [TaskListPage] comes from the Task
/// List, so one reader owns the `truncated`, `total` and `has_more` keys.
class HoldingAreaRepository {
  final Dio _dio;

  const HoldingAreaRepository( this._dio );

  /// Request path for the held set: `status=not_approved`, 500 rows, terse.
  ///
  /// The pane is the held set, not a filter over the board. The store's default query
  /// excludes held rows, so the status is named here. `char_budget=0` is needed: the
  /// default 100,000-character budget admits about 23 of 500 rows of ~4,242 characters. `terse=true` makes rows smaller instead of fewer. `hide_parked` is
  /// absent because the status is pinned and a parked row is not held.
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
