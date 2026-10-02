import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/testing/test_keys.dart';
import '../../docs/data/doc_repository.dart';
import '../../docs/presentation/abstract_body.dart';
import '../data/notification_models.dart';
import '../domain/notification_bloc.dart';
import '../domain/notification_event.dart';
import '../domain/notification_state.dart';
import 'interactive_prompt_sheet.dart';
import 'persona_badge.dart';

/// Shows a sender's conversation grouped by date, newest date first.
///
/// Backed by `GET /api/notifications/conversation-by-date/{sender}/{user}`,
/// which returns a map from `YYYY-MM-DD` to that day's [NotificationItem]s.
/// Items show no delivery-state badge; the flat conversation screen does.
class ConversationByDateScreen extends StatefulWidget {
  /// Sender whose conversation is shown.
  final String  senderId;

  /// Email of the user the messages were addressed to.
  final String  userEmail;

  /// Date (`YYYY-MM-DD`) passed on when entering from a date tile; null otherwise.
  final String? anchorDate;

  /// Creates the screen for [senderId] and [userEmail], optionally anchored.
  const ConversationByDateScreen( {
    super.key,
    required this.senderId,
    required this.userEmail,
    this.anchorDate,
  } );

  @override
  State<ConversationByDateScreen> createState() => _ConversationByDateScreenState();
}

class _ConversationByDateScreenState extends State<ConversationByDateScreen> {
  @override
  void initState() {
    super.initState();
    context.read<NotificationBloc>().add( NotificationsLoadConversationByDate(
      senderId  : widget.senderId,
      userEmail : widget.userEmail,
      anchor    : widget.anchorDate,
    ) );
  }

  Future<void> _refresh() async {
    context.read<NotificationBloc>().add( NotificationsLoadConversationByDate(
      senderId  : widget.senderId,
      userEmail : widget.userEmail,
      anchor    : widget.anchorDate,
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
      ),
      body: BlocBuilder<NotificationBloc, NotificationState>(
        buildWhen: ( prev, next ) =>
          next is NotificationsConversationByDateLoaded ||
          next is NotificationsLoading                  ||
          next is NotificationsError,
        builder: ( context, state ) {
          if ( state is NotificationsLoading ) {
            return const Center( child: CircularProgressIndicator() );
          }
          if ( state is NotificationsError ) {
            return Center( child: Text( state.message ) );
          }
          if ( state is NotificationsConversationByDateLoaded ) {
            if ( state.byDate.isEmpty ) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all( 32 ),
                      child: Center( child: Text( "No messages" ) ),
                    ),
                  ],
                ),
              );
            }
            // Sort dates descending (most recent first) for a chronological feed.
            final dates = state.byDate.keys.toList()..sort( ( a, b ) => b.compareTo( a ) );
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.symmetric( vertical: 8 ),
                children: [
                  for ( final date in dates ) ...[
                    Padding(
                      key: Key( '${TestKeys.convByDateSectionHeaderPrefix}$date' ),
                      padding: const EdgeInsets.fromLTRB( 16, 16, 16, 4 ),
                      child: Row(
                        children: [
                          const Icon( Icons.calendar_today, size: 14 ),
                          const SizedBox( width: 8 ),
                          Text( date, style: Theme.of( context ).textTheme.titleSmall ),
                          const SizedBox( width: 6 ),
                          Text(
                            "(${state.byDate[ date ]!.length})",
                            style: Theme.of( context ).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    ...state.byDate[ date ]!.map( ( item ) =>
                      _NotificationItemCard( item: item ),
                    ),
                  ],
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

/// Renders one [NotificationItem] for the date-grouped view.
///
/// The by-date endpoint carries no delivery state or response value, so this
/// card differs from the flat conversation screen's message card.
class _NotificationItemCard extends StatelessWidget {
  final NotificationItem item;
  const _NotificationItemCard( { required this.item } );

  Color _priorityColor() {
    switch ( item.priority ) {
      case "urgent": return Colors.red;
      case "high"  : return Colors.orange;
      case "medium": return Colors.blue;
      case "low"   :
      default       : return Colors.grey;
    }
  }

  @override
  Widget build( BuildContext context ) {
    final theme       = Theme.of( context );
    final color       = _priorityColor();
    final showRespond = item.responseRequested && item.responseType != null;
    final titleStyle  = item.played
        ? theme.textTheme.titleMedium?.copyWith( color: theme.disabledColor )
        : theme.textTheme.titleMedium?.copyWith( fontWeight: FontWeight.bold );
    return Card(
      key: Key( '${TestKeys.convByDateItemPrefix}${item.id}' ),
      margin: const EdgeInsets.symmetric( horizontal: 12, vertical: 4 ),
      child: Padding(
        padding: const EdgeInsets.all( 12 ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Chip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: color.withOpacity( 0.15 ),
                      side: BorderSide( color: color ),
                      label: Text(
                        item.priority,
                        style: TextStyle( color: color, fontSize: 11 ),
                      ),
                    ),
                    if ( item.voicePersona != null ) ...[
                      const SizedBox( width: 8 ),
                      PersonaBadge(
                        persona  : item.voicePersona,
                        senderId : item.senderId,
                        diameter : 24,
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    if ( item.played )
                      Padding(
                        padding: const EdgeInsets.only( right: 6 ),
                        child: Icon( Icons.done_all, size: 14, color: theme.disabledColor ),
                      ),
                    if ( item.timeDisplay != null )
                      Text( item.timeDisplay!, style: theme.textTheme.bodySmall ),
                  ],
                ),
              ],
            ),
            const SizedBox( height: 8 ),
            if ( item.title != null && item.title!.isNotEmpty ) ...[
              Text( item.title!, style: titleStyle ),
              const SizedBox( height: 4 ),
            ],
            Text( item.message ),
            if ( item.abstractText != null && item.abstractText!.isNotEmpty ) ...[
              const SizedBox( height: 8 ),
              AbstractBody(
                abstractText : item.abstractText,
                repository   : ServiceLocator.instance<DocRepository>(),
              ),
            ],
            if ( showRespond ) ...[
              const SizedBox( height: 12 ),
              FilledButton.tonalIcon(
                key: Key( '${TestKeys.convByDateRespondPrefix}${item.id}' ),
                onPressed: () => InteractivePromptSheet.show(
                  context        : context,
                  notificationId : item.id,
                  responseType   : item.responseType ?? "open_ended",
                  options        : null,
                ),
                icon  : const Icon( Icons.touch_app_outlined ),
                label : const Text( "Respond" ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
