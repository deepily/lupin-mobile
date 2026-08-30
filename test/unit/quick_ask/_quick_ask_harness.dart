/// Shared harness for the Quick Ask bloc tests.
///
/// Everything here is a REAL `QuickAskBloc` driven through real events. No
/// `MockBloc` — mocking the bloc would replace the very computation these
/// tests exist to check (AC-S2.2a / AC-S2.5a), leaving assertions that pass
/// unchanged against an inverted predicate.
library;

import 'dart:async';

import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/data/queue_repository.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class MockQueueRepository  extends Mock implements QueueRepository  {}
class MockAsrService       extends Mock implements AsrService       {}
class MockWebSocketService extends Mock implements WebSocketService {}

const ourEmail   = 'rick@lupin.test';
const ourSession = 'wise penguin';
const ourJob     = 'job-ours';

/// A `job_state_transition` frame in the EXACT wire shape — `queue_util.py`
/// builds `{job_id, from_state, to_state, timestamp}` plus `metadata`.
Map<String, dynamic> transitionFrame( {
  String  jobId     = ourJob,
  String  from      = 'pending',
  required String to,
  String? question  = 'what is the weather',
  String? email     = ourEmail,
  String? sessionId,
  String? responseText,
  String? error,
  String? metaStatus,
  Map<String, dynamic>? extraMeta,
} ) => {
  'type'       : 'job_state_transition',
  'job_id'     : jobId,
  'from_state' : from,
  'to_state'   : to,
  'timestamp'  : '2026-08-29T20:00:00',
  'metadata'   : {
    if ( question     != null ) 'question_text' : question,
    if ( email        != null ) 'user_email'    : email,
    if ( sessionId    != null ) 'session_id'    : sessionId,
    if ( responseText != null ) 'response_text' : responseText,
    if ( error        != null ) 'error'         : error,
    if ( metaStatus   != null ) 'status'        : metaStatus,
    'agent_type' : 'weather',
    ...?extraMeta,
  },
};

AskResponse waitingAsk( { String? jobId = ourJob } ) => AskResponse(
  path        : 'agent',
  status      : 'waiting',
  routeReason : 'router:weather',
  traceId     : 'tr-1',
  jobId       : jobId,
);

JobSummary summaryRow( {
  String  jobId  = ourJob,
  String  status = 'running',
  String? responseText,
  String? error,
} ) => JobSummary(
  jobId        : jobId,
  questionText : 'what is the weather',
  status       : status,
  responseText : responseText,
  error        : error,
);

QueueResponse queueWith( String name, List<JobSummary> jobs ) => QueueResponse(
  queueName   : name,
  jobs        : jobs,
  filteredBy  : ourEmail,
  isAdminView : false,
  totalJobs   : jobs.length,
);

NotificationItem notif( {
  String  id                = 'n-1',
  String  message           = 'hello',
  bool    responseRequested = false,
  String? jobId,
} ) => NotificationItem(
  id                     : id,
  message                : message,
  type                   : 'task',
  priority               : 'high',
  timestamp              : DateTime( 2026, 8, 29 ),
  played                 : false,
  playCount              : 0,
  responseRequested      : responseRequested,
  suppressDing           : false,
  jobId                  : jobId,
  displayQualifierWidget : false,
);

/// Builds a bloc wired to mocks, with the connection stream already
/// reporting CONNECTED so the socket clause is not the one under test.
class Harness {
  late final MockQueueRepository  repo;
  late final MockAsrService       asr;
  late final MockWebSocketService ws;
  late final StreamController<bool> connCtrl;
  late final QuickAskBloc         bloc;

  /// [now] MUST be supplied inside a `fakeAsync` zone. `fake_async` fakes
  /// Timers, not `DateTime.now()`, so the watchdog's stall-threshold FLOOR —
  /// which compares wall-clock elapsed against the server's own patience —
  /// would otherwise never advance and `lost` could never be reached.
  /// Records every mic-permission request, so AC-S2.7 can assert the REQUEST
  /// was ISSUED — not merely that an error rendered, which is the falsifier.
  int  micRequests = 0;
  bool micGranted  = true;

  Harness( { bool connected = true, String? sessionId = ourSession, DateTime Function()? now } ) {
    repo     = MockQueueRepository();
    asr      = MockAsrService();
    ws       = MockWebSocketService();
    connCtrl = StreamController<bool>.broadcast();

    when( () => ws.sessionId ).thenReturn( sessionId );
    // Mirrors the real stream's replay-on-subscribe contract (AC-S1.8): each
    // listener is told the current value immediately, then follows.
    when( () => ws.connectionStream ).thenAnswer( ( _ ) async* {
      yield connected;
      yield* connCtrl.stream;
    } );

    when( () => asr.isCapturing ).thenReturn( false );
    when( () => asr.startRecording() ).thenAnswer( ( _ ) async {} );
    when( () => asr.cancelRecording() ).thenAnswer( ( _ ) async {} );

    bloc = QuickAskBloc(
      repo,
      asr                  : asr,
      ws                   : ws,
      userEmail            : ourEmail,
      now                  : now,
      requestMicPermission : () async { micRequests++; return micGranted; },
    );
  }

  /// Default: every queue listing comes back EMPTY (found-nowhere).
  void stubEmptyQueues() {
    for ( final q in const [ 'done', 'dead', 'run', 'todo' ] ) {
      when( () => repo.getQueue( q ) ).thenAnswer( ( _ ) async => queueWith( q, const [] ) );
    }
  }

  /// Our job is visible in [queue] on EVERY probe — positive proof of life.
  void stubFoundIn( String queue, { JobSummary? row } ) {
    stubEmptyQueues();
    when( () => repo.getQueue( queue ) )
        .thenAnswer( ( _ ) async => queueWith( queue, [ row ?? summaryRow() ] ) );
  }

  Future<void> dispose() async {
    await bloc.close();
    await connCtrl.close();
  }
}

/// Let the bloc's event queue drain. Bloc handlers are async, so a bare
/// `expect` right after `add()` races them.
Future<void> settle( [ int rounds = 16 ] ) async {
  for ( var i = 0; i < rounds; i++ ) {
    await Future<void>.delayed( Duration.zero );
  }
}
