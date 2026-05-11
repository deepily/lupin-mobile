import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/claude_code_models.dart';
import '../domain/claude_code_bloc.dart';
import '../domain/claude_code_event.dart';
import '../domain/claude_code_state.dart';

const _kRetiredBannerYellow  = Color( 0xFFFFF3CD );
const _kRetiredBannerAccent  = Color( 0xFFFF9800 );

Widget _retiredBanner( String copy ) {
  return Container(
    decoration: const BoxDecoration(
      color  : _kRetiredBannerYellow,
      border : Border( left: BorderSide( color: _kRetiredBannerAccent, width: 4 ) ),
    ),
    padding: const EdgeInsets.all( 12 ),
    child: Row(
      children: [
        const Icon( Icons.warning_amber_rounded, color: _kRetiredBannerAccent ),
        const SizedBox( width: 12 ),
        Expanded(
          child: Text(
            copy,
            style: const TextStyle( fontStyle: FontStyle.italic ),
          ),
        ),
      ],
    ),
  );
}

class DispatchSheet extends StatefulWidget {
  const DispatchSheet( { super.key } );

  @override
  State<DispatchSheet> createState() => _DispatchSheetState();
}

class _DispatchSheetState extends State<DispatchSheet> {
  final _promptCtrl  = TextEditingController();
  final _projectCtrl = TextEditingController();
  bool  _loading     = false;

  @override
  void dispose() {
    _promptCtrl.dispose();
    _projectCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final prompt  = _promptCtrl.text.trim();
    if ( prompt.isEmpty ) return;
    final project = _projectCtrl.text.trim();

    final request = project.isEmpty
        ? ClaudeCodeSubmitRequest( prompt: prompt )
        : ClaudeCodeSubmitRequest( prompt: prompt, project: project );

    context.read<ClaudeCodeBloc>().add( ClaudeCodeSubmit( request ) );
  }

  @override
  Widget build( BuildContext context ) {
    final bottom = MediaQuery.of( context ).viewInsets.bottom;
    return BlocListener<ClaudeCodeBloc, ClaudeCodeState>(
      listener: ( context, state ) {
        if ( state is ClaudeCodeSubmitted ) {
          Navigator.of( context ).pop();
        }
        if ( state is ClaudeCodeSubmitting ) {
          setState( () => _loading = true );
        }
        if ( state is ClaudeCodeError ) {
          setState( () => _loading = false );
        }
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB( 16, 20, 16, bottom + 20 ),
        child: Column(
          mainAxisSize       : MainAxisSize.min,
          crossAxisAlignment : CrossAxisAlignment.stretch,
          children: [
            _retiredBanner(
              "INTERACTIVE controls retired 2026-05-05. Returns when ClaudeCodeJob gains "
              "inject / interrupt / end_session. See parent retirement plan.",
            ),
            const SizedBox( height: 16 ),
            Text( "New Claude Code Job (BOUNDED)", style: Theme.of( context ).textTheme.titleLarge ),
            const SizedBox( height: 16 ),
            TextField(
              controller : _promptCtrl,
              decoration : const InputDecoration(
                labelText : "Prompt",
                border    : OutlineInputBorder(),
              ),
              minLines  : 3,
              maxLines  : 6,
              autofocus : true,
            ),
            const SizedBox( height: 12 ),
            TextField(
              controller : _projectCtrl,
              decoration : const InputDecoration(
                labelText : "Project (optional, default: lupin)",
                border    : OutlineInputBorder(),
              ),
            ),
            const SizedBox( height: 16 ),
            FilledButton(
              onPressed : _loading ? null : _submit,
              child     : _loading
                  ? const SizedBox( width: 20, height: 20, child: CircularProgressIndicator( strokeWidth: 2 ) )
                  : const Text( "Submit" ),
            ),
          ],
        ),
      ),
    );
  }
}
