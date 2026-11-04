import 'package:dio/dio.dart';

import 'transcript_models.dart';

/// The four REST reads the Live Console needs, over one endpoint.
///
/// Every call takes a `CancelToken`, and it is required, not a courtesy. Every backlog and
/// repair fetch is cancelled when the route closes or the app backgrounds, because a
/// response must never land in a closed bloc. The token is `required` rather than a named
/// optional a caller can forget, and it must reach the Dio call or cancelling does nothing.
class TranscriptRepository {
  /// The endpoint path prefix.
  ///
  /// The path is provisional and the REST naming is an open question. "Transcript" already
  /// means speech-to-text on other surfaces, and the `cc-` prefix keeps this one
  /// unambiguous. It is one constant, so changing it is one edit.
  /// TODO: confirm the path against the server.
  static const String pathPrefix = "/api/cc-transcript";

  /// How many bytes to fetch on open: the last 64 KB of the current epoch.
  ///
  /// Never `since_offset=0`, which returns the first 64 KB. That would open the screen at
  /// the top of the transcript instead of the live end, and a test stub that serves
  /// `since_offset=0` must fail.
  static const int openTailBytes = 65536;

  /// A backwards page's size in bytes.
  static const int pageBytes = 65536;

  final Dio _dio;

  /// Creates the repository over the shared Dio.
  const TranscriptRepository( this._dio );

  String _path( String ccSessionId ) => "$pathPrefix/$ccSessionId";

  /// Fetches the last [tailBytes] of the current epoch, on screen open.
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

  /// Fetches forward from [sinceOffset], for catch-up after a background trip and gap repair.
  ///
  /// Requires:
  ///     - sinceOffset is the client's `last_next_offset`, because a gap is repaired from
  ///       there and not from 0
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

  /// Fetches a page backwards from the oldest block held, for "Load earlier".
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

  /// Fetches one server-truncated block's full text.
  ///
  /// It goes by REST and never from memory. The truncated prefix is all the client ever had,
  /// and expanding from memory would show the prefix again and call it the full text.
  /// `max_bytes: 0` is the unbounded sentinel, the same meaning `budget == 0` has on the
  /// tasks endpoint.
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

  // Performs one GET and parses the body. Query values must be scalars Dio can serialise.
  // A 2xx body is parsed. A 403 raises [TranscriptRefused], which the screen treats as
  // final: it shows a static message, sends no further watch, does not retry and offers only
  // Back; a generic exception would be retried by a caller that cannot tell a refusal from a
  // flaky network. Any other non-2xx or transport failure raises [TranscriptApiException],
  // which is retryable. A cancelled request rethrows the DioException unflattened, so the
  // bloc can tell "the route closed" from "the fetch failed".
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

/// The server will not let this caller watch this seat; the refusal is terminal.
class TranscriptRefused implements Exception {
  /// The server's own words, when it gave any.
  final String? reason;

  /// Creates the refusal, with the server's reason when it gave one.
  const TranscriptRefused( [ this.reason ] );

  @override
  String toString() => "TranscriptRefused${ reason == null ? "" : ": $reason" }";
}

/// A transport or HTTP failure that is not a refusal.
///
/// It is retryable in principle, though the console does not retry on its own and waits for
/// the next lifecycle event.
class TranscriptApiException implements Exception {
  /// The server's detail, or a status-bearing fallback.
  final String message;

  /// The HTTP status, or null for a transport failure.
  final int?   statusCode;

  /// Creates the exception.
  const TranscriptApiException( this.message, { this.statusCode } );

  @override
  String toString() => statusCode == null
      ? "TranscriptApiException: $message"
      : "TranscriptApiException($statusCode): $message";
}
