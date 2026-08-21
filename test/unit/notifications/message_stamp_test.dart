import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/features/notifications/presentation/message_stamp.dart';

void main() {
  group( 'MessageStamp.format', () {
    test( 'same local day ⇒ HH:mm:ss, zero-padded', () {
      final now = DateTime( 2026, 8, 21, 15, 4, 9 );
      expect( MessageStamp.format( DateTime( 2026, 8, 21, 9, 7, 3 ), now: now ), '09:07:03' );
      expect( MessageStamp.format( DateTime( 2026, 8, 21, 23, 59, 59 ), now: now ), '23:59:59' );
    } );
    test( 'other day ⇒ MM-dd prefix', () {
      final now = DateTime( 2026, 8, 21, 15 );
      expect( MessageStamp.format( DateTime( 2026, 8, 20, 9, 7, 3 ), now: now ), '08-20 09:07:03' );
      expect( MessageStamp.format( DateTime( 2025, 12, 31, 0, 0, 0 ), now: now ), '12-31 00:00:00' );
    } );
  } );
}
