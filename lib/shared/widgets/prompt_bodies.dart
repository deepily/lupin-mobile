/// Shared interactive-prompt bodies (F-S3-1 extract-to-shared, 2026-06-12).
///
/// Extracted VERBATIM from the library-private bodies in
/// `interactive_prompt_sheet.dart` (`_YesNoBody`, `_MultipleChoiceBody`,
/// `_OpenEndedBody`) so TWO consumers compose the SAME widgets:
///   - the legacy `InteractivePromptSheet` (wires `onRespond` to its
///     existing `NotificationsRespond` dispatch — behavior-neutral,
///     AC-S3.9), and
///   - the focus-mode inline prompt bubbles (wire `onRespond` to
///     `FocusRespondRequested`, F-S3-2).
///
/// The batch body (`_OpenEndedBatchBody`) is deliberately NOT extracted
/// (F-S3-S2-2(d)): it submits `Map<String, String>` and stays in the legacy
/// sheet; focus bubbles render a fallback affordance for batch asks.
///
/// Callback typing: yes/no and open-ended are String end-to-end.
/// Multiple-choice keeps the legacy `dynamic` callback because its
/// MULTI-SELECT variant submits a `List` (legacy wire shape preserved —
/// AC-S3.9 behavior-neutrality governs); the focus path composes this body
/// ONLY for single-select asks (where the value is always a String) and
/// routes multi-select asks to the same fallback affordance as batch —
/// implementer call on the record, S3 §8.
library;

import 'package:flutter/material.dart';

import '../../core/testing/test_keys.dart';

// --- yes/no -----------------------------------------------------------------

class YesNoPromptBody extends StatefulWidget {
  final void Function( String ) onRespond;
  const YesNoPromptBody( { super.key, required this.onRespond } );

  @override
  State<YesNoPromptBody> createState() => _YesNoPromptBodyState();
}

class _YesNoPromptBodyState extends State<YesNoPromptBody> {
  final _comment = TextEditingController();

  String _withComment( String answer ) {
    final c = _comment.text.trim();
    return c.isEmpty ? answer : "$answer [comment: $c]";
  }

  @override
  Widget build( BuildContext context ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key       : const Key( TestKeys.promptCommentField ),
          controller: _comment,
          decoration: const InputDecoration(
            labelText: "Optional comment",
            border   : OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox( height: 16 ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key( TestKeys.promptNoButton ),
                onPressed: () => widget.onRespond( _withComment( "no" ) ),
                child: const Text( "No" ),
              ),
            ),
            const SizedBox( width: 8 ),
            Expanded(
              child: Tooltip(
                message: "Neither — the question itself needs re-framing",
                child: TextButton(
                  key: const Key( TestKeys.promptNeitherButton ),
                  onPressed: () => widget.onRespond( _withComment( "neither" ) ),
                  child: const Text( "⊘ Neither" ),
                ),
              ),
            ),
            const SizedBox( width: 8 ),
            Expanded(
              child: FilledButton(
                key: const Key( TestKeys.promptYesButton ),
                onPressed: () => widget.onRespond( _withComment( "yes" ) ),
                child: const Text( "Yes" ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --- multiple choice --------------------------------------------------------

class MultipleChoicePromptBody extends StatefulWidget {
  final List<dynamic>            options;
  final bool                     multi;

  /// `dynamic` preserved from the legacy body: single-select submits a
  /// String; MULTI-select submits a `List` (legacy wire shape — see the
  /// library docstring). Focus-path consumers compose this only with
  /// `multi: false`.
  final void Function( dynamic ) onRespond;

  const MultipleChoicePromptBody( {
    super.key,
    required this.options,
    required this.multi,
    required this.onRespond,
  } );

  @override
  State<MultipleChoicePromptBody> createState() => _MultipleChoicePromptBodyState();
}

class _MultipleChoicePromptBodyState extends State<MultipleChoicePromptBody> {
  String?      _single;
  final Set<String> _multi = {};
  final _other = TextEditingController();

  String _label( dynamic opt ) {
    if ( opt is Map ) return ( opt[ "label" ] ?? "" ).toString();
    return opt.toString();
  }

  @override
  Widget build( BuildContext context ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...widget.options.map( ( opt ) {
          final label = _label( opt );
          if ( widget.multi ) {
            return CheckboxListTile(
              dense: true,
              title: Text( label ),
              value: _multi.contains( label ),
              onChanged: ( v ) => setState( () {
                if ( v == true ) {
                  _multi.add( label );
                } else {
                  _multi.remove( label );
                }
              } ),
            );
          }
          return RadioListTile<String>(
            dense: true,
            title: Text( label ),
            value: label,
            groupValue: _single,
            onChanged: ( v ) => setState( () => _single = v ),
          );
        } ),
        const Divider(),
        TextField(
          controller: _other,
          decoration: const InputDecoration(
            labelText: "Other (optional)",
            border   : OutlineInputBorder(),
          ),
        ),
        const SizedBox( height: 12 ),
        FilledButton(
          onPressed: () {
            dynamic value;
            final other = _other.text.trim();
            if ( widget.multi ) {
              value = [ ..._multi, if ( other.isNotEmpty ) other ];
            } else {
              value = other.isNotEmpty ? other : ( _single ?? "" );
            }
            widget.onRespond( value );
          },
          child: const Text( "Submit" ),
        ),
      ],
    );
  }
}

// --- open ended -------------------------------------------------------------

class OpenEndedPromptBody extends StatefulWidget {
  final void Function( String ) onRespond;
  const OpenEndedPromptBody( { super.key, required this.onRespond } );

  @override
  State<OpenEndedPromptBody> createState() => _OpenEndedPromptBodyState();
}

class _OpenEndedPromptBodyState extends State<OpenEndedPromptBody> {
  final _ctrl = TextEditingController();

  @override
  Widget build( BuildContext context ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          minLines: 3,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Your response",
            border   : OutlineInputBorder(),
          ),
        ),
        const SizedBox( height: 12 ),
        FilledButton(
          onPressed: () => widget.onRespond( _ctrl.text ),
          child: const Text( "Submit" ),
        ),
      ],
    );
  }
}
