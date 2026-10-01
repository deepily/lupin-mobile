import 'dart:convert';

import 'package:dio/dio.dart';

import 'queue_models.dart';

/// Typed wrapper over the Lupin CJ Flow queue API.
///
/// It uses the shared Dio, whose auth interceptor adds the bearer token.
class QueueRepository {
  final Dio _dio;

  /// Creates a repository over the shared Dio.
  const QueueRepository( this._dio );

  /// Receive timeout for the ask, spoken-ask and resume calls only.
  ///
  /// The shared Dio's 30 second limit is right for every other call and is not loosened.
  /// Those calls can block while the server asks the user to confirm a near-match replay.
  /// The server retries that confirmation for roughly 210 seconds in the worst case.
  /// At 30 seconds the phone would time out on the first attempt and the user never sees the question.
  /// 240 seconds covers the whole retry ladder.
  /// The confirmation is enabled on the development server and disabled in the testing profile.
  static const Duration askReceiveTimeout = Duration( seconds: 240 );

  /// Asks one question through CJ Flow v2 and returns the synchronous [AskResponse].
  ///
  /// The answer, or the first clarifying question, is in the response and nothing is queued.
  /// An agent failure never surfaces as a 500: the server degrades to the receptionist
  /// and reports it in `status` and `error`.
  ///
  /// Raises:
  ///   - [QueueApiException] when the request fails
  Future<AskResponse> ask( AskRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v2/ask',
        data    : req.toJson(),
        options : Options( receiveTimeout: askReceiveTimeout ),
      );
      return AskResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'ask failed' );
    }
  }

  /// Path of the one-request spoken-ask endpoint.
  static const String askAudioPath = '/api/v2/ask-audio';

  /// Uploads a recording and asks it in one request, reading the reply as it arrives.
  ///
  /// [SpokenAskTranscript] arrives once the server has transcribed, then one terminal event.
  /// [SpokenAskEvent] lists the end-of-stream rules.
  /// The stream is lazy, so nothing runs until someone listens.
  ///
  /// Ensures:
  ///   - the websocket id goes on the query string, never in the form, because the server ignores it as a form field
  ///   - the multipart field is `file` and the filename is the recording's own, so the server suffix matches the format
  ///   - it uses [askReceiveTimeout], because the second line waits on the same blocking confirmation as [ask]
  ///   - it never throws; every failure is emitted as an event
  ///   - it does not delete `audioPath`, which the speech-recognition service owns
  Stream<SpokenAskEvent> askSpoken( String audioPath, String websocketId ) async* {
    final ResponseBody body;
    try {
      final form = FormData.fromMap( {
        'file': await MultipartFile.fromFile(
          audioPath,
          filename: audioPath.substring( audioPath.lastIndexOf( '/' ) + 1 ),
        ),
      } );
      final res = await _dio.post<ResponseBody>(
        askAudioPath,
        data            : form,
        queryParameters : { 'websocket_id': websocketId },
        options         : Options(
          responseType   : ResponseType.stream,
          receiveTimeout : askReceiveTimeout,
        ),
      );
      final data = res.data;
      if ( data == null ) {
        yield const SpokenAskFailed( 'closed before transcript' );
        return;
      }
      body = data;
    } on DioException catch ( e ) {
      // Build the error, then emit it. Every other caller throws the result of `_err`,
      // but a throw here would reach the bloc as an unhandled stream error instead of
      // a SpokenAskFailed. A streamed error body is still unread bytes, so decode it
      // first so `_err` can find `detail`.
      await _decodeStreamedErrorBody( e );
      final err = _err( e, 'ask-audio failed' );
      yield SpokenAskFailed( err.message, statusCode: err.statusCode );
      return;
    } catch ( e ) {
      // The recording could not be read, or anything else before a response.
      yield SpokenAskFailed( 'ask-audio failed: $e' );
      return;
    }

    String? transcript;
    try {
      final lines = body.stream
          .cast<List<int>>()
          .transform( utf8.decoder )
          .transform( const LineSplitter() );
      await for ( final line in lines ) {
        if ( line.trim().isEmpty ) continue;
        final obj  = _decodeLine( line );
        final type = obj?[ 'type' ];

        if ( transcript == null ) {
          final text = obj?[ 'transcription' ];
          if ( type == 'transcript' && text is String ) {
            transcript = text;
            yield SpokenAskTranscript( text );
            continue;
          }
          // Anything else first is a broken body: nothing usable arrived.
          yield SpokenAskFailed( type == 'error' && obj?[ 'detail' ] is String
              ? obj![ 'detail' ] as String
              : 'malformed line before transcript' );
          return;
        }

        if ( type == 'ask' && obj?[ 'result' ] is Map<String, dynamic> ) {
          // A result AskResponse cannot parse throws here and lands in the
          // catch below, which reads it as CutOff: the ask was sent.
          yield SpokenAskResult( AskResponse.fromJson( obj![ 'result' ] as Map<String, dynamic> ) );
          return;
        }
        if ( type == 'error' ) {
          final detail = obj?[ 'detail' ];
          yield SpokenAskFailed( detail is String ? detail : 'ask failed' );
          return;
        }
        // Malformed second line: the ask was sent, its result is unreadable.
        yield SpokenAskCutOff( transcript );
        return;
      }
    } catch ( _ ) {
      // Network error, receive timeout or undecodable bytes mid-body: the
      // closed-body row for its position.
      yield transcript == null
          ? const SpokenAskFailed( 'closed before transcript' )
          : SpokenAskCutOff( transcript );
      return;
    }
    // The body closed without a terminal line.
    yield transcript == null
        ? const SpokenAskFailed( 'closed before transcript' )
        : SpokenAskCutOff( transcript );
  }

  /// One NDJSON line as a JSON object, or null when it is not one.
  static Map<String, dynamic>? _decodeLine( String line ) {
    try {
      final v = jsonDecode( line );
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }

  /// Replaces the unread body of a streamed non-200 with its decoded JSON or text.
  ///
  /// A non-200 on a streamed request carries its body as an unread [ResponseBody].
  /// Decoding it lets [_err] read `detail`.
  /// A body that cannot be read leaves `_err` its `message` fallback.
  static Future<void> _decodeStreamedErrorBody( DioException e ) async {
    final response = e.response;
    if ( response == null || response.data is! ResponseBody ) return;
    try {
      final text = await utf8.decodeStream(
        ( response.data as ResponseBody ).stream.cast<List<int>>() );
      try {
        response.data = jsonDecode( text );
      } on FormatException {
        response.data = text;
      }
    } catch ( _ ) {
      response.data = null;
    }
  }

  /// Submits work whose command is already decided and returns the synchronous [AskResponse].
  ///
  /// A command missing arguments comes back as `needs_input` with `argsMissing`, never parked.
  ///
  /// Raises:
  ///   - [QueueApiException] when the request fails
  Future<AskResponse> submit( SubmitRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( '/api/v2/submit', data: req.toJson() );
      return AskResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'submit failed' );
    }
  }

  /// Submits an agentic job through `/api/v2/submit` and returns the queue-and-poll shape.
  ///
  /// The mapping to [submit] is one to one: `routing_command` becomes `command`,
  /// `args` and `question` carry over unchanged, and the queue directives stay top-level.
  ///
  /// Raises:
  ///   - [QueueApiException] when the body created no job (needs input, receptionist or failed),
  ///     so the caller never sees "Job queued" without an id
  Future<PushJobResponse> pushAgentic( PushAgenticRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( '/api/v2/submit', data: req.toSubmitRequest().toJson() );
      final ask = AskResponse.fromJson( res.data! );
      if ( ask.jobId == null || ask.jobId!.isEmpty || !( ask.status == 'waiting' || ask.status == 'done' ) ) {
        throw QueueApiException(
          ask.status == 'needs_input'
              ? 'Missing: ${ask.argsMissing.join( ", " )}'
              : ( ask.error ?? ask.answer ?? 'No job was created (${ask.path}/${ask.status}: ${ask.routeReason})' ),
        );
      }
      return PushJobResponse.fromAsk( ask, websocketId: req.websocketId );
    } on DioException catch ( e ) {
      throw _err( e, 'push-agentic failed' );
    }
  }

  /// Fetches one queue (todo, run, done or dead) for the signed-in user.
  Future<QueueResponse> getQueue( String queueName ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( '/api/get-queue/$queueName' );
      return QueueResponse.fromJson( queueName, res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'getQueue($queueName) failed' );
    }
  }

  /// Cancels a job.
  Future<void> cancelJob( String jobId ) async {
    try {
      await _dio.post<dynamic>( '/api/jobs/$jobId/cancel' );
    } on DioException catch ( e ) {
      throw _err( e, 'cancelJob($jobId) failed' );
    }
  }

  /// Sends a message into a running job as a notification.
  Future<MessageDeliveredResponse> injectMessage(
    String jobId,
    String message, {
    String priority = 'normal',
  } ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/jobs/$jobId/message',
        data: { 'message': message, 'priority': priority },
      );
      return MessageDeliveredResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'injectMessage($jobId) failed' );
    }
  }

  /// Retries a job by asking its question again through `POST /api/v2/ask`.
  ///
  /// The server no longer reads the question off the stored row, so the caller supplies it.
  Future<AskResponse> retryJob( {
    required String  jobId,
    required String  questionText,
    String?          websocketId,
  } ) async {
    try {
      final req = AskRequest( question: questionText, websocketId: websocketId );
      final res = await _dio.post<Map<String, dynamic>>( '/api/v2/ask', data: req.toJson() );
      return AskResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'retryJob($jobId) failed' );
    }
  }

  /// Answers one turn of a parked interview and returns the next turn.
  ///
  /// The outcome is the same branch as [ask].
  /// It is another `parked` on the same `pending_id`, a `done` answer, or one of the resume
  /// door's two endings, `pending_expired` and `already_resumed`.
  /// All four fields go on the wire, as [ResumeRequest] explains.
  /// Dropping `websocket_id` silences the answer's speech on every turn after the first,
  /// and nothing reports a fault.
  Future<AskResponse> resume( ResumeRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v2/resume',
        data    : req.toJson(),
        // Same budget as the ask turn: a resume re-enters the same flow and
        // can hit the same blocking near-match confirmation.
        options : Options( receiveTimeout: askReceiveTimeout ),
      );
      return AskResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'resume failed' );
    }
  }

  /// Resumes a failed or interrupted job from its last checkpoint as a new job.
  Future<ResumeCheckpointResponse> resumeFromCheckpoint( String idHash ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( '/api/jobs/$idHash/resume-from-checkpoint' );
      return ResumeCheckpointResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'resumeFromCheckpoint($idHash) failed' );
    }
  }

  /// Pauses a job that is still in the todo queue.
  Future<void> pauseJob( String jobId ) async {
    try {
      await _dio.patch<dynamic>( '/api/queue/todo/$jobId/pause' );
    } on DioException catch ( e ) {
      throw _err( e, 'pauseJob($jobId) failed' );
    }
  }

  /// Resumes a paused job in the todo queue.
  Future<void> resumeJob( String jobId ) async {
    try {
      await _dio.patch<dynamic>( '/api/queue/todo/$jobId/resume' );
    } on DioException catch ( e ) {
      throw _err( e, 'resumeJob($jobId) failed' );
    }
  }

  /// Deletes a job from the named queue.
  Future<void> deleteJob( String queueName, String jobId ) async {
    try {
      await _dio.delete<dynamic>( '/api/queue/$queueName/$jobId' );
    } on DioException catch ( e ) {
      throw _err( e, 'deleteJob($queueName/$jobId) failed' );
    }
  }

  /// Fetches one page of job history, optionally filtered by status, type or age in days.
  Future<JobHistoryPage> getJobHistory( {
    String? status,
    String? jobType,
    int     limit  = 20,
    int     offset = 0,
    int?    days,
  } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/job-history',
        queryParameters: {
          if ( status  != null ) 'status'   : status,
          if ( jobType != null ) 'job_type' : jobType,
          'limit'  : limit,
          'offset' : offset,
          if ( days != null ) 'days' : days,
        },
      );
      return JobHistoryPage.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'getJobHistory failed' );
    }
  }

  /// Fetches one job history record.
  Future<JobHistoryEntry> getJobHistoryEntry( String jobId ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( '/api/job-history/$jobId' );
      return JobHistoryEntry.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'getJobHistoryEntry($jobId) failed' );
    }
  }

  /// Resets all queues and returns the server's reply; admin only.
  Future<Map<String, dynamic>> resetQueues() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( '/api/reset-queues' );
      return res.data!;
    } on DioException catch ( e ) {
      throw _err( e, 'resetQueues failed' );
    }
  }

  /// Fetches the notification interactions recorded for a job.
  Future<JobInteractionsResponse> getJobInteractions( String jobId ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( '/api/get-job-interactions/$jobId' );
      return JobInteractionsResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'getJobInteractions($jobId) failed' );
    }
  }

  /// Builds a [QueueApiException] from a failed request, preferring the server's `detail`.
  QueueApiException _err( DioException e, String fallback ) {
    final code   = e.response?.statusCode;
    final detail = e.response?.data is Map
        ? ( e.response!.data as Map )[ 'detail' ]?.toString()
        : null;
    return QueueApiException( detail ?? e.message ?? fallback, statusCode: code );
  }
}
