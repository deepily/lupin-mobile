import 'dart:convert';

import 'package:dio/dio.dart';

import 'queue_models.dart';

/// Typed wrapper over the 14-endpoint Lupin CJ Flow queue API.
/// Uses the shared Dio (auth interceptor injects Bearer automatically).
class QueueRepository {
  final Dio _dio;
  const QueueRepository( this._dio );

  // ─────────────────────────────────────────────
  // POST /api/v2/ask  (was POST /api/push — 410 tombstone, REMOVE BY 2026-12-31)
  // ─────────────────────────────────────────────

  /// Ask one question through CJ Flow v2. SYNCHRONOUS: the answer (or the
  /// first clarifying question) is in the returned [AskResponse]; nothing is
  /// queued for polling. Never 500s for an agent failure — the server degrades
  /// to the receptionist and reports it in `status`/`error`.
  /// Per-request receive budget for the ask call ONLY (AC-S4.7, landed here
  /// because S1 owns the ask-call edits per the plan's sequencing table).
  ///
  /// The shared Dio's global 30s (`http_service.dart:45`) is right for every
  /// other call and is NOT loosened. It is wrong for exactly this one: the
  /// near-match confirmation (`rest/v2/flow.py`, `_near_match_replay` /
  /// `_user_confirms`) BLOCKS the request thread while it asks the user
  /// "is that the same as …?" — `timeout_seconds = 30`, `retry_on_timeout`,
  /// `max_attempts = 3`, `backoff_multiplier = 2.0`, so ~210s worst case.
  /// At the global 30s the phone times out at the instant the FIRST confirm
  /// attempt expires, the confirm then defaults to "no", and the user never
  /// sees the question. 240s covers the whole ladder.
  ///
  /// 🔴 Live on the dev server: `similarity confirmation enabled = true` sits
  /// in `[Lupin: Development]` (`lupin-app.ini:497`); it is `false` only under
  /// `[Lupin: Testing]`.
  static const Duration askReceiveTimeout = Duration( seconds: 240 );

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

  // ─────────────────────────────────────────────
  // POST /api/v2/ask-audio  (one request, two NDJSON lines — plan rev 14 §2.1)
  // ─────────────────────────────────────────────

  static const String askAudioPath = '/api/v2/ask-audio';

  /// Upload a recording and ask it in ONE request. The reply is read as it
  /// arrives: [SpokenAskTranscript] as soon as the server has transcribed
  /// (~280 ms), then one terminal event — see [SpokenAskEvent] for the
  /// end-of-stream rules.
  ///
  /// 🔴 `websocketId` goes on the QUERY STRING, never in the form. The server
  /// reads `websocket_id` as a query parameter; sent as a form field it is
  /// silently ignored, both lines still arrive, and the answer goes to a
  /// session nobody is listening on (§2.1 CB1).
  ///
  /// The multipart field is `file` (the server binds `file: UploadFile`) and
  /// the filename is the recording's own name, so the server's temp-file
  /// suffix matches the real format (§3.2 CB2).
  ///
  /// Never throws: every failure is emitted as an event. It does NOT delete
  /// `audioPath` — `AsrService` owns the recording (§3.2 SB2/CB3), and this
  /// stream is lazy, so nothing here runs until someone listens.
  ///
  /// Uses [askReceiveTimeout]: line 2 waits on the same blocking confirm
  /// ladder inside `flow.ask` that [ask] does.
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
      // SB5 — BUILD-THEN-EMIT. `_err` is the house mapping; every other caller
      // throws its result, and a throw here would reach §C as an unhandled
      // stream error instead of a SpokenAskFailed. A streamed error body is
      // still unread bytes, so decode it first for `_err` to find `detail`.
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

  /// A non-200 on a `ResponseType.stream` request carries its body as an
  /// unread [ResponseBody]. Replace it with the decoded JSON (or text) so
  /// [_err] can read `detail`. Best-effort: a body that cannot be read leaves
  /// `_err` its `message` fallback.
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

  // ─────────────────────────────────────────────
  // POST /api/v2/submit  (wave 2 of the v2 cutover — the eleven submit-shaped
  // doors route through this one body once the server's agentic-job path lands)
  // ─────────────────────────────────────────────

