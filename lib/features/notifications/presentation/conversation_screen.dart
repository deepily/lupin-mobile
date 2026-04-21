import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../data/notification_models.dart';
import '../domain/notification_bloc.dart';
import '../domain/notification_event.dart';
import '../domain/notification_state.dart';
import 'interactive_prompt_sheet.dart';

class ConversationScreen extends StatefulWidget {
  final String senderId;
  final String userEmail;

  const ConversationScreen( {
    super.key,
    required this.senderId,
    required this.userEmail,
  } );

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  @override
  void initState() {
    super.initState();
    context.read<NotificationBloc>().add( NotificationsLoadConversation(
      senderId  : widget.senderId,
      userEmail : widget.userEmail,
    ) );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.senderId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key      : const Key( TestKeys.convSummarizeButton ),
            tooltip  : "Summarize",
            icon     : const Icon( Icons.summarize_outlined ),
            onPressed: () => context.read<NotificationBloc>().add(
              const NotificationsGenerateGistRequested(),
            ),
          ),
        ],
      ),
      body: BlocConsumer<NotificationBloc, NotificationState>(
        listener: ( context, state ) {
          if ( state is NotificationsResponseAcked ) {
            ScaffoldMessenger.of( context ).showSnackBar(
              const SnackBar( content: Text( "Response sent" ) ),
            );
          } else if ( state is NotificationsGistReady ) {
            _showGistSheet( context, state.gist );
          }
        },
        buildWhen: ( prev, next ) =>
          next is NotificationsConversationLoaded ||
          next is NotificationsLoading           ||
          next is NotificationsError,
        builder: ( context, state ) {
          if ( state is NotificationsLoading ) {
            return const Center( child: CircularProgressIndicator() );
          }
          if ( state is NotificationsError ) {
            return Center( child: Text( state.message ) );
          }
          if ( state is NotificationsConversationLoaded ) {
            if ( state.messages.isEmpty ) {
              return const Center( child: Text( "No messages" ) );
            }
            return ListView.separated(
              padding: const EdgeInsets.all( 12 ),
              itemCount: state.messages.length,
              separatorBuilder: ( _, __ ) => const SizedBox( height: 8 ),
              itemBuilder: ( _, i ) => _MessageCard( message: state.messages[ i ] ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

void _showGistSheet( BuildContext context, String gist ) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: ( _ ) => SafeArea(
      child: SingleChildScrollView(
        key: const Key( TestKeys.convGistSheet ),
        padding: const EdgeInsets.all( 16 ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row( children: [
              const Icon( Icons.summarize_outlined ),
              const SizedBox( width: 8 ),
              Text( "Summary", style: Theme.of( context ).textTheme.titleMedium ),
            ] ),
            const SizedBox( height: 12 ),
            SelectableText( gist ),
            const SizedBox( height: 16 ),
          ],
        ),
      ),
    ),
  );
}

class _MessageCard extends StatelessWidget {
  final ConversationMessage message;
  const _MessageCard( { required this.message } );

  Color _stateColor( BuildContext c ) {
    switch ( message.state ) {
      case "delivered": return Colors.blue;
      case "responded": return Colors.green;
      case "expired"  : return Colors.grey;
      case "pending"  :
      default          : return Colors.orange;
    }
  }

  @override
  Widget build( BuildContext context ) {
    final theme = Theme.of( context );
    final hasResponse = message.responseRequested && message.respondedAt == null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all( 12 ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: _stateColor( context ).withOpacity( 0.15 ),
                  side: BorderSide( color: _stateColor( context ) ),
                  label: Text(
                    message.state ?? "pending",
                    style: TextStyle( color: _stateColor( context ), fontSize: 11 ),
                  ),
                ),
                if ( message.timeDisplay != null )
                  Text(
                    message.timeDisplay!,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox( height: 8 ),
            if ( message.title != null && message.title!.isNotEmpty ) ...[
              Text(
                message.title!,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox( height: 4 ),
            ],
            Text( message.message ),
            if ( message.abstractText != null && message.abstractText!.isNotEmpty ) ...[
              const SizedBox( height: 8 ),
              Container(
                padding: const EdgeInsets.all( 8 ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular( 6 ),
                ),
                child: Text(
                  message.abstractText!,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            if ( hasResponse ) ...[
              const SizedBox( height: 12 ),
              FilledButton.tonalIcon(
                onPressed: () => InteractivePromptSheet.show(
                  context        : context,
                  notificationId : message.id,
                  responseType   : message.responseType ?? "open_ended",
                  options        : null,
                ),
                icon  : const Icon( Icons.touch_app_outlined ),
                label : const Text( "Respond" ),
              ),
            ],
            if ( message.responseValue != null ) ...[
              const SizedBox( height: 8 ),
              Text(
                "Response: ${message.responseValue}",
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
