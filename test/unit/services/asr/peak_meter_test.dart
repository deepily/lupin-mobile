/// The peak meter keeps the loudest reading and calls a quiet capture silent.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/asr/peak_meter.dart';

void main() {
  PeakMeter meterOver( List<double?> levels ) {
    var i = 0;
    return PeakMeter( read: () async => levels[ i++ % levels.length ] );
  }

  test( 'keeps the loudest of the readings', () => fakeAsync( ( clock ) {
    final meter = meterOver( [ -40, -12.5, -30 ] )..start();
    clock.elapse( PeakMeter.defaultInterval * 3 );
    meter.stop();

    expect( meter.peakDb, -12.5 );
    expect( meter.samples, 3 );
    expect( meter.describe(), 'peakDb=-12.5 samples=3' );
  } ) );

  test( 'a capture quieter than the floor is marked SILENT', () => fakeAsync( ( clock ) {
    final meter = meterOver( [ -120, -90 ] )..start();
    clock.elapse( PeakMeter.defaultInterval * 2 );

    expect( meter.describe(), 'peakDb=-90.0 samples=2 SILENT' );
  } ) );

  test( 'no readings says none, and is not called silent', () => fakeAsync( ( clock ) {
    final meter = meterOver( [ null ] )..start();
    clock.elapse( PeakMeter.defaultInterval * 2 );

    expect( meter.describe(), 'peakDb=none samples=0' );
  } ) );

  test( 'a reading that throws is skipped', () => fakeAsync( ( clock ) {
    var calls = 0;
    final meter = PeakMeter( read: () async {
      if ( calls++ == 0 ) throw StateError( 'recorder not ready' );
      return -20;
    } )..start();
    clock.elapse( PeakMeter.defaultInterval * 2 );

    expect( meter.peakDb, -20 );
    expect( meter.samples, 1 );
  } ) );

  test( 'start forgets the earlier run, and stop ends the readings', () => fakeAsync( ( clock ) {
    final meter = meterOver( [ -10 ] )..start();
    clock.elapse( PeakMeter.defaultInterval );
    meter.stop();
    clock.elapse( PeakMeter.defaultInterval * 5 );
    expect( meter.samples, 1 );

    meter.start();
    expect( meter.peakDb, isNull );
    expect( meter.samples, 0 );
    meter.stop();
  } ) );
}
