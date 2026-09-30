/// AC-S4.6 (wire-contract fixture pin) + AC-S4.7 (live probe, net-zero).
///
/// AC-S4.7 POSTs the CHECKED-IN canned WAV (Phase-0 fixture, gTTS-synthesized
/// to the OSQ-2 params — no microphone involved) to the dev `:7999` server.
/// When the server is unreachable the test reports SKIPPED rather than
/// failing — the live pin runs wherever `:7999` is up (the dev box), and the
/// suite stays venue-portable (laptop builds).
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../_helpers/fixture_loader.dart';

void main() {
  group( 'ASR wire contract (S4)', () {
    test( 'AC-S4.6 — Phase-0 endpoint-contract fixture parses and pins the wire facts', () {
      final contract = loadFixture( 'asr/transcribe_endpoint_contract.json' );

      expect( contract[ 'endpoint' ], 'POST /api/upload-and-transcribe-wav' );

      final osq1 = contract[ 'osq1_answer' ] as Map<String, dynamic>;
      expect( osq1[ 'auth_required' ], isFalse,
          reason: 'OSQ-1: endpoint is unauthenticated (speech.py:646-653)' );
      expect( ( osq1[ 'unauthenticated' ] as Map )[ 'status' ], 200 );
      expect( osq1[ 'response_shape' ], contains( 'JSON string literal' ) );

      // Whisper hallucinates on silence — 200 with junk text, NOT empty.
      // AsrService's empty-transcript exception is therefore necessary but
      // not sufficient silence handling; pinned here so drift is loud.
      final silence = contract[ 'silence_behavior' ] as Map<String, dynamic>;
      expect( silence[ 'status' ], 200 );
      expect( ( silence[ 'transcript' ] as String ).isNotEmpty, isTrue );

      expect( ( contract[ 'prefix_param' ] as Map )[ 'usage' ],
          contains( 'UNSET for chat replies' ) );
      expect( contract[ '_capture' ], isNotNull, reason: 'provenance block present' );
    } );

    test( 'AC-S4.7 — live probe: POST the checked-in canned WAV to :7999 → known transcript', () async {
      const wavPath = 'test/fixtures/asr/canned-focus-mode-test.wav';
      expect( File( wavPath ).existsSync(), isTrue,
          reason: 'Phase-0 canned fixture must be checked in' );

      final provenance = loadFixture( 'asr/canned-focus-mode-test.provenance.json' );
      final expected   = provenance[ 'expected_transcript' ] as String;

      final dio = Dio( BaseOptions(
        baseUrl        : 'http://localhost:7999',
        connectTimeout : const Duration( seconds: 5 ),
        receiveTimeout : const Duration( seconds: 120 ),
      ) );

      try {
        final form = FormData.fromMap( {
          'file': await MultipartFile.fromFile( wavPath, filename: 'canned.wav' ),
        } );
        final res = await dio.post<dynamic>( '/api/upload-and-transcribe-wav', data: form );

        expect( res.statusCode, 200 );
        final transcript = res.data.toString().trim();
        expect( transcript, isNotEmpty );
        expect(
          transcript.toLowerCase().replaceAll( RegExp( r'[^a-z0-9 ]' ), '' ),
          expected.toLowerCase().replaceAll( RegExp( r'[^a-z0-9 ]' ), '' ),
          reason: 'live Whisper round-trip must match the provenance transcript',
        );
      } on DioException catch ( e ) {
        if ( e.type == DioExceptionType.connectionError ||
             e.type == DioExceptionType.connectionTimeout ) {
          markTestSkipped( 'AC-S4.7 live probe skipped — dev :7999 not reachable '
              'from this venue (runs on the dev box; laptop suites skip).' );
          return;
        }
        rethrow;
      } finally {
        dio.close();
      }
    } );
  } );
}
