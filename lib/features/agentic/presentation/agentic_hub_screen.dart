import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/agentic_submission_bloc.dart';
import 'bug_fix_expediter_form.dart';
import 'deep_research_form.dart';
import 'podcast_generator_form.dart';
import 'presentation_generator_form.dart';
import 'research_to_podcast_form.dart';
import 'research_to_presentation_form.dart';
import 'swe_team_form.dart';
import 'test_fix_expediter_form.dart';
import 'test_suite_form.dart';

class AgenticHubScreen extends StatelessWidget {
  const AgenticHubScreen( { super.key } );

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( 'Agentic Jobs' ) ),
      body: ListView( padding: const EdgeInsets.all( 16 ), children: [
        _HubCard(
          icon    : Icons.search_outlined,
          title   : 'Deep Research',
          subtitle: 'Multi-source research synthesis → markdown report',
          onTap   : () => _push( context, const DeepResearchForm() ),
        ),
        _HubCard(
          icon    : Icons.podcasts_outlined,
          title   : 'Podcast Generator',
          subtitle: 'Convert a research doc into a multi-voice podcast',
          onTap   : () => _push( context, const PodcastGeneratorForm() ),
        ),
        _HubCard(
          icon    : Icons.slideshow_outlined,
          title   : 'Presentation Generator',
          subtitle: 'Turn a source doc into a slide deck',
          onTap   : () => _push( context, const PresentationGeneratorForm() ),
        ),
        _HubCard(
          icon    : Icons.account_tree_outlined,
          title   : 'Research → Podcast',
          subtitle: 'Chained: run deep research then generate podcast',
          onTap   : () => _push( context, const ResearchToPodcastForm() ),
        ),
        _HubCard(
          icon    : Icons.auto_awesome_mosaic_outlined,
          title   : 'Research → Presentation',
          subtitle: 'Chained: run deep research then generate slides',
          onTap   : () => _push( context, const ResearchToPresentationForm() ),
        ),
        _HubCard(
          icon    : Icons.code_outlined,
          title   : 'SWE Team',
          subtitle: 'Multi-agent software engineering workflow',
          onTap   : () => _push( context, const SweTeamForm() ),
        ),
        _HubCard(
          icon    : Icons.bug_report_outlined,
          title   : 'Bug Fix Expediter',
          subtitle: 'Re-run a dead job through the bug-fix pipeline',
          onTap   : () => _push( context, const BugFixExpediterForm() ),
        ),
        _HubCard(
          icon    : Icons.science_outlined,
          title   : 'Test Suite',
          subtitle: 'Schedule and run automated test suites',
          onTap   : () => _push( context, const TestSuiteForm() ),
        ),
        _HubCard(
          icon    : Icons.restart_alt_outlined,
          title   : 'Test Fix Expediter',
          subtitle: 'Resume a test-fix session from a prior job or plan',
          onTap   : () => _push( context, const TestFixExpediterForm() ),
        ),
      ] ),
    );
  }

  void _push( BuildContext context, Widget screen ) {
    Navigator.of( context ).push( MaterialPageRoute(
      builder: ( _ ) => BlocProvider.value(
        value: context.read<AgenticSubmissionBloc>(),
        child: screen,
      ),
    ) );
  }
}

class _HubCard extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final VoidCallback onTap;

  const _HubCard( {
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  } );

  @override
  Widget build( BuildContext context ) {
    return Card(
      margin: const EdgeInsets.only( bottom: 12 ),
      child: ListTile(
        leading  : Icon( icon, size: 32 ),
        title    : Text( title ),
        subtitle : Text( subtitle ),
        trailing : const Icon( Icons.chevron_right ),
        onTap    : onTap,
      ),
    );
  }
}
