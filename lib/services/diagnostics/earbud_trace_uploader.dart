import 'package:dio/dio.dart';

import '../../core/logging/logger.dart';
import '../audio/lupin_media_handler.dart';

/// Sends the earbud trace lines to the server, so they can be read without a cable.
///
/// Each `EarbudTrace` log line goes out as `GET /health?earbud_trace=<line>`.
/// The server's access log records the request line, and the phone's own log file is out of reach without adb.
/// It is a temporary diagnostic for the earbud taps; remove it once they are confirmed.
///
/// A failed or offline upload is dropped without a word, since a log line must never break a tap.
class EarbudTraceUploader implements LogDestination {
  /// The path the lines are sent to; any cheap GET the server already answers will do.
  static const String path = '/health';

  /// The query parameter that carries one line.
  static const String param = 'earbud_trace';

  final Dio _dio;

  /// Creates an uploader that sends through [dio].
  EarbudTraceUploader( Dio dio ) : _dio = dio;

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
