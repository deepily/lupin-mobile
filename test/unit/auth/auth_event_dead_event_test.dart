/// Fold-later from the 597c5dc review (row 8d9b2a0c): `AuthServerContextChanged`
/// was declared and handled but never dispatched — the real switch goes through
/// `AuthServerContextSwitchRequested`, which clears the OLD server's session
/// before switching. A second, half-done path onto the same state is a trap for
/// the next reader, so it was deleted.
///
/// A deletion needs a guard, or it quietly comes back. This scans the shipped
/// source for the name, on COMMENT-STRIPPED text so a future explanation of why
/// it went away does not read as a declaration (same rule as
/// `test/unit/core/event_constants_test.dart`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strip `///`, `//` and `/* */` so the scan measures CODE, never prose.
String codeOnly( String source ) {
  final noBlocks = source.replaceAll( RegExp( r'/\*.*?\*/', dotAll: true ), '' );
  return noBlocks.split( '\n' ).map( ( line ) {
    final i = line.indexOf( '//' );
    return i < 0 ? line : line.substring( 0, i );
  } ).join( '\n' );
}

void main() {
  final dartFiles = Directory( 'lib' )
      .listSync( recursive: true )
      .whereType<File>()
      .where( ( f ) => f.path.endsWith( '.dart' ) )
      .toList();

  test( 'lib/ declares some Dart files to scan', () {
    expect( dartFiles.length, greaterThan( 50 ), reason: 'an empty scan proves nothing' );
  } );

  test( 'AuthServerContextChanged is gone from the shipped source', () {
    final hits = dartFiles
        .where( ( f ) => codeOnly( f.readAsStringSync() ).contains( 'AuthServerContextChanged' ) )
        .map( ( f ) => f.path )
        .toList();
    expect(
      hits,
      isEmpty,
      reason: 'the server switch goes through AuthServerContextSwitchRequested, '
              'which clears the OLD context first; a second path onto AuthUnauthenticated '
              'skips that clear',
    );
  } );

  test( 'the scan can find a name that IS there — AuthServerContextSwitchRequested', () {
    final hits = dartFiles
        .where( ( f ) => codeOnly( f.readAsStringSync() ).contains( 'AuthServerContextSwitchRequested' ) )
        .map( ( f ) => f.path )
        .toList();
    expect( hits, isNotEmpty, reason: 'control: the surviving event is still declared and dispatched' );
  } );
}
