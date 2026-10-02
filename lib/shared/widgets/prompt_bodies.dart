/// Interactive-prompt bodies shared by the notification sheet and the focus pane.
///
/// Each body takes its data and an `onRespond` callback. It knows nothing about
/// endpoints or which screen hosts it; the host decides where the answer goes.
/// Yes/no and open-ended answers are strings. Multiple choice keeps a `dynamic`
/// callback because its multi-select form submits a `List`.
/// Design: src/docs/decisions/README.md (R-prompt-bodies-shared)
library;

import 'package:flutter/material.dart';

import '../../core/testing/test_keys.dart';
import '../../services/asr/asr_service.dart';
import '../../services/permissions/mic_permission.dart';
import 'dictation_text_field.dart';

// --- yes/no -----------------------------------------------------------------

/// Yes, No and Neither buttons over an optional comment box.
class YesNoPromptBody extends StatefulWidget {
  /// Receives "yes", "no" or "neither", with ` [comment: …]` appended when a comment was typed.
  final void Function( String ) onRespond;

  /// Whether the comment box offers dictation; false gives a plain text box.
  ///
  /// Quick Ask passes false, because its bloc owns a recorder on the same screen.
  final bool dictate;

  /// Creates the body; [dictate] defaults to true.
  const YesNoPromptBody( { super.key, required this.onRespond, this.dictate = true } );

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
        DictationTextField(
          fieldKey  : const Key( TestKeys.promptCommentField ),
          controller: _comment,
          dictate   : widget.dictate,
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

/// A list of options with an "Other" box and a Submit button.
class MultipleChoicePromptBody extends StatefulWidget {
  /// The options; each is a map with a `label`, or a bare value shown as text.
  final List<dynamic>            options;

  /// Whether several options can be ticked; false gives radio buttons.
  final bool                     multi;

  /// Receives a `String` for single-select and a `List` for multi-select.
  ///
  /// The focus pane composes this body only with [multi] false.
  final void Function( dynamic ) onRespond;

  /// Creates the body over [options].
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
        DictationTextField(
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

/// A free-text answer box with dictation and a Submit button.
class OpenEndedPromptBody extends StatefulWidget {
  /// Receives the text of the box when Submit is tapped.
  final void Function( String ) onRespond;

  /// The recorder service, or null to take it from the app's [DictationScope].
  ///
  /// With neither there is no microphone. The box builds its own recording
  /// session from the service and cancels it on dispose, so no ancestor owns one.
  final AsrService? asr;

  /// Test seam for the permission prompt.
  final MicPermissionRequester? requestMicPermission;

  /// Whether the box offers dictation; false gives a plain text box.
  ///
  /// Quick Ask's interview answer passes false, because its bloc owns a
  /// recorder on the same screen.
  final bool dictate;

  /// Creates the body; [dictate] defaults to true.
  const OpenEndedPromptBody( {
    super.key,
    required this.onRespond,
    this.asr,
    this.requestMicPermission,
    this.dictate = true,
  } );

  @override
  State<OpenEndedPromptBody> createState() => _OpenEndedPromptBodyState();
}

class _OpenEndedPromptBodyState extends State<OpenEndedPromptBody> {
  final _ctrl = TextEditingController();

  DictationPhase _phase = DictationPhase.idle;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DictationTextField(
          fieldKey             : const Key( TestKeys.promptResponseField ),
          micKey               : const Key( TestKeys.promptResponseMic ),
          cancelKey            : const Key( TestKeys.promptResponseMicCancel ),
          errorKey             : const Key( TestKeys.promptResponseMicError ),
          controller           : _ctrl,
          asr                  : widget.asr,
          requestMicPermission : widget.requestMicPermission,
          dictate              : widget.dictate,
          minLines             : 3,
          maxLines             : 6,
          autofocus            : true,
          onPhaseChanged       : ( p ) => setState( () => _phase = p ),
          decoration           : const InputDecoration(
            labelText: "Your response",
            border   : OutlineInputBorder(),
          ),
        ),
        const SizedBox( height: 12 ),
        // While a chunk records or transcribes, Submit is hidden, so a half-dictated
        // answer cannot be sent by a stray tap and the prompt is answered once.
        if ( _phase == DictationPhase.idle )
          FilledButton(
            onPressed: () => widget.onRespond( _ctrl.text ),
            child: const Text( "Submit" ),
          ),
      ],
    );
  }
}

// --- multi-question ----------------------------------------------------------

/// One prompt covering several questions, answered together with one Submit.
///
/// It reads the nested `response_options.questions[]` shape and keys each answer
/// by the question's `header`. A question with its own `options` renders as a
/// choice control; a question without options renders as a text box.
/// It takes questions and a callback, and the host decides where the value goes.
/// Design: src/docs/decisions/README.md (R-prompt-bodies-shared)
class MultiQuestionPromptBody extends StatefulWidget {
  /// The nested `response_options.questions[]` list.
  ///
  /// Each entry may carry `question`, `header`, `options` and `multi_select`.
  /// A bare string is treated as the question text.
  final List<dynamic> questions;

  /// Receives the answers keyed by each question's `header`, or `q_<i>` without one.
  ///
  /// A value is a `String` for a text or single-select question and a
  /// `List<String>` for a multi-select one.
  final void Function( Map<String, dynamic> ) onRespond;

  /// Creates the body over [questions].
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

  /// The answer key: the question's `header`, or `q_<i>` when it has none.
  ///
  /// The server's parser expects a `{header: value}` map.
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

  /// The option's `description` as a subtitle, or null when it has none.
  ///
  /// The description carries the pros and cons of the option.
  Widget? _subtitle( dynamic opt ) {
    if ( opt is! Map ) return null;
    final d = ( opt[ "description" ] ?? "" ).toString().trim();
    return d.isEmpty ? null : Text( d );
  }

  Widget _questionBody( int i, dynamic q ) {
    final options = _optionsOf( q );
    if ( options.isEmpty ) {
      // One recorder across N boxes: the recorder guard disables every other
      // box's mic while one records.
      return DictationTextField(
        controller: _text[ i ]!,
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
              subtitle : _subtitle( opt ),
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
            subtitle   : _subtitle( opt ),
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
