/// Fakes for the Live Console's two seams: the REST reads and the socket send.
///
/// 🔴 EVERY FAKE HERE RECORDS RATHER THAN ONLY ANSWERS, because most of §5's acceptance rows
/// are about what the client ASKED FOR, not about what it did with the reply. C5.16 is "the
/// fake REST layer records a `tail_bytes` request, **not** `since_offset=0`"; C5.21 is "the
/// fake socket and REST layer record **zero** calls after the refusal". Neither can be
/// asserted against a fake that only returns a body.
///
/// ⚠️ AND EVERY ONE CAN BE MADE TO FAIL ITS OWN TEST. `PanePollingMixin`'s header states the
/// rule this repo works to — "a test that passes without the feature is worse than no test" —
/// so each fake carries a deliberate way to produce the WRONG answer, named at its field:
/// `serveFirstPageForTail` for C5.16's control, `fullTextDiffers` for C5.19's.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_models.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_repository.dart';

/// One REST call, as the client made it.
class RecordedRead {
  final String            ccSessionId;
  final Map<String, Object?> query;

  const RecordedRead( this.ccSessionId, this.query );

  bool get isTail        => query.containsKey( "tail_bytes" );
  bool get isSince       => query.containsKey( "since_offset" );
  bool get isBefore      => query.containsKey( "before_offset" );
  int?     get sinceOffset  => query[ "since_offset" ] as int?;
  int?     get beforeOffset => query[ "before_offset" ] as int?;
  int?     get maxBytes     => query[ "max_bytes" ] as int?;

  @override
  String toString() => "$ccSessionId $query";
}

/// A `TranscriptRepository` whose answers and recordings the test dictates.
class FakeTranscriptRepository extends TranscriptRepository {
  FakeTranscriptRepository() : super( _unusedDio );

  static final Dio _unusedDio = Dio();

  final List<RecordedRead> reads = [];

  /// What a tail / since / before read answers with. Set per test.
  TranscriptBacklog tail   = const TranscriptBacklog();
  TranscriptBacklog since  = const TranscriptBacklog();
  TranscriptBacklog before = const TranscriptBacklog();

  /// One block's full text, for C5.19.
  TranscriptBacklog full = const TranscriptBacklog();

  /// Thrown instead of answering, when set. Cleared by the test between phases.
  Object? throws;

  /// Only the NEXT read throws. For "the first fetch fails, the retry succeeds" shapes.
  Object? throwsOnce;

  /// 🔴 C5.16's NEGATIVE CONTROL, AS A SWITCH. With this true the fake serves the FIRST page
  /// for a tail read — which is exactly what a server implementing `since_offset=0` would do,
  /// and what ruling Q6 forbids. C5.16 must go red with it on, or the row is asserting
  /// nothing.
  bool serveFirstPageForTail = false;

  /// The "first page", served when [serveFirstPageForTail] is on.
  TranscriptBacklog firstPage = const TranscriptBacklog();

  int get readCount => reads.length;
  int countWhere( bool Function( RecordedRead ) p ) => reads.where( p ).length;
  void clearReads() => reads.clear();

  Future<TranscriptBacklog> _answer(
    String id,
    Map<String, Object?> query,
    TranscriptBacklog body,
    CancelToken token,
  ) async {
    reads.add( RecordedRead( id, query ) );

    // A cancelled token must behave like a cancelled Dio call, or a test of "the route
    // closed mid-fetch" passes against a fake that ignored the cancellation.
    if ( token.isCancelled ) {
      throw DioException.requestCancelled(
        requestOptions : RequestOptions( path: "/fake" ),
        reason         : null,
      );
    }

    final once = throwsOnce;
    if ( once != null ) {
      throwsOnce = null;
      throw once;
    }
    if ( throws != null ) throw throws!;

    return body;
  }

  @override
  Future<TranscriptBacklog> fetchTail( {
    required String      ccSessionId,
    required CancelToken cancelToken,
    int                  tailBytes = TranscriptRepository.openTailBytes,
  } ) {
    return _answer(
      ccSessionId,
      { "tail_bytes": tailBytes },
      serveFirstPageForTail ? firstPage : tail,
      cancelToken,
    );
  }

  @override
  Future<TranscriptBacklog> fetchSince( {
    required String      ccSessionId,
    required int         sinceOffset,
    required CancelToken cancelToken,
    int?                 maxBytes,
  } ) {
    return _answer(
      ccSessionId,
      {
        "since_offset" : sinceOffset,
        if ( maxBytes != null ) "max_bytes": maxBytes,
      },
      since,
      cancelToken,
    );
  }

