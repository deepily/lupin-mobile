// Row c41c090a: the three seat-worktree scripts share one library, a byte-identical copy of lupin's
// worktree-link-lib.sh. They must source it and must not carry their own copy of what it defines.
// The byte-compare against lupin's file is lupin's test (test_worktree_link_lib.py); this test never
// edits or compares the library's contents.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _libPath = "src/scripts/lib/worktree-link-lib.sh";

const List<String> _scripts = [
  "src/scripts/link-worktree-venv.sh",
  "src/scripts/link-worktree-artifacts.sh",
  "src/scripts/provision-seat-worktree.sh",
];

/// [shell] with whole-line comments removed.
String _code( String shell ) =>
    shell.split( "\n" ).where( ( line ) => !line.trimLeft().startsWith( "#" ) ).join( "\n" );

List<String> _definedFunctions( String library ) =>
    RegExp( r"^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{", multiLine: true )
        .allMatches( _code( library ) )
        .map( ( m ) => m.group( 1 )! )
        .toList();

void main() {
  final library   = File( _libPath ).readAsStringSync();
  final functions = _definedFunctions( library );

  test( "the library exists and defines functions", () {
    expect( functions, isNotEmpty );
  } );

  for ( final script in _scripts ) {
    group( script, () {
      final code = _code( File( script ).readAsStringSync() );

      test( "sources the shared library", () {
        expect( code, contains( "lib/worktree-link-lib.sh" ) );
        expect( RegExp( r'^\s*(source|\.)\s+.*lib/worktree-link-lib\.sh', multiLine: true ).hasMatch( code ), isTrue );
      } );

      test( "defines none of the library's functions itself", () {
        for ( final name in functions ) {
          expect( RegExp( "^\\s*(function\\s+)?$name\\s*\\(\\)", multiLine: true ).hasMatch( code ), isFalse, reason: name );
        }
      } );

      test( "calls the library instead of repeating its mechanism", () {
        expect( code, isNot( contains( "worktree list --porcelain" ) ), reason: "wt_resolve_main owns this" );
        expect( RegExp( r'=\s*"\$\{line#worktree \}"' ).hasMatch( code ), isFalse, reason: "assigning the main path from the list is wt_resolve_main's job" );
        expect( code, contains( "wt_resolve_main" ) );
      } );
    } );
  }
}