  /// Submit work whose command is already decided. Same synchronous
  /// [AskResponse] as [ask]; a command missing arguments comes back
  /// `needs_input` + `argsMissing` and is never parked.
  Future<AskResponse> submit( SubmitRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( '/api/v2/submit', data: req.toJson() );
      return AskResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'submit failed' );
    }
  }

  // ─────────────────────────────────────────────
  // PushAgenticRequest → POST /api/v2/submit   (was /api/push-agentic — wave 2)
  // ─────────────────────────────────────────────

  /// Door 10 is 1:1 with `submit`: `routing_command` → `command`, `args` /
  /// `question` verbatim, queue directives top-level. A v2 body that did not
  /// create a job (needs_input / receptionist / failed) is a [QueueApiException],
  /// never a "Job queued" with no id.
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

  // ─────────────────────────────────────────────
  // GET /api/get-queue/{queue_name}
  // ─────────────────────────────────────────────

  Future<QueueResponse> getQueue( String queueName ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( '/api/get-queue/$queueName' );
      return QueueResponse.fromJson( queueName, res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'getQueue($queueName) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/jobs/{job_id}/cancel
  // ─────────────────────────────────────────────

  Future<void> cancelJob( String jobId ) async {
    try {
      await _dio.post<dynamic>( '/api/jobs/$jobId/cancel' );
    } on DioException catch ( e ) {
      throw _err( e, 'cancelJob($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/jobs/{job_id}/message
  // ─────────────────────────────────────────────

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

  // ─────────────────────────────────────────────
  // Retry = re-ask via POST /api/v2/ask
  // (was POST /api/job-history/{job_id}/retry — 410 tombstone, REMOVE BY 2026-12-31.
  //  The old handler pulled question_text off the stored row server-side; the
  //  client now supplies it, so a retry is just the same question asked again.)
  // ─────────────────────────────────────────────

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

  // ─────────────────────────────────────────────
  // POST /api/v2/resume  (Door A — answer a PARKED ask)  AC-S4.8
  // ─────────────────────────────────────────────

  /// Answer one turn of a parked interview and get the NEXT turn back.
  ///
  /// Returns an [AskResponse] because the outcome is the same six-way
  /// branch as [ask]: another `parked` (the interview continues on the
  /// SAME `pending_id` — AC-S4.12), a `done` answer, or one of the resume
  /// door's own two endings, `pending_expired` / `already_resumed`
  /// (AC-S4.13).
  ///
  /// 🔴 All FOUR fields go on the wire — see [ResumeRequest]. Dropping
  /// `websocket_id` silences the answer's TTS on every turn after the
  /// first, and nothing reports a fault when it happens.
  Future<AskResponse> resume( ResumeRequest req ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v2/resume',
        data    : req.toJson(),
        // Same budget as the ask turn: a resume re-enters the same flow and
        // can hit the same blocking near-match confirm.
        options : Options( receiveTimeout: askReceiveTimeout ),
      );
      return AskResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'resume failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/jobs/{id_hash}/resume-from-checkpoint
  // ─────────────────────────────────────────────

  Future<ResumeCheckpointResponse> resumeFromCheckpoint( String idHash ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( '/api/jobs/$idHash/resume-from-checkpoint' );
      return ResumeCheckpointResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'resumeFromCheckpoint($idHash) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // PATCH /api/queue/todo/{job_id}/pause
  // ─────────────────────────────────────────────

  Future<void> pauseJob( String jobId ) async {
    try {
      await _dio.patch<dynamic>( '/api/queue/todo/$jobId/pause' );
    } on DioException catch ( e ) {
      throw _err( e, 'pauseJob($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // PATCH /api/queue/todo/{job_id}/resume
  // ─────────────────────────────────────────────

  Future<void> resumeJob( String jobId ) async {
    try {
      await _dio.patch<dynamic>( '/api/queue/todo/$jobId/resume' );
    } on DioException catch ( e ) {
      throw _err( e, 'resumeJob($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // DELETE /api/queue/{queue_name}/{job_id}
  // ─────────────────────────────────────────────

  Future<void> deleteJob( String queueName, String jobId ) async {
    try {
      await _dio.delete<dynamic>( '/api/queue/$queueName/$jobId' );
    } on DioException catch ( e ) {
      throw _err( e, 'deleteJob($queueName/$jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // GET /api/job-history
  // ─────────────────────────────────────────────

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

  // ─────────────────────────────────────────────
  // GET /api/job-history/{job_id}
  // ─────────────────────────────────────────────

  Future<JobHistoryEntry> getJobHistoryEntry( String jobId ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( '/api/job-history/$jobId' );
      return JobHistoryEntry.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'getJobHistoryEntry($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // POST /api/reset-queues  (admin only)
  // ─────────────────────────────────────────────

  Future<Map<String, dynamic>> resetQueues() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>( '/api/reset-queues' );
      return res.data!;
    } on DioException catch ( e ) {
      throw _err( e, 'resetQueues failed' );
    }
  }

  // ─────────────────────────────────────────────
  // GET /api/get-job-interactions/{job_id}
  // ─────────────────────────────────────────────

  Future<JobInteractionsResponse> getJobInteractions( String jobId ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( '/api/get-job-interactions/$jobId' );
      return JobInteractionsResponse.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, 'getJobInteractions($jobId) failed' );
    }
  }

  // ─────────────────────────────────────────────
  // Error helper
  // ─────────────────────────────────────────────

  QueueApiException _err( DioException e, String fallback ) {
    final code   = e.response?.statusCode;
    final detail = e.response?.data is Map
        ? ( e.response!.data as Map )[ 'detail' ]?.toString()
        : null;
    return QueueApiException( detail ?? e.message ?? fallback, statusCode: code );
  }
}
