import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../data/notification_models.dart';
import '../domain/notification_bloc.dart';
import '../domain/notification_event.dart';
import '../domain/notification_state.dart';
import 'conversation_by_date_screen.dart';

/// Per-sender date browse screen.
///
/// Backed by `GET /api/notifications/sender-dates/{sender}/{user}`, which
/// returns `List<DateSummary>` (date YYYY-MM-DD, count, newCount). Tapping
/// a date pushes [ConversationByDateScreen] anchored to that date.
class SenderDatesScreen extends StatefulWidget {
  final String senderId;
  final String userEmail;

  const SenderDatesScreen( {
    super.key,
    required this.senderId,
    required this.userEmail,
  } );

  @override
  State<SenderDatesScreen> createState() => _SenderDatesScreenState();
}

class _SenderDatesScreenState extends State<SenderDatesScreen> {
  @override
  void initState() {
    super.initState();
    context.read<NotificationBloc>().add( NotificationsLoadSenderDates(
      senderId  : widget.senderId,
      userEmail : widget.userEmail,
    ) );
  }

  Future<void> _refresh() async {
    context.read<NotificationBloc>().add( NotificationsLoadSenderDates(
      senderId  : widget.senderId,
      userEmail : widget.userEmail,
    ) );
  }

  void _openDate( DateSummary date ) {
    final bloc = context.read<NotificationBloc>();
    Navigator.of( context ).push( MaterialPageRoute(
      builder: ( _ ) => BlocProvider<NotificationBloc>.value(
        value: bloc,
        child: ConversationByDateScreen(
          senderId   : widget.senderId,
          userEmail  : widget.userEmail,
          anchorDate : date.date,
        ),
      ),
    ) );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "${widget.senderId} · dates",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: BlocBuilder<NotificationBloc, NotificationState>(
        buildWhen: ( prev, next ) =>
          next is NotificationsSenderDatesLoaded ||
          next is NotificationsLoading           ||
          next is NotificationsError,
        builder: ( context, state ) {
          if ( state is NotificationsLoading ) {
            return const Center( child: CircularProgressIndicator() );
          }
          if ( state is NotificationsError ) {
            return Center( child: Text( state.message ) );
          }
          if ( state is NotificationsSenderDatesLoaded ) {
            if ( state.dates.isEmpty ) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all( 32 ),
                      child: Center( child: Text( "No dates" ) ),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                itemCount: state.dates.length,
                separatorBuilder: ( _, __ ) => const Divider( height: 1 ),
                itemBuilder: ( _, i ) {
                  final d = state.dates[ i ];
                  return ListTile(
                    key      : Key( '${TestKeys.senderDatesTilePrefix}${d.date}' ),
                    leading  : const Icon( Icons.calendar_today ),
                    title    : Text( d.date ),
                    subtitle : Text(
                      "${d.count} message${d.count == 1 ? '' : 's'}",
                    ),
                    trailing : d.newCount > 0
                        ? CircleAvatar(
                            radius: 12,
                            backgroundColor: Theme.of( context ).colorScheme.primary,
                            child: Text(
                              "${d.newCount}",
                              style: TextStyle(
                                color: Theme.of( context ).colorScheme.onPrimary,
                                fontSize: 11,
                              ),
                            ),
                          )
                        : null,
                    onTap: () => _openDate( d ),
                  );
                },
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
