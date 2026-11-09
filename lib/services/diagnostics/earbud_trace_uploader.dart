import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/logging/logger.dart';
import '../audio/lupin_media_handler.dart';

/// Sends the earbud trace lines to the server, so they can be read without a cable.
///
/// Each `EarbudTrace` log line goes out as `GET /health?earbud_trace=<line>`.
/// The server's access log records the request line, and the phone's own log file is out of reach without adb.
/// It is a temporary diagnostic for the earbud taps; remove it once they are confirmed.
///
/// It uses its own bare [Dio], not the app's shared one.
/// The shared Dio carries the auth interceptor, and a 401 on /health would start a token refresh or a sign-out.
///
/// A failed or offline upload is dropped without a word, since a log line must never break a tap.
class EarbudTraceUploader implements LogDestination {
  /// The path the lines are sent to; any cheap GET the server already answers will do.
  static const String path = '/health';

  /// The query parameter that carries one line.
  static const String param = 'earbud_trace';

  static EarbudTraceUploader? _installed;

  final Dio _dio;

  /// Creates an uploader that sends through [dio].
  EarbudTraceUploader( Dio dio ) : _dio = dio;

  /// Makes this the one uploader on the shared logger, aimed at [baseUrl].
  ///
  /// The service locator can reset and start again within one run, and each start calls this.
  /// The earlier uploader leaves the logger first, so a line is sent once.
  ///
  /// Ensures:
  ///   - exactly one uploader is registered after any number of calls
  ///   - the uploader's Dio has no interceptors and short timeouts
  /// [dio] is a test seam; production passes nothing.
  static EarbudTraceUploader install( { required String baseUrl, Dio? dio } ) {
    final previous = _installed;
    if ( previous != null ) Logger.removeDestination( previous );
    final bare = dio ?? Dio( BaseOptions(
      baseUrl        : baseUrl,
      connectTimeout : const Duration( seconds: 3 ),
      sendTimeout    : const Duration( seconds: 3 ),
      receiveTimeout : const Duration( seconds: 3 ),
    ) );
    bare.options.baseUrl = baseUrl;
    final uploader = EarbudTraceUploader( bare );
    _installed = uploader;
    Logger.addDestination( uploader );
    return uploader;
  }

  /// The uploader now on the logger, or null before the first [install].
  @visibleForTesting
  static EarbudTraceUploader? get installed => _installed;

  /// The Dio the lines go through.
  @visibleForTesting
  Dio get dio => _dio;

  /// Points later uploads at [url], after the user switches server.
  set baseUrl( String url ) => _dio.options.baseUrl = url;

  /// Sends [entry] if it is an earbud trace line; any other entry is ignored.
  ///
  /// Ensures:
  ///   - returns at once; the upload is not awaited
  ///   - a failed upload raises nothing
  @override
  void write( LogEntry entry ) {
    if ( entry.tag != LupinMediaHandler.logTag ) return;
    _dio.get<void>( path, queryParameters: { param: entry.message } ).then<void>( ( _ ) {}, onError: ( Object _ ) {} );
  }

  @override
  Future<void> flush() async {}
}