  @override
  Future<TranscriptBacklog> fetchBefore( {
    required String      ccSessionId,
    required int         beforeOffset,
    required CancelToken cancelToken,
    int                  maxBytes = TranscriptRepository.pageBytes,
  } ) {
    return _answer(
      ccSessionId,
      { "before_offset": beforeOffset, "max_bytes": maxBytes },
      before,
      cancelToken,
    );
  }

  @override
  Future<TranscriptBacklog> fetchFullBlock( {
    required String      ccSessionId,
    required int         blockOffset,
    required CancelToken cancelToken,
  } ) {
    return _answer(
      ccSessionId,
      { "since_offset": blockOffset, "max_bytes": 0 },
      full,
      cancelToken,
    );
  }
}

/// Records every frame the bloc sends over the socket.
class RecordingSender {
  final List<Map<String, dynamic>> sent = [];

  /// Set to throw, for "the socket is gone" paths.
  Object? throws;

  Future<void> call( Map<String, dynamic> frame ) async {
    sent.add( frame );
    if ( throws != null ) throw throws!;
  }

  List<Map<String, dynamic>> ofType( String type ) =>
      sent.where( ( f ) => f[ "type" ] == type ).toList();

  int countOfType( String type ) => ofType( type ).length;
  void clear() => sent.clear();
}

/// A lifecycle stream a test can push states into, standing in for the singleton
/// `AppLifecycleService` — which has a private constructor and cannot be faked, so the
/// STREAM is the seam (`pane_polling_mixin.dart:86`, `broadcast_bloc.dart:242`).
class FakeLifecycle {
  final StreamController<AppLifecycleState> controller =
      StreamController<AppLifecycleState>.broadcast();

  Stream<AppLifecycleState> get stream => controller.stream;

  /// A full background round trip: away, then back.
  ///
  /// 🔴 `gap` IS MANDATORY INSIDE `testWidgets`, AND OMITTING IT HANGS THE TEST FOREVER —
  /// not a failure, a hang. The default gap is a real `Future.delayed`, which is a TIMER;
  /// `testWidgets` runs in a fake-async zone whose clock only advances on `tester.pump`, so
  /// nothing outside `tester.runAsync` ever completes that timer and the `await` never
  /// returns. A plain `test()` has a real clock and the default is correct there. Measured
  /// 2026-09-27: two `testWidgets` rows in the C5.7/C5.11 file hung on exactly this.
  /// In a widget test pass `gap: () => tester.pump( const Duration( milliseconds: 10 ) )`.
  Future<void> roundTrip( { Future<void> Function()? gap } ) async {
    final settle = gap ?? () => Future<void>.delayed( Duration.zero );
    controller.add( AppLifecycleState.paused );
    await settle();
    controller.add( AppLifecycleState.resumed );
    await settle();
  }

  Future<void> close() => controller.close();
}

/// Build a block without repeating the named arguments in forty places.
TranscriptBlock block( {
  TranscriptBlockKind kind = TranscriptBlockKind.text,
  String text = "hello",
  String? rawKind,
  bool truncated = false,
  String? name,
  int? offset,
} ) => TranscriptBlock(
  kind      : kind,
  text      : text,
  rawKind   : rawKind,
  truncated : truncated,
  name      : name,
  offset    : offset,
);

/// Build a backlog body.
TranscriptBacklog backlog( {
  String? epoch = "epoch-1",
  int? offset = 0,
  int? nextOffset = 100,
  List<TranscriptBlock>? blocks,
  bool atStart = false,
} ) => TranscriptBacklog(
  fileEpoch  : epoch,
  offset     : offset,
  nextOffset : nextOffset,
  blocks     : blocks ?? [ block( text: "backlog" ) ],
  atStart    : atStart,
);

/// Build an append frame.
TranscriptAppend append( {
  String? id = "seat-1",
  String? epoch = "epoch-1",
  int? offset = 100,
  int? nextOffset = 200,
  List<TranscriptBlock>? blocks,
} ) => TranscriptAppend(
  ccSessionId : id,
  fileEpoch   : epoch,
  offset      : offset,
  nextOffset  : nextOffset,
  blocks      : blocks ?? [ block( text: "chunk" ) ],
);
