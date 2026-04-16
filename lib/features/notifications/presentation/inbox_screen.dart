import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/notification_models.dart';
import '../domain/notification_bloc.dart';
import '../domain/notification_event.dart';
import '../domain/notification_state.dart';
import 'conversation_screen.dart';

class InboxScreen extends StatefulWidget {
  final String userEmail;
  const InboxScreen( { super.key, required this.userEmail } );

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  @override
  void initState() {
    super.initState();
    context.read<NotificationBloc>().add(
      NotificationsLoadInbox( userEmail: widget.userEmail ),
    );
  }

  Future<void> _refresh() async {
    context.read<NotificationBloc>().add(
      NotificationsLoadInbox( userEmail: widget.userEmail ),
    );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text( "Inbox" ),
        actions: [
          IconButton(
            tooltip: "Clear all",
            icon: const Icon( Icons.delete_sweep_outlined ),
            onPressed: () => _confirmBulkDelete( context ),
          ),
        ],
      ),
      body: BlocBuilder<NotificationBloc, NotificationState>(
        builder: ( context, state ) {
          if ( state is NotificationsLoading || state is NotificationsInitial ) {
            return const Center( child: CircularProgressIndicator() );
          }
          if ( state is NotificationsError ) {
            return _ErrorView( message: state.message, onRetry: _refresh );
          }
          if ( state is NotificationsInboxLoaded ) {
            if ( state.senders.isEmpty ) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  children: const [
                    SizedBox( height: 200 ),
                    Center( child: Text( "No notifications" ) ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                itemCount: state.senders.length,
                separatorBuilder: ( _, __ ) => const Divider( height: 1 ),
                itemBuilder: ( _, i ) => _SenderTile(
                  sender    : state.senders[ i ],
                  userEmail : widget.userEmail,
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Future<void> _confirmBulkDelete( BuildContext ctx ) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: ( c ) => AlertDialog(
        title  : const Text( "Clear all notifications?" ),
        content: const Text(
          "This soft-deletes everything in the inbox. You can restore from the backend if needed.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of( c ).pop( false ),
            child: const Text( "Cancel" ),
          ),
          FilledButton(
            onPressed: () => Navigator.of( c ).pop( true ),
            child: const Text( "Clear" ),
          ),
        ],
      ),
    );
    if ( confirmed == true && context.mounted ) {
      context.read<NotificationBloc>().add(
        NotificationsBulkDelete( userEmail: widget.userEmail ),
      );
    }
  }
}

class _SenderTile extends StatelessWidget {
  final SenderSummary sender;
  final String        userEmail;

  const _SenderTile( { required this.sender, required this.userEmail } );

  @override
  Widget build( BuildContext context ) {
    final theme    = Theme.of( context );
    final newCount = sender.newCount ?? 0;
    return Dismissible(
      key: ValueKey( sender.senderId ),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric( horizontal: 16 ),
        color: Colors.red.withOpacity( 0.8 ),
        child: const Icon( Icons.delete, color: Colors.white ),
      ),
      onDismissed: ( _ ) {
        context.read<NotificationBloc>().add(
          NotificationsDeleteConversation(
            senderId  : sender.senderId,
            userEmail : userEmail,
          ),
        );
      },
      child: ListTile(
        leading: CircleAvatar(
          child: Text( sender.senderId.isNotEmpty ? sender.senderId[ 0 ].toUpperCase() : "?" ),
        ),
        title: Text(
          sender.senderId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          "${sender.count} message${sender.count == 1 ? '' : 's'}"
          + ( sender.lastActivity != null
              ? "  ·  ${_relativeTime( sender.lastActivity! )}"
              : "" ),
        ),
        trailing: newCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric( horizontal: 8, vertical: 2 ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular( 12 ),
              ),
              child: Text(
                "$newCount",
                style: TextStyle( color: theme.colorScheme.onPrimary ),
              ),
            )
          : null,
        onTap: () => Navigator.of( context ).push( MaterialPageRoute(
          builder: ( _ ) => ConversationScreen(
            senderId  : sender.senderId,
            userEmail : userEmail,
          ),
        ) ),
      ),
    );
  }
}

String _relativeTime( DateTime ts ) {
  final delta = DateTime.now().difference( ts );
  if ( delta.inSeconds < 60 ) return "${delta.inSeconds}s ago";
  if ( delta.inMinutes < 60 ) return "${delta.inMinutes}m ago";
  if ( delta.inHours   < 24 ) return "${delta.inHours}h ago";
  return "${delta.inDays}d ago";
}

class _ErrorView extends StatelessWidget {
  final String        message;
  final VoidCallback  onRetry;
  const _ErrorView( { required this.message, required this.onRetry } );

  @override
  Widget build( BuildContext context ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon( Icons.error_outline, size: 48 ),
          const SizedBox( height: 12 ),
          Padding(
            padding: const EdgeInsets.symmetric( horizontal: 24 ),
            child: Text( message, textAlign: TextAlign.center ),
          ),
          const SizedBox( height: 12 ),
          FilledButton.tonal( onPressed: onRetry, child: const Text( "Retry" ) ),
        ],
      ),
    );
  }
}
