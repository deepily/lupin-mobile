import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/agentic/data/bug_fix_expediter_models.dart';
import 'package:lupin_mobile/features/agentic/data/chained_models.dart';
import 'package:lupin_mobile/features/agentic/data/deep_research_models.dart';
import 'package:lupin_mobile/features/agentic/data/podcast_models.dart';
import 'package:lupin_mobile/features/agentic/data/presentation_models.dart';
import 'package:lupin_mobile/features/agentic/data/swe_team_models.dart';
import 'package:lupin_mobile/features/agentic/data/test_suite_models.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';

/// v2 wave 2 prep: every submit-shaped door can express itself as `/api/v2/submit`
/// `args` with the contract's key names, and NEVER leaks a queue directive
/// (`scheduled_at` / `monopolize` / `websocket_id`) into `args`.
void main() {
  const directives = [ 'scheduled_at', 'monopolize', 'websocket_id', 'parent_id_hash' ];

  void noDirectives( Map<String, dynamic> args ) {
    for ( final k in directives ) {
      expect( args.containsKey( k ), isFalse, reason: '$k is a queue directive — top-level on SubmitRequest, never in args' );
    }
  }

  test( 'deep research → query + contract keys, directives excluded', () {
    const r = DeepResearchRequest( query: 'q', budget: 1.5, audience: 'expert', scheduledAt: '2026-08-22T10:00:00-04:00', monopolize: true, websocketId: 'ws' );
    expect( DeepResearchRequest.submitCommand, 'agent router go to deep research' );
    final a = r.toSubmitArgs();
    expect( a, { 'query': 'q', 'budget': 1.5, 'audience': 'expert' } );
    noDirectives( a );
  } );

  test( 'podcast generator → research_source renamed to research, target_languages to languages', () {
    const r = PodcastGeneratorRequest( researchSource: 'the KISS explainer', targetLanguages: [ 'en', 'es-MX' ], dryRun: true, monopolize: true );
    final a = r.toSubmitArgs();
    expect( a[ 'research' ], 'the KISS explainer' );
    expect( a[ 'languages' ], [ 'en', 'es-MX' ] );
    expect( a[ 'dry_run' ], isTrue );
    expect( a.containsKey( 'research_source' ), isFalse );
    expect( a.containsKey( 'target_languages' ), isFalse );
    noDirectives( a );
  } );

  test( 'presentation generator → source_path renamed to source', () {
    const r = PresentationGeneratorRequest( sourcePath: '/io/x.md', theme: 'dark', renderOnly: true, scheduledAt: 'x' );
    final a = r.toSubmitArgs();
    expect( a, { 'source': '/io/x.md', 'theme': 'dark', 'render_only': true } );
    noDirectives( a );
  } );

  test( 'swe team, BFE, test suite → 1:1 keys, directives excluded', () {
    expect( const SweTeamRequest( task: 't', budget: 2, trustMode: 'shadow', websocketId: 'ws', monopolize: true ).toSubmitArgs(),
            { 'task': 't', 'budget': 2, 'trust_mode': 'shadow' } );
    expect( const BugFixExpediterRequest( deadJobId: 'dj', extraContext: 'c', websocketId: 'ws', scheduledAt: 's' ).toSubmitArgs(),
            { 'dead_job_id': 'dj', 'extra_context': 'c' } );
    expect( const TestSuiteRequest( testTypes: 'integration', pytestArgs: '-k lane2', autoFixOnFailure: false, envVars: { 'LUPIN_TEST_X': '1' }, scheduledAt: 's' ).toSubmitArgs(),
            { 'test_types': 'integration', 'pytest_args': '-k lane2', 'auto_fix_on_failure': false, 'env_vars': { 'LUPIN_TEST_X': '1' } } );
    expect( SweTeamRequest.submitCommand, 'agent router go to swe team' );
    expect( BugFixExpediterRequest.submitCommand, 'agent router go to bug fix expediter' );
    expect( TestSuiteRequest.submitCommand, 'agent router go to test suite' );
  } );

  test( 'chained doors → query + contract keys; languages renamed', () {
    expect( const ResearchToPodcastRequest( query: 'q', targetLanguages: [ 'en' ], maxSegments: 3 ).toSubmitArgs(),
            { 'query': 'q', 'languages': [ 'en' ], 'max_segments': 3 } );
    expect( const ResearchToPresentationRequest( query: 'q', leadModel: 'm', audienceContext: 'ac' ).toSubmitArgs(),
            { 'query': 'q', 'audience_context': 'ac', 'lead_model': 'm' } );
    expect( ResearchToPodcastRequest.submitCommand, 'agent router go to research to podcast' );
    expect( ResearchToPresentationRequest.submitCommand, 'agent router go to research to presentation' );
  } );

  test( 'push-agentic → SubmitRequest 1:1, directives top-level and only when set', () {
    const p = PushAgenticRequest( routingCommand: 'agent router go to deep research', websocketId: 'ws', args: { 'query': 'q' }, question: 'hi', scheduledAt: 's', monopolize: true );
    final j = p.toSubmitRequest().toJson();
    expect( j[ 'command' ], 'agent router go to deep research' );
    expect( j[ 'args' ], { 'query': 'q' } );
    expect( j[ 'question' ], 'hi' );
    expect( j[ 'websocket_id' ], 'ws' );
    expect( j[ 'scheduled_at' ], 's' );
    expect( j[ 'monopolize' ], isTrue );
    final plain = const PushAgenticRequest( routingCommand: 'c', websocketId: 'ws' ).toSubmitRequest().toJson();
    expect( plain.containsKey( 'scheduled_at' ), isFalse );
    expect( plain.containsKey( 'monopolize' ), isFalse, reason: 'false = unset → omitted' );
  } );
}
