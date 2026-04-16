import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/notification_bloc.dart';
import '../domain/notification_event.dart';

/// Bottom sheet for responding to interactive notifications. Variants:
///   - yes_no            → two FilledButtons + optional comment
///   - multiple_choice   → radio list (single) or checkbox list (multi)
///   - open_ended        → multiline TextField
///   - open_ended_batch  → list of TextFields (one per question)
class InteractivePromptSheet extends StatelessWidget {
  final String                notificationId;
  final String                responseType;
  final Map<String, dynamic>? options;

  const InteractivePromptSheet( {
    super.key,
    required this.notificationId,
    required this.responseType,
    this.options,
  } );

  static Future<void> show( {
    required BuildContext  context,
    required String        notificationId,
    required String        responseType,
    Map<String, dynamic>?  options,
  } ) {
    return showModalBottomSheet<void>(
      context              : context,
      isScrollControlled   : true,
      showDragHandle       : true,
      builder: ( ctx ) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of( ctx ).viewInsets.bottom,
        ),
        child: BlocProvider.value(
          value: context.read<NotificationBloc>(),
          child: InteractivePromptSheet(
            notificationId : notificationId,
            responseType   : responseType,
            options        : options,
          ),
        ),
      ),
    );
  }

  void _submit( BuildContext context, dynamic value ) {
    context.read<NotificationBloc>().add( NotificationsRespond(
      notificationId : notificationId,
      responseValue  : value,
    ) );
    Navigator.of( context ).pop();
  }

  @override
  Widget build( BuildContext context ) {
    Widget body;
    switch ( responseType ) {
      case "yes_no":
        body = _YesNoBody( onSubmit: ( v ) => _submit( context, v ) );
        break;
      case "multiple_choice":
        body = _MultipleChoiceBody(
          options  : ( options?[ "options" ] as List? )?.cast<dynamic>() ?? const [],
          multi    : options?[ "multi_select" ] == true,
          onSubmit : ( v ) => _submit( context, v ),
        );
        break;
      case "open_ended_batch":
        body = _OpenEndedBatchBody(
          questions: ( options?[ "questions" ] as List? )?.cast<dynamic>() ?? const [],
          onSubmit : ( v ) => _submit( context, v ),
        );
        break;
      case "open_ended":
      default:
        body = _OpenEndedBody( onSubmit: ( v ) => _submit( context, v ) );
    }
    return Padding(
      padding: const EdgeInsets.all( 16 ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Respond",
            style: Theme.of( context ).textTheme.titleLarge,
          ),
          const SizedBox( height: 16 ),
          body,
        ],
      ),
    );
  }
}

// --- yes/no -----------------------------------------------------------------

class _YesNoBody extends StatefulWidget {
  final void Function( String ) onSubmit;
  const _YesNoBody( { required this.onSubmit } );

  @override
  State<_YesNoBody> createState() => _YesNoBodyState();
}

class _YesNoBodyState extends State<_YesNoBody> {
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
                onPressed: () => widget.onSubmit( _withComment( "no" ) ),
                child: const Text( "No" ),
              ),
            ),
            const SizedBox( width: 12 ),
            Expanded(
              child: FilledButton(
                onPressed: () => widget.onSubmit( _withComment( "yes" ) ),
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

class _MultipleChoiceBody extends StatefulWidget {
  final List<dynamic>           options;
  final bool                    multi;
  final void Function( dynamic ) onSubmit;

  const _MultipleChoiceBody( {
    required this.options,
    required this.multi,
    required this.onSubmit,
  } );

  @override
  State<_MultipleChoiceBody> createState() => _MultipleChoiceBodyState();
}

class _MultipleChoiceBodyState extends State<_MultipleChoiceBody> {
  String?      _single;
  Set<String>  _multi = {};
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
            widget.onSubmit( value );
          },
          child: const Text( "Submit" ),
        ),
      ],
    );
  }
}

// --- open ended -------------------------------------------------------------

class _OpenEndedBody extends StatefulWidget {
  final void Function( String ) onSubmit;
  const _OpenEndedBody( { required this.onSubmit } );

  @override
  State<_OpenEndedBody> createState() => _OpenEndedBodyState();
}

class _OpenEndedBodyState extends State<_OpenEndedBody> {
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
          onPressed: () => widget.onSubmit( _ctrl.text ),
          child: const Text( "Submit" ),
        ),
      ],
    );
  }
}

// --- open-ended batch -------------------------------------------------------

class _OpenEndedBatchBody extends StatefulWidget {
  final List<dynamic>                  questions;
  final void Function( Map<String, String> ) onSubmit;

  const _OpenEndedBatchBody( {
    required this.questions,
    required this.onSubmit,
  } );

  @override
  State<_OpenEndedBatchBody> createState() => _OpenEndedBatchBodyState();
}

class _OpenEndedBatchBodyState extends State<_OpenEndedBatchBody> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.questions.length,
      ( _ ) => TextEditingController(),
    );
  }

  String _question( dynamic q ) {
    if ( q is Map ) return ( q[ "question" ] ?? "" ).toString();
    return q.toString();
  }

  String _key( dynamic q, int i ) {
    if ( q is Map && q[ "header" ] != null ) return q[ "header" ].toString();
    return "q_$i";
  }

  @override
  Widget build( BuildContext context ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...List.generate( widget.questions.length, ( i ) {
          return Padding(
            padding: const EdgeInsets.only( bottom: 12 ),
            child: TextField(
              controller: _controllers[ i ],
              decoration: InputDecoration(
                labelText: _question( widget.questions[ i ] ),
                border   : const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          );
        } ),
        FilledButton(
          onPressed: () {
            final map = <String, String>{};
            for ( var i = 0; i < widget.questions.length; i++ ) {
              map[ _key( widget.questions[ i ], i ) ] = _controllers[ i ].text;
            }
            widget.onSubmit( map );
          },
          child: const Text( "Submit all" ),
        ),
      ],
    );
  }
}
