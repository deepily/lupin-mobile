import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/queue/domain/queue_bloc.dart';
import 'package:lupin_mobile/features/queue/domain/queue_event.dart';
import 'package:lupin_mobile/features/queue/domain/queue_state.dart';
import 'package:lupin_mobile/features/queue/presentation/queue_dashboard_screen.dart';

class _MockQueueBloc extends MockBloc<QueueEvent, QueueState> implements QueueBloc {}

/// Pins the colour the queue dashboard paints behind each job-status chip, as ARGB
/// bytes. Measured before and after the move from `Color.withOpacity( 0.2 )` to
/// `.withValues( alpha: 0.2 )`: every channel was identical (alpha 51 throughout).
void main() {
  setUpAll( () => registerFallbackValue( const QueueLoadSnapshot( "todo" ) ) );

  final expected = <String, int>{
    "running"   : 0x332196F3,   // blue,       A51 R33 G150 B243
    "completed" : 0x334CAF50,   // green,      A51 R76 G175 B80
    "failed"    : 0x33F44336,   // red,        A51 R244 G67 B54
    "paused"    : 0x33FF9800,   // orange,     A51 R255 G152 B0
    "dead"      : 0x33B71C1C,   // red.shade900, A51 R183 G28 B28
    "queued"    : 0x339E9E9E,   // grey (default), A51 R158 G158 B158
  };

  for ( final e in expected.entries ) {
    testWidgets( "job status chip '${e.key}' paints ${e.value.toRadixString( 16 )}", ( tester ) async {
      final bloc = _MockQueueBloc();
      whenListen(
        bloc,
        Stream<QueueState>.fromIterable( [
          QueueSnapshotLoaded( QueueResponse(
            queueName   : JobLane.values.first.name,
            jobs        : [ JobSummary( jobId: "j-1", status: e.key ) ],
            filteredBy  : "",
            isAdminView : false,
            totalJobs   : 1,
          ) ),
        ] ),
        initialState: const QueueInitial(),
      );
      await tester.pumpWidget( MaterialApp(
        home: BlocProvider<QueueBloc>.value( value: bloc, child: const QueueDashboardScreen() ),
      ) );
      await tester.pump();

      final chip = tester.widget<Chip>( find.widgetWithText( Chip, e.key ) );
      expect( chip.backgroundColor!.toARGB32(), e.value );
    });
  }
}
