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
/// EVERY body now lives in `lib/shared/widgets/prompt_bodies.dart` and is
/// COMPOSED here, wiring `onRespond` to the existing `NotificationsRespond`
/// dispatch. The three single-String bodies moved in F-S3-1 (2026-06-12);
/// the batch body followed in AC-S4.16 (2026-08-29) as
/// [MultiQuestionPromptBody] — it was the only widget in the tree that read
/// the canonical nested `questions[]` shape, and being private is what kept
/// anyone from reusing it.
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

  /// The canonical nested question list, or empty when the payload does
  /// not carry one. ONE reader, so the two doors cannot disagree about
  /// where questions live.
  static List<dynamic> _nestedQuestions( Map<String, dynamic>? options ) =>
      ( options?[ "questions" ] as List? )?.cast<dynamic>() ?? const [];

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
        // 🔴 AC-S4.10b delta 3 / AC-S4.5. This read `options?["options"]`
        // and `options?["multi_select"]` at the TOP level, but a canonical
        // `ask_multiple_choice` payload nests its questions under
        // `response_options.questions[]` — so the sheet rendered an EMPTY
        // option list and submitted a bare label. It is the same defect the
        // focus pane carries one layer up, and this sheet is where the
        // pane's "Answer in full view…" fallback lands, so a canonical
        // payload used to hit the wall twice.
        final nested = _nestedQuestions( options );
        if ( nested.isNotEmpty ) {
          body = MultiQuestionPromptBody(
            questions : nested,
            // The server parser wants {"answers": {header: value}}; the
            // body stays door-agnostic and the HOST wraps (AC-S4.11).
            onRespond : ( v ) => _submit( context, { "answers": v } ),
          );
        } else {
          body = MultipleChoicePromptBody(
            options   : ( options?[ "options" ] as List? )?.cast<dynamic>() ?? const [],
            multi     : options?[ "multi_select" ] == true,
            onRespond : ( v ) => _submit( context, v ),
          );
        }
        break;
      case "open_ended_batch":
        // Unchanged shape: a batch question carries no `options`, so the
        // promoted body renders the same text fields and submits the same
        // {header: value} map it always did — unwrapped, as this door has
        // always expected.
        body = MultiQuestionPromptBody(
          questions : _nestedQuestions( options ),
          onRespond : ( v ) => _submit( context, v ),
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
