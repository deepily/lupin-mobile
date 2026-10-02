import 'package:dio/dio.dart';

import 'finished_tasks_models.dart';

/// Fetches the finished-work event stream over the shared Dio.
///
/// The auth interceptor in `service_locator.dart` supplies the Bearer token and
/// refreshes on 401, so nothing here touches credentials.
class FinishedTasksRepository {
  final Dio _dio;

  /// Creates a repository over the shared [Dio].
  const FinishedTasksRepository( this._dio );

  /// The server path the events are read from.
  static const String endpoint = "/api/tasks/events";

  /// Fetches one status's events inside the window.
  ///
  /// One call per status, because `to_status` is an exact-match filter; fetching
  /// unfiltered would pull every transition in the window to render three.
  ///
  /// Requires:
  ///     - status is one of kFinishedStatuses
  ///     - since is an ISO-8601 instant
  ///
  /// Ensures:
  ///     - returns the parsed events, newest first as the server ordered them
  ///
  /// Raises:
  ///     - FinishedTasksApiException on any transport or HTTP failure, carrying the
  ///       server's own `detail` message unedited when one was supplied
  ///     - a cancelled request rethrows the DioException unflattened, so the caller can
  ///       tell "the pane went away" from "the fetch failed"; without that, leaving the
  ///       pane mid-poll would paint an error view on the way out
  Future<List<FinishedTaskEvent>> fetchStatus( {
    required String status,
    required String since,
    int limit = kFinishedPageLimit,
    CancelToken? cancelToken,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        endpoint,
        cancelToken: cancelToken,
        queryParameters: {
          "to_status" : status,
          "since"     : since,
          "limit"     : limit,
        },
      );
      final body   = res.data;
      final events = body?[ "events" ];
      if ( events is! List ) {
        throw FinishedTasksApiException(
          "malformed response: no 'events' list for status '$status'",
        );
      }
      return events
          .cast<Map<String, dynamic>>()
          .map( FinishedTaskEvent.fromJson )
          .toList();
    } on DioException catch ( e ) {
      // A cancellation is not a failure; flattening it would make every pane exit look
      // like a dead endpoint.
      if ( e.type == DioExceptionType.cancel ) rethrow;
      throw FinishedTasksApiException( _detail( e, "fetching '$status' events" ) );
    }
  }

  /// Fetches every status in the window, independently.
  ///
  /// A failed status is absent from the map, not empty: empty means none, absent means
  /// unknown, and [FinishedFetchResult.succeeded] says which.
  ///
  /// Ensures:
  ///     - one entry per status whose fetch succeeded, in kFinishedStatuses order
  ///     - a single status failing never fails the others
  Future<FinishedFetchResult> fetchWindow( {
    required int days,
    required DateTime now,
    CancelToken? cancelToken,
  } ) async {
    final since     = windowSinceIso( days, now );
    final byStatus  = <String, List<FinishedTaskEvent>>{};
    final failures  = <String, String>{};

    for ( final status in kFinishedStatuses ) {
      try {
        byStatus[ status ] = await fetchStatus(
          status      : status,
          since       : since,
          cancelToken : cancelToken,
        );
      } on FinishedTasksApiException catch ( e ) {
        failures[ status ] = e.message;
      }
    }

    return FinishedFetchResult(
      eventsByStatus : byStatus,
      failures       : failures,
      windowDays     : clampWindowDays( days ),
    );
  }

  String _detail( DioException e, String what ) {
    final data = e.response?.data;
    if ( data is Map && data[ "detail" ] != null ) return "${data[ "detail" ]}";
    return "$what failed: ${e.message ?? e.type.name}";
  }
}

/// The outcome of one window fetch, keeping "none" and "unknown" apart.
class FinishedFetchResult {
  /// Events for each status whose fetch succeeded; an absent key means unknown.
  final Map<String, List<FinishedTaskEvent>> eventsByStatus;

  /// Why each failed status failed; empty when the whole window came back.
  final Map<String, String> failures;

  /// The window the fetch covered, in days, after clamping.
  final int windowDays;

  /// Creates a result from the per-status events, failures and window.
  const FinishedFetchResult( {
    required this.eventsByStatus,
    required this.failures,
    required this.windowDays,
  } );

  /// The statuses whose fetch actually succeeded, in kFinishedStatuses order.
  List<String> get succeeded =>
      kFinishedStatuses.where( eventsByStatus.containsKey ).toList();

  /// True when at least one status came back and at least one did not.
  bool get isPartial => failures.isNotEmpty && eventsByStatus.isNotEmpty;

  /// True when nothing came back at all.
  bool get isTotalFailure => eventsByStatus.isEmpty && failures.isNotEmpty;

  /// How many events a status holds, or null when its fetch failed.
  ///
  /// Ensures:
  ///     - a pill's count never depends on whether the pill is lit
  ///     - null is "unknown", which a pill must render differently from zero
  int? countFor( String status ) => eventsByStatus[ status ]?.length;
}

/// A failed fetch, carrying the message to show.
class FinishedTasksApiException implements Exception {
  /// The server's own message when it supplied one, else a description of the failure.
  final String message;

  /// Creates an exception with its message.
  const FinishedTasksApiException( this.message );
  @override
  String toString() => "FinishedTasksApiException: $message";
}
