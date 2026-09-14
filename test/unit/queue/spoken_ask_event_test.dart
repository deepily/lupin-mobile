/// Plan rev 14 §3.2 SB3 — the `SpokenAskEvent` union compares by VALUE.
///
/// §C's bloc tests compare emitted events; without value equality those
/// comparisons are identity checks that fail a correct parser.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';

Map<String, dynamic> _askJson() => {
  'path'         : 'agent',
  'status'       : 'waiting',
  'route_reason' : 'args_complete',
  'args_known'   : [ 'location' ],
  'job_id'       : '4f2a9c7e1b3d',
  'timings_ms'   : { 't_recv': 0.0 },
  'trace_id'     : 'tr-5c1e8a20',
};

void main() {
  group( 'SpokenAskEvent (SB3)', () {
    test( 'two Results parsed from the same JSON are equal', () {
      final a = SpokenAskResult( AskResponse.fromJson( _askJson() ) );
      final b = SpokenAskResult( AskResponse.fromJson( _askJson() ) );
      expect( identical( a.response, b.response ), isFalse );
      expect( a, equals( b ) );
    } );

    test( 'Results differing only in job_id are NOT equal', () {
      final a = SpokenAskResult( AskResponse.fromJson( _askJson() ) );
      final b = SpokenAskResult( AskResponse.fromJson( { ..._askJson(), 'job_id': 'other' } ) );
      expect( a, isNot( equals( b ) ) );
    } );

    test( 'Failed compares detail AND statusCode', () {
      expect( const SpokenAskFailed( 'x', statusCode: 401 ), equals( const SpokenAskFailed( 'x', statusCode: 401 ) ) );
      expect( const SpokenAskFailed( 'x', statusCode: 401 ), isNot( equals( const SpokenAskFailed( 'x' ) ) ) );
    } );

    test( 'Transcript and CutOff with the same text are different events', () {
      expect( const SpokenAskTranscript( 'hi' ), isNot( equals( const SpokenAskCutOff( 'hi' ) ) ) );
    } );

    test( 'only Result, Failed and CutOff are terminal', () {
      expect( const SpokenAskTranscript( 'hi' ).isTerminal, isFalse );
      expect( SpokenAskResult( AskResponse.fromJson( _askJson() ) ).isTerminal, isTrue );
      expect( const SpokenAskFailed( 'x' ).isTerminal, isTrue );
      expect( const SpokenAskCutOff( 'hi' ).isTerminal, isTrue );
    } );
  } );
}
