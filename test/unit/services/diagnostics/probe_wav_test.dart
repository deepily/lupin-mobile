import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/diagnostics/probe_wav.dart';

String _ascii( Uint8List b, int offset, int len ) =>
    String.fromCharCodes( b.sublist( offset, offset + len ) );

void main() {
  group( 'ProbeWav', () {
    test( 'generateInBackground returns the same bytes as generate', () async {
      final background = await ProbeWav.generateInBackground( sampleRate: 16000, seconds: 2 );
      expect( background, ProbeWav.generate( sampleRate: 16000, seconds: 2 ) );
    } );

    test( 'generateInBackground surfaces argument errors through the future', () async {
      await expectLater( ProbeWav.generateInBackground( sampleRate: 0 ), throwsArgumentError );
    } );

    test( '30 s at 44.1 kHz is 2,646,044 bytes (the ~2.6 MB being measured)', () {
      final wav = ProbeWav.generate( sampleRate: 44100 );
      expect( wav.length, 44 + 44100 * 30 * 2 );
      expect( wav.length, 2646044 );
      expect( ProbeWav.byteLength( sampleRate: 44100 ), wav.length );
    } );

    test( '30 s at 16 kHz is 960,044 bytes', () {
      final wav = ProbeWav.generate( sampleRate: 16000 );
      expect( wav.length, 960044 );
    } );

    for ( final rate in [ 44100, 16000 ] ) {
      test( 'header fields are a valid mono 16-bit PCM RIFF/WAVE at $rate Hz', () {
        final wav = ProbeWav.generate( sampleRate: rate );
        final v   = ByteData.view( wav.buffer );
        expect( _ascii( wav, 0, 4 ),  'RIFF' );
        expect( v.getUint32( 4,  Endian.little ), wav.length - 8 );
        expect( _ascii( wav, 8, 4 ),  'WAVE' );
        expect( _ascii( wav, 12, 4 ), 'fmt ' );
        expect( v.getUint32( 16, Endian.little ), 16 );
        expect( v.getUint16( 20, Endian.little ), 1 );          // PCM
        expect( v.getUint16( 22, Endian.little ), 1 );          // mono
        expect( v.getUint32( 24, Endian.little ), rate );
        expect( v.getUint32( 28, Endian.little ), rate * 2 );   // byte rate
        expect( v.getUint16( 32, Endian.little ), 2 );          // block align
        expect( v.getUint16( 34, Endian.little ), 16 );
        expect( _ascii( wav, 36, 4 ), 'data' );
        expect( v.getUint32( 40, Endian.little ), rate * 30 * 2 );
      } );
    }

    test( 'bytes are deterministic across calls', () {
      final a = ProbeWav.generate( sampleRate: 16000 );
      final b = ProbeWav.generate( sampleRate: 16000 );
      expect( a, equals( b ) );
    } );

    test( 'audio is a moderate-amplitude signal, not silence', () {
      final wav  = ProbeWav.generate( sampleRate: 16000, seconds: 1 );
      final v    = ByteData.view( wav.buffer );
      var   peak = 0;
      for ( var i = 44; i < wav.length; i += 2 ) {
        final s = v.getInt16( i, Endian.little ).abs();
        if ( s > peak ) peak = s;
      }
      expect( peak, greaterThan( 9000 ) );
      expect( peak, lessThanOrEqualTo( ( 0.3 * 32767 ).round() ) );
    } );

    test( 'rejects a non-positive sample rate', () {
      expect( () => ProbeWav.generate( sampleRate: 0 ), throwsArgumentError );
    } );
  } );
}
