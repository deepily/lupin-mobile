import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../../services/asr/asr_service.dart';
import '../../../shared/widgets/prompt_bodies.dart';
import '../domain/notification_bloc.dart';
import '../domain/notification_event.dart';

/// Bottom sheet for answering an interactive notification.
///
/// Picks a body from `lib/shared/widgets/prompt_bodies.dart` by response type.
/// The types are yes_no, multiple_choice, open_ended and open_ended_batch.
/// Each body's answer is sent as a `NotificationsRespond` event, then the sheet closes.
class InteractivePromptSheet extends StatelessWidget {
  /// Id of the notification being answered.
  final String                notificationId;

  /// Response type that selects the body, such as `yes_no` or `multiple_choice`.
  final String                responseType;

  /// Response options from the notification payload, or null when it has none.
  final Map<String, dynamic>? options;

  /// Creates a sheet that answers [notificationId].
  const InteractivePromptSheet( {
    super.key,
    required this.notificationId,
    required this.responseType,
    this.options,
  } );

  /// Opens the sheet as a modal bottom sheet that shares the caller's bloc.
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

  /// The nested question list, or empty when the payload carries none.
  ///
  /// Every caller reads questions here, so they agree on where questions live.
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
        // A payload with nested questions gets the multi-question body.
        // Otherwise the top-level `options` and `multi_select` keys are read.
        final nested = _nestedQuestions( options );
        if ( nested.isNotEmpty ) {
          body = MultiQuestionPromptBody(
            questions : nested,
            // The server expects {"answers": {header: value}}, so the sheet wraps the map.
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
        // A batch question carries no `options`. It submits the {header: value} map unwrapped.
        body = MultiQuestionPromptBody(
          questions : _nestedQuestions( options ),
          onRespond : ( v ) => _submit( context, v ),
        );
        break;
      case "open_ended":
      default:
        // The append mic needs the ASR service, not a session. The body builds its own
        // session and cancels it on dispose. Without a registered service there is no mic.
        body = OpenEndedPromptBody(
          onRespond : ( v ) => _submit( context, v ),
          asr       : ServiceLocator.isRegistered<AsrService>()
              ? ServiceLocator.get<AsrService>()
              : null,
        );
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
