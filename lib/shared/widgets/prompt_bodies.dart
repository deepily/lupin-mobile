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
/// 🔴 **That earlier decision is REVERSED — AC-S4.16, 2026-08-29.** This
/// comment used to say the batch body was intentionally left behind under
/// F-S3-S2-2(d), because it submitted a `Map<String, String>` and belonged
/// with the legacy sheet. True and reasonable when written; false now, and
/// left standing it is in-tree documentation arguing against the
/// requirement — a citation for doing the wrong thing.
///
/// (The old wording is deliberately NOT reproduced verbatim here. A
/// grep-able invariant that a quotation can satisfy is not an invariant —
/// the test for this reversal greps for the retired phrase, and quoting it
/// to be helpful is exactly how such a check goes quietly green.)
///
/// What changed: a canonical `ask_multiple_choice` payload nests its
/// questions under `response_options.questions[]`, and the batch body was
/// **already the only widget in the tree that reads that shape** and keys
/// answers by `header`. The very `Map<String, String>` submission the old
/// comment cited as the reason to leave it stranded is precisely what
/// AC-S4.5 needs. So the rationale for keeping it private became the
/// argument for promoting it. It is now [MultiQuestionPromptBody], below —
/// a MOVE, not a copy: nothing question-shaped stayed behind in
/// `interactive_prompt_sheet.dart`.
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

// --- multi-question (PROMOTED from interactive_prompt_sheet.dart) ------------

/// One prompt covering N questions — AC-S4.16, AC-S4.5.
///
/// **Moved, not rewritten.** This was `_OpenEndedBatchBody`, `_`-private to
/// `interactive_prompt_sheet.dart`, where nobody could reuse it. It already
/// read the canonical nested `response_options.questions[]` shape and
/// already keyed each answer by its `header` — the exact behaviour AC-S4.5
/// asks for. The plan originally said to build a one-question-at-a-time
/// stepper; building one would have put a second widget in the tree for a
/// payload shape this one already handled better.
///
/// The single addition on promotion: a question carrying its own
/// `options` list renders as a CHOICE control rather than a text field.
/// That is what a canonical `ask_multiple_choice` payload looks like, and
/// what previously fell through to an empty option list one layer up. A
/// question with no options is unchanged — a `TextField`, exactly as the
/// `open_ended_batch` path has always rendered it.
///
/// 🔴 Status-blind and door-agnostic (AC-S4.11): it takes questions and a
/// callback, and knows nothing about endpoints, `status`, or which of the
/// four doors is asking. The HOST decides where the value goes.
class MultiQuestionPromptBody extends StatefulWidget {
  /// The nested `response_options.questions[]` list. Each entry may carry
  /// `question`, `header`, `options`, `multi_select`; a bare string is
  /// treated as the question text.
  final List<dynamic> questions;

  /// Answers keyed by each question's `header` (falling back to `q_<i>`).
  /// A value is a `String` for a text or single-select question, and a
  /// `List<String>` for a multi-select one — the shape each question's own
  /// payload asked for.
  final void Function( Map<String, dynamic> ) onRespond;

  const MultiQuestionPromptBody( {
    super.key,
    required this.questions,
    required this.onRespond,
  } );

  @override
  State<MultiQuestionPromptBody> createState() => _MultiQuestionPromptBodyState();
}

class _MultiQuestionPromptBodyState extends State<MultiQuestionPromptBody> {
  final Map<int, TextEditingController> _text    = {};
  final Map<int, String>                _single  = {};
  final Map<int, Set<String>>           _multi   = {};

  @override
  void initState() {
    super.initState();
    for ( var i = 0; i < widget.questions.length; i++ ) {
      if ( _optionsOf( widget.questions[ i ] ).isEmpty ) {
        _text[ i ] = TextEditingController();
      } else if ( _isMulti( widget.questions[ i ] ) ) {
        _multi[ i ] = <String>{};
      }
    }
  }

  @override
  void dispose() {
    for ( final c in _text.values ) {
      c.dispose();
    }
    super.dispose();
  }

  String _question( dynamic q ) {
    if ( q is Map ) return ( q[ "question" ] ?? "" ).toString();
    return q.toString();
  }

  /// The answer key: the server's own `header`, so the submitted map is
  /// the `{header: value}` shape its parser expects rather than a bare
  /// label. Positional fallback for a payload without one.
  String _key( dynamic q, int i ) {
    if ( q is Map && q[ "header" ] != null ) return q[ "header" ].toString();
    return "q_$i";
  }

  List<dynamic> _optionsOf( dynamic q ) {
    if ( q is Map && q[ "options" ] is List ) return q[ "options" ] as List<dynamic>;
    return const [];
  }

  bool _isMulti( dynamic q ) => q is Map && q[ "multi_select" ] == true;

  String _label( dynamic opt ) {
    if ( opt is Map ) return ( opt[ "label" ] ?? "" ).toString();
    return opt.toString();
  }

  Widget _questionBody( int i, dynamic q ) {
    final options = _optionsOf( q );
    if ( options.isEmpty ) {
      return TextField(
        controller: _text[ i ],
        decoration: InputDecoration(
          labelText: _question( q ),
          border   : const OutlineInputBorder(),
        ),
        maxLines: 2,
      );
    }

    final multi = _isMulti( q );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text( _question( q ) ),
        ...options.map( ( opt ) {
          final label = _label( opt );
          if ( multi ) {
            return CheckboxListTile(
              dense    : true,
              title    : Text( label ),
              value    : _multi[ i ]!.contains( label ),
              onChanged: ( v ) => setState( () {
                if ( v == true ) {
                  _multi[ i ]!.add( label );
                } else {
                  _multi[ i ]!.remove( label );
                }
              } ),
            );
          }
          return RadioListTile<String>(
            dense      : true,
            title      : Text( label ),
            value      : label,
            groupValue : _single[ i ],
            onChanged  : ( v ) => setState( () => _single[ i ] = v ?? '' ),
          );
        } ),
      ],
    );
  }

  @override
  Widget build( BuildContext context ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...List.generate( widget.questions.length, ( i ) => Padding(
          padding : const EdgeInsets.only( bottom: 12 ),
          child   : _questionBody( i, widget.questions[ i ] ),
        ) ),
        FilledButton(
          key: const Key( TestKeys.promptMultiQuestionSubmit ),
          onPressed: () {
            final answers = <String, dynamic>{};
            for ( var i = 0; i < widget.questions.length; i++ ) {
              final q = widget.questions[ i ];
              answers[ _key( q, i ) ] = _text.containsKey( i )
                  ? _text[ i ]!.text
                  : ( _isMulti( q ) ? _multi[ i ]!.toList() : ( _single[ i ] ?? '' ) );
            }
            widget.onRespond( answers );
          },
          child: const Text( "Submit all" ),
        ),
      ],
    );
  }
}
