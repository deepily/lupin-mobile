import 'package:dio/dio.dart';

import 'finished_tasks_models.dart';

/// Fetches the finished-work event stream over the shared Dio.
///
/// The auth interceptor registered in `service_locator.dart` injects the Bearer token
/// and refreshes on 401, so nothing here touches credentials — the house rule, and the
/// reason the cascade struck 401 handling from this phase.
class FinishedTasksRepository {
  final Dio _dio;

  const FinishedTasksRepository( this._dio );

  static const String endpoint = "/api/tasks/events";

  /// Fetch one status's events inside the window.
  ///
  /// 🔴 ONE CALL PER STATUS, DELIBERATELY. `to_status` is an exact-match filter, so
  /// the three lit-able statuses are three requests. The alternative — fetching
  /// unfiltered and partitioning on the client — would pull every transition in the
  /// window (queued, in_progress, blocked, …) to render three of them, which on a
  /// phone is the difference between a page and a payload.
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
  ///     - 🔴 a CANCELLED request rethrows the DioException UNFLATTENED, so the caller
  ///       can tell "the pane went away" from "the fetch failed". Now that this pane
  ///       polls, that distinction is load-bearing: without it, leaving the pane
  ///       mid-poll paints an error view on the way out, and the next visit opens on a
  ///       failure that never happened. The same rule `FleetRepository.fetchState`
  ///       already follows.
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
      // A CANCELLATION IS NOT A FAILURE — see the docstring. Flattening it here would
      // make every pane exit look like a dead endpoint.
      if ( e.type == DioExceptionType.cancel ) rethrow;
      throw FinishedTasksApiException( _detail( e, "fetching '$status' events" ) );
    }
  }

  /// Fetch every status in the window, independently.
  ///
  /// 🔴 A STATUS WHOSE FETCH FAILED IS ABSENT FROM THE MAP, NOT EMPTY — and the
  /// distinction is the point. An empty list means "the window holds none of these";
  /// an absent key means "we do not know". Collapsing the two renders a failed fetch
  /// as a confident "nothing was closed today", which is the most misleading thing
  /// this pane could say. [FinishedFetchResult.succeeded] carries which is which so
  /// the pane can show a partial result honestly rather than silently.
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
  /// Events for each status whose fetch SUCCEEDED. An absent key is unknown.
  final Map<String, List<FinishedTaskEvent>> eventsByStatus;

  /// Why each failed status failed. Empty when the whole window came back.
  final Map<String, String> failures;

  final int windowDays;

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

class FinishedTasksApiException implements Exception {
  final String message;
  const FinishedTasksApiException( this.message );
  @override
  String toString() => "FinishedTasksApiException: $message";
}
