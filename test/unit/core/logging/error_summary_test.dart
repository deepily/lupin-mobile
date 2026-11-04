// describeFailure names the failure without quoting the input that caused it.

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/logging/error_summary.dart';

void main() {
  test( "a FormatException is described by type and offset, never by its source text", () {
    const secret = "alice@example.com private note";
    const error  = FormatException( "bad input", secret, 6 );

    final out = describeFailure( error );

    expect( out, "FormatException at offset 6" );
    expect( out, isNot( contains( "alice" ) ) );
    expect( error.toString(), contains( "alice" ), reason: "the raw message does quote it, which is why it is not logged" );
  } );

  test( "a FormatException without an offset is described by type alone", () {
    expect( describeFailure( const FormatException( "bad" ) ), "FormatException" );
  } );

  test( "any other error is described by its runtime type", () {
    expect( describeFailure( StateError( "alice@example.com" ) ), "StateError" );
  } );
}
