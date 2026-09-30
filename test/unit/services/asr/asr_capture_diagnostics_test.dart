/// Row 4be8fe63 — capture diagnostics. The duration maths behind the log
/// lines that tell a SILENT capture from a TRUNCATED one.
///
/// Why this is tested at all, when it only feeds debugPrint: the numbers are
/// the evidence a human reads to decide which bug they have. A wrong constant
/// here does not crash anything — it quietly argues for the wrong diagnosis,
/// which is worse than no diagnostic. Two capture bugs were already chased
/// blind on this row; the arithmetic that ends that is worth pinning.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:lupin_mobile/services/asr/asr_service.dart';

void main() {
  group( 'AsrService.wavSeconds', () {
    test( 'a header-only file is zero seconds, not a negative number', () {
      // The 44-byte canonical WAV header with no PCM after it. This is exactly
      // what a silent-microphone capture produced on the emulator, and the
      // reading must be 0.00s rather than a negative that reads as a bug in
      // the diagnostic itself.
      expect( AsrService.wavSeconds( 44 ), 0.0 );
    } );

    test( 'a file smaller than a header is still zero, never negative', () {
      expect( AsrService.wavSeconds( 0 ),  0.0 );
      expect( AsrService.wavSeconds( 12 ), 0.0 );
      expect( AsrService.wavSeconds( 43 ), 0.0 );
    } );

    test( 'one second of 44.1kHz mono 16-bit PCM reads as one second', () {
      // 44100 samples x 1 channel x 2 bytes = 88200 bytes, plus the header.
      expect( AsrService.wavSeconds( 88200 + 44 ), closeTo( 1.0, 0.0001 ) );
    } );

    test( 'the payload is measured past the header, not including it', () {
      // The header must NOT be counted as audio. Were it included, this would
      // read 1.0005s and every short capture would look longer than it is —
      // precisely the direction that hides a truncation.
      expect( AsrService.wavSeconds( 88200 ), lessThan( 1.0 ) );
    } );

    test( 'a two-second capture and a half-second capture scale linearly', () {
      expect( AsrService.wavSeconds( 176400 + 44 ), closeTo( 2.0, 0.0001 ) );
      expect( AsrService.wavSeconds(  44100 + 44 ), closeTo( 0.5, 0.0001 ) );
    } );

    test( 'the maths matches the recorder config it claims to describe', () {
      // The constant describes the WAV format (the fallback since row
      // 9b1f7701), so a change to its sample rate or channel count that
      // forgets the diagnostic fails HERE rather than silently reporting
      // wrong durations in the field.
      const cfg = AsrService.wavFallbackConfig;
      expect( cfg.encoder,     AudioEncoder.wav );
      expect( cfg.sampleRate,  44100 );
      expect( cfg.numChannels, 1 );

      final oneSecondBytes = cfg.sampleRate * cfg.numChannels * 2;
      expect( AsrService.wavSeconds( oneSecondBytes + 44 ), closeTo( 1.0, 0.0001 ) );
    } );

    test( 'a truncated tail is visible as a duration shortfall', () {
      // The shape of the live bug: a capture that should have run ~2.4s but
      // whose file only carries ~1.9s. The diagnostic has to make that half
      // second legible, because that half second is the missing words.
      final full  = AsrService.wavSeconds( ( 88200 * 2.4 ).round() + 44 );
      final short = AsrService.wavSeconds( ( 88200 * 1.9 ).round() + 44 );
      expect( full - short, closeTo( 0.5, 0.01 ) );
    } );
  } );

  // Row 7ef8f124 — input dropout: live signal that jumps to EXACT zeros.
  group( 'AsrService.findDropout', () {
    const sr = 44100;

    /// A tone-ish live signal: never zero, well above the live floor.
    Int16List live( int n, { int offset = 0 } ) =>
        Int16List.fromList( List.generate( n, ( i ) => ( ( i + offset ) % 2 == 0 ) ? 3000 : -3000 ) );

    Int16List concat( List<Int16List> parts ) {
      final out = Int16List( parts.fold( 0, ( a, p ) => a + p.length ) );
      var at = 0;
      for ( final p in parts ) { out.setAll( at, p ); at += p.length; }
      return out;
    }

    test( 'live then exact zeros to the end is a dropout, at the right time', () {
      // The emulator shape: 1.756 s of voice, then zeros to the end.
      final pcm = concat( [ live( 77440 ), Int16List( 108416 ) ] );
      final d   = AsrService.findDropout( pcm, sr );
      expect( d, isNotNull );
      expect( d!.startSeconds,  closeTo( 77440 / sr, 1e-6 ) );
      expect( d.lengthSeconds,  closeTo( 108416 / sr, 1e-6 ) );
    } );

    test( 'an all-zero capture is NOT a dropout — the silent-mic line covers it', () {
      expect( AsrService.findDropout( Int16List( sr * 3 ), sr ), isNull );
    } );

    test( 'quiet speech with small non-zero values is not a dropout', () {
      final quiet = Int16List.fromList( List.generate( sr * 2, ( i ) => ( i % 3 ) - 1 == 0 ? 1 : -2 ) );
      expect( AsrService.findDropout( concat( [ live( 4410 ), quiet ] ), sr ), isNull );
    } );

    test( 'zeros at the end shorter than 100 ms are not a dropout', () {
      final pcm = concat( [ live( sr ), Int16List( ( sr * 0.09 ).round() ) ] );
      expect( AsrService.findDropout( pcm, sr ), isNull );
    } );

    test( 'zeros at the end of at least 100 ms are a dropout', () {
      final pcm = concat( [ live( sr ), Int16List( ( sr * 0.11 ).round() ) ] );
      expect( AsrService.findDropout( pcm, sr ), isNotNull );
    } );

    test( 'a mid-capture gap must reach 250 ms before it counts', () {
      final short = concat( [ live( sr ), Int16List( ( sr * 0.20 ).round() ), live( sr ) ] );
      final long  = concat( [ live( sr ), Int16List( ( sr * 0.30 ).round() ), live( sr ) ] );
      expect( AsrService.findDropout( short, sr ), isNull );
      expect( AsrService.findDropout( long,  sr ), isNotNull );
    } );

    test( 'leading zeros before the first live sample are ignored', () {
      // A capture that starts silent is not an input that stopped.
      final pcm = concat( [ Int16List( sr ), live( sr ) ] );
      expect( AsrService.findDropout( pcm, sr ), isNull );
    } );
  } );

  group( 'AsrService.pcmFromWav', () {
    Uint8List wav( List<int> samples, { List<int> extraChunk = const [] } ) {
      final data = ByteData( samples.length * 2 );
      for ( var i = 0; i < samples.length; i++ ) { data.setInt16( i * 2, samples[ i ], Endian.little ); }
      final b = BytesBuilder();
      void u32( int v ) { final x = ByteData( 4 )..setUint32( 0, v, Endian.little ); b.add( x.buffer.asUint8List() ); }
      b.add( 'RIFF'.codeUnits ); u32( 0 ); b.add( 'WAVE'.codeUnits );
      b.add( 'fmt '.codeUnits ); u32( 16 ); b.add( List.filled( 16, 0 ) );
      if ( extraChunk.isNotEmpty ) { b.add( 'LIST'.codeUnits ); u32( extraChunk.length ); b.add( extraChunk ); }
      b.add( 'data'.codeUnits ); u32( samples.length * 2 ); b.add( data.buffer.asUint8List() );
      return b.toBytes();
    }

    test( 'reads the samples of a canonical 44-byte-header WAV', () {
      expect( AsrService.pcmFromWav( wav( [ 1, -2, 32767, -32768, 0 ] ) ), [ 1, -2, 32767, -32768, 0 ] );
    } );

    test( 'finds the data chunk after an extra chunk instead of assuming 44 bytes', () {
      expect( AsrService.pcmFromWav( wav( [ 7, -7 ], extraChunk: [ 1, 2, 3, 4, 5, 6 ] ) ), [ 7, -7 ] );
    } );

    test( 'a file with no data chunk yields no samples', () {
      final b = BytesBuilder()..add( 'RIFF'.codeUnits )..add( [ 0, 0, 0, 0 ] )..add( 'WAVE'.codeUnits );
      expect( AsrService.pcmFromWav( b.toBytes() ), isEmpty );
    } );
  } );
}
