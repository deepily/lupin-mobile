import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The census guard (row c67f9781, plan §5).
///
/// Rick, 2026-09-28: the append mic is the default on every text box. A NEW
/// text box fails this test until someone classifies it, which is what makes
/// "default everywhere" stick after the migration.
///
/// Per file:
///   no        plain TextField on purpose: a transcription error there changes
///             meaning silently (path, ID, number, credential, exact-match filter)
///   exception plain TextField on purpose for another reason (Broadcast keeps
///             its bloc-owned session; `dictation_text_field.dart` is the widget)
///   yes       DictationTextField( already migrated
///   pending   a mic-yes box still a plain TextField, waiting for its migration
///             commit. Every commit lowers this; the last one deletes the column.
const Map<String, Map<String, int>> _census = {
  'features/agentic/presentation/bug_fix_expediter_form.dart'       : { 'no': 1, 'pending': 1 },
  'features/agentic/presentation/deep_research_form.dart'           : { 'no': 1, 'pending': 1 },
  'features/agentic/presentation/podcast_generator_form.dart'       : { 'pending': 1 },   // S1
  'features/agentic/presentation/presentation_generator_form.dart'  : { 'no': 2 },
  'features/agentic/presentation/research_to_podcast_form.dart'     : { 'no': 1, 'pending': 1 },
  'features/agentic/presentation/research_to_presentation_form.dart': { 'no': 2, 'pending': 1 },
  'features/agentic/presentation/swe_team_form.dart'                : { 'no': 1, 'pending': 1 },
  'features/agentic/presentation/test_fix_expediter_form.dart'      : { 'pending': 1 },   // S2
  'features/auth/presentation/login_screen.dart'                    : { 'no': 2 },
  'features/broadcast/presentation/broadcast_pane.dart'             : { 'exception': 1 },
  'features/claude_code/presentation/dispatch_sheet.dart'           : { 'no': 1, 'pending': 1 },
  'features/fleet/presentation/verb_reason_sheet.dart'              : { 'pending': 1 },
  'features/focus_mode/presentation/voice_reply_field.dart'         : { 'pending': 1 },
  'features/holding_area/presentation/filer_group_header.dart'      : { 'pending': 1 },
  'features/queue/presentation/job_detail_screen.dart'              : { 'pending': 1 },
  'features/queue/presentation/submit_job_sheet.dart'               : { 'pending': 1 },
  'features/settings/presentation/notification_filter_settings_screen.dart': { 'no': 2 },
  'features/task_list/presentation/new_ticket_sheet.dart'           : { 'no': 3, 'yes': 2 },
  'features/task_list/presentation/task_list_header.dart'           : { 'no': 1 },
  'shared/widgets/dictation_text_field.dart'                        : { 'exception': 1 },
  'shared/widgets/prompt_bodies.dart'                               : { 'yes': 1, 'pending': 3 },
  'ui/debug/websocket_debug_dashboard.dart'                         : { 'no': 1 },
};

final _plain     = RegExp( r'(?<![A-Za-z])(?:TextField|TextFormField)\(' );
final _dictation = RegExp( r'DictationTextField\(' );

int _count( String source, RegExp re ) => source
    .split( '\n' )
    .where( ( l ) => !l.trimLeft().startsWith( '//' ) && !l.trimLeft().startsWith( '*' ) )
    .map( ( l ) => re.allMatches( l ).length )
    .fold( 0, ( a, b ) => a + b );

void main() {
  test( 'every text box in lib/ is classified', () {
    final plain     = <String, int>{};
    final dictation = <String, int>{};
    final root      = Directory( 'lib' );
    for ( final f in root.listSync( recursive: true ).whereType<File>() ) {
      if ( !f.path.endsWith( '.dart' ) ) continue;
      final rel = f.path.substring( 'lib/'.length );
      final src = f.readAsStringSync();
      final p   = _count( src, _plain );
      final d   = rel == 'shared/widgets/dictation_text_field.dart' ? 0 : _count( src, _dictation );
      if ( p > 0 ) plain[ rel ] = p;
      if ( d > 0 ) dictation[ rel ] = d;
    }

    final problems = <String>[];
    final files    = { ...plain.keys, ...dictation.keys, ..._census.keys };
    for ( final rel in files ) {
      final c = _census[ rel ];
      if ( c == null ) {
        problems.add( '$rel: unclassified text box (add it to the census as yes / no / exception)' );
        continue;
      }
      final wantPlain = ( c[ 'no' ] ?? 0 ) + ( c[ 'exception' ] ?? 0 ) + ( c[ 'pending' ] ?? 0 );
      final wantDict  = c[ 'yes' ] ?? 0;
      if ( ( plain[ rel ] ?? 0 ) != wantPlain ) {
        problems.add( '$rel: ${plain[ rel ] ?? 0} plain TextField( found, census says $wantPlain' );
      }
      if ( ( dictation[ rel ] ?? 0 ) != wantDict ) {
        problems.add( '$rel: ${dictation[ rel ] ?? 0} DictationTextField( found, census says $wantDict' );
      }
    }
    expect( problems, isEmpty, reason: problems.join( '\n' ) );
  } );
}
