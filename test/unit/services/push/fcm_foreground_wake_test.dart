// Row b69dbf0b: a foreground push with the socket down reconnects instead of being ignored as "WS is live".

import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/push/fcm_bootstrap.dart';

void main() {
  test( "a foreground data message asks for a reconnect", () async {
    var asked = 0;
    await onForegroundDataMessage( { "type": "ws_wake" }, reconnect: () async => asked++ );
    expect( asked, 1 );
  } );
}
