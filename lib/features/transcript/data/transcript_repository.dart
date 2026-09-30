import 'package:dio/dio.dart';

import 'transcript_models.dart';

/// The four REST reads the Live Console needs, over §3's one endpoint.
///
/// 🔴 EVERY CALL TAKES A `CancelToken` AND IT IS NOT OPTIONAL COURTESY. §5 (C3): "Every
/// backlog and repair fetch carries a Dio `CancelToken`, cancelled when the route closes or
/// the app backgrounds… A response must never land in a closed bloc." `PanePollingMixin`
/// already says the same thing from the other side — "honour it by handing it to the Dio
/// call, or the cancellation buys nothing" — so the token is `required` here rather than a
/// named optional a caller can forget.
class TranscriptRepository {
  /// 🔴 THE PATH IS PROVISIONAL AND OSQ-6 IS OPEN ON IT. §3 proposes
  /// `/api/cc-transcript/{cc_session_id}`: "transcript" already means speech-to-text on
  /// three other surfaces in this system (`/api/v2/transcribe`,
  /// `/upload-and-transcribe-{mp3,wav}`, and `transcript` as an STT NDJSON line name), so
  /// the `cc-` prefix is what keeps it unambiguous. It is María's to carry to Rick.
  ///
  /// TODO(OSQ-6): confirm once phase 1 lands. One constant, one edit.
  static const String pathPrefix = "/api/cc-transcript";

  /// Ruling Q6's number: the LAST ~64 KB on open.
  ///
  /// 🔴 NEVER `since_offset=0`, WHICH RETURNS THE **FIRST** 64 KB. That would open the
  /// screen at the top of the transcript rather than at the live end — §2 item 4 / A2.9, and
  /// C5.16's negative control is a stub that serves `since_offset=0` and must fail the test.
  static const int openTailBytes = 65536;

  /// A backwards page's size (C-7).
  static const int pageBytes = 65536;

  final Dio _dio;

  const TranscriptRepository( this._dio );

  String _path( String ccSessionId ) => "$pathPrefix/$ccSessionId";

  /// On screen open: the last [openTailBytes] of the current epoch.
  Future<TranscriptBacklog> fetchTail( {
    required String      ccSessionId,
    required CancelToken cancelToken,
    int                  tailBytes = openTailBytes,
  } ) {
    return _get(
      ccSessionId : ccSessionId,
      cancelToken : cancelToken,
      query       : { "tail_bytes": tailBytes },
    );
  }

  /// Catch-up after a background trip, and gap repair.
  ///
  /// Requires:
  ///     - sinceOffset is the client's `last_next_offset` — §3's gap rule repairs FROM
  ///       there, not from 0
  Future<TranscriptBacklog> fetchSince( {
    required String      ccSessionId,
    required int         sinceOffset,
    required CancelToken cancelToken,
    int?                 maxBytes,
  } ) {
    return _get(
      ccSessionId : ccSessionId,
      cancelToken : cancelToken,
      query       : {
        "since_offset" : sinceOffset,
        if ( maxBytes != null ) "max_bytes": maxBytes,
      },
    );
  }

  /// "Load earlier" — a page backwards from the oldest block held (C-7).
  Future<TranscriptBacklog> fetchBefore( {
    required String      ccSessionId,
    required int         beforeOffset,
    required CancelToken cancelToken,
    int                  maxBytes = pageBytes,
  } ) {
    return _get(
      ccSessionId : ccSessionId,
      cancelToken : cancelToken,
      query       : {
        "before_offset" : beforeOffset,
        "max_bytes"     : maxBytes,
      },
    );
  }

  /// One server-truncated block's FULL text.
  ///
  /// 🔴 BY REST, NEVER FROM MEMORY (C5.19, the phone's twin of A2.4). The truncated prefix
  /// is all the client ever had; expanding from memory would show the prefix again and call
  /// it the full text. `max_bytes: 0` is §2 item 7's unbounded sentinel, adopted from
  /// `tasks.py:770-785` where `budget == 0` already means the same thing.
  Future<TranscriptBacklog> fetchFullBlock( {
    required String      ccSessionId,
    required int         blockOffset,
    required CancelToken cancelToken,
  } ) {
    return _get(
      ccSessionId : ccSessionId,
      cancelToken : cancelToken,
      query       : {
        "since_offset" : blockOffset,
        "max_bytes"    : 0,
      },
    );
  }

  /// Requires:
  ///     - query values are scalars Dio can serialise
  ///
  /// Ensures:
  ///     - a 2xx body is parsed
  ///     - a 403 raises [TranscriptRefused], which the screen treats as FINAL — §5: it
  ///       "shows a static message… sends no further watch, does not retry, and offers
  ///       only Back". A generic exception here would be retried by a caller that could not
  ///       tell a refusal from a flaky network
  ///     - any other non-2xx or transport failure raises [TranscriptApiException], which IS
  ///       retryable
  ///     - a CANCELLED request rethrows the DioException unflattened, so the bloc can tell
  ///       "the route closed" from "the fetch failed"
  Future<TranscriptBacklog> _get( {
    required String            ccSessionId,
    required CancelToken       cancelToken,
    required Map<String, Object?> query,
  } ) async {
    try {
      final res = await _dio.get<Object?>(
        _path( ccSessionId ),
        queryParameters : query,
        cancelToken     : cancelToken,
        options         : Options( validateStatus: ( _ ) => true ),
      );
      final status = res.statusCode ?? 0;

      if ( status == 403 ) {
        throw TranscriptRefused( _detailFrom( res.data ) );
      }
      if ( status < 200 || status >= 300 ) {
        throw TranscriptApiException(
          _detailFrom( res.data ) ?? "HTTP $status",
          statusCode: status,
        );
      }
      return TranscriptBacklog.fromJson( res.data );
    } on DioException catch ( e ) {
      if ( e.type == DioExceptionType.cancel ) rethrow;
      throw TranscriptApiException( e.message ?? e.type.name );
    }
  }

  static String? _detailFrom( Object? body ) {
    if ( body is Map ) {
      final detail = body[ "detail" ];
      if ( detail is String && detail.isNotEmpty ) return detail;
    }
    return null;
  }
}

/// The server will not let this caller watch this seat. **Terminal.**
class TranscriptRefused implements Exception {
  /// The server's own words, when it gave any.
  final String? reason;

  const TranscriptRefused( [ this.reason ] );

  @override
  String toString() => "TranscriptRefused${ reason == null ? "" : ": $reason" }";
}

/// A transport or HTTP failure that is NOT a refusal. Retryable in principle — though the
/// console does not retry on its own; it waits for the next lifecycle event.
class TranscriptApiException implements Exception {
  final String message;
  final int?   statusCode;

  const TranscriptApiException( this.message, { this.statusCode } );

  @override
  String toString() => statusCode == null
      ? "TranscriptApiException: $message"
      : "TranscriptApiException($statusCode): $message";
}
