import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/widgets/prompt_bodies.dart';
import '../domain/notification_bloc.dart';
import '../domain/notification_event.dart';

/// Bottom sheet for responding to interactive notifications. Variants:
///   - yes_no            → two FilledButtons + optional comment
///   - multiple_choice   → radio list (single) or checkbox list (multi)
///   - open_ended        → multiline TextField
///   - open_ended_batch  → list of TextFields (one per question)
///
/// The three single-String bodies (yes/no, multiple-choice, open-ended)
/// were EXTRACTED to `lib/shared/widgets/prompt_bodies.dart` (F-S3-1,
/// 2026-06-12) and are COMPOSED here, wiring `onRespond` to the existing
/// `NotificationsRespond` dispatch — behavior-neutral for this surface
/// (AC-S3.9). The batch body stays private here (F-S3-S2-2(d): it submits
/// a Map; focus-mode bubbles route batch asks to this sheet instead).
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
        body = YesNoPromptBody( onRespond: ( v ) => _submit( context, v ) );
        break;
      case "multiple_choice":
        body = MultipleChoicePromptBody(
          options   : ( options?[ "options" ] as List? )?.cast<dynamic>() ?? const [],
          multi     : options?[ "multi_select" ] == true,
          onRespond : ( v ) => _submit( context, v ),
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
        body = OpenEndedPromptBody( onRespond: ( v ) => _submit( context, v ) );
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

// --- open-ended batch (UNEXTRACTED — Map-valued, F-S3-S2-2(d)) ---------------

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
