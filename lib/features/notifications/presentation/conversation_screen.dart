import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/testing/test_keys.dart';
import '../../docs/data/doc_repository.dart';
import '../../docs/presentation/abstract_body.dart';
import '../../../services/notification_filter/notification_stop_list.dart';
import '../../../services/notification_filter/progress_group_collapse.dart';
import '../data/notification_models.dart';
import '../domain/notification_bloc.dart';
import '../domain/notification_event.dart';
import '../domain/notification_state.dart';
import 'interactive_prompt_sheet.dart';
import 'message_stamp.dart';
import 'persona_badge.dart';
import 'sender_dates_screen.dart';

class ConversationScreen extends StatefulWidget {
  final String senderId;
  final String userEmail;
  /// Stop-list seam (plan 2026.08.21 §3). Tests inject; production resolves
  /// from the locator when registered; null ⇒ no filtering.
  final NotificationStopList? stopList;

  const ConversationScreen( {
    super.key,
    required this.senderId,
    required this.userEmail,
    this.stopList,
  } );

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  NotificationStopList? _stopList;
  bool _showHidden = false;

  @override
  void initState() {
    super.initState();
    _stopList = widget.stopList ??
        ( ServiceLocator.isRegistered<NotificationStopList>()
            ? ServiceLocator.get<NotificationStopList>()
            : null );
    _stopList?.addListener( _onStopListChanged );
    context.read<NotificationBloc>().add( NotificationsLoadConversation(
      senderId  : widget.senderId,
      userEmail : widget.userEmail,
    ) );
  }

  @override
  void dispose() {
    _stopList?.removeListener( _onStopListChanged );
    super.dispose();
  }

  void _onStopListChanged() {
    if ( mounted ) setState( () {} );
  }

  /// Plan §4 — a pending ask is never buried in a collapsed group.
  static String? _groupKey( ConversationMessage m ) =>
      m.responseRequested ? null : m.progressGroupId;

  /// Hide-not-delete: the bloc state keeps every message; this lens drops
  /// stop-listed ones unless the user taps the "N hidden" chip.
  List<ConversationMessage> _visible( List<ConversationMessage> all ) {
    final sl = _stopList;
    if ( sl == null || _showHidden ) return all;
    return all.where( ( m ) => !sl.matches( m.message ) ).toList();
  }

  /// Chronological (oldest→newest), STABLE on equal timestamps — the shape
  /// the group collapse wants; the render then flips it so the NEWEST is at
  /// the top (Rick 2026-08-21). Sorting ASC directly (not DESC-then-reverse)
  /// keeps tied messages in wire order instead of flipping them.
  static List<ConversationMessage> _oldestFirst( List<ConversationMessage> ms ) {
    final indexed = ms.asMap().entries.toList()
      ..sort( ( a, b ) {
        final c = a.value.timestamp.compareTo( b.value.timestamp );
        return c != 0 ? c : a.key.compareTo( b.key );   // stable on ties
      } );
    return indexed.map( ( e ) => e.value ).toList( growable: false );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar(
        title: BlocSelector<NotificationBloc, NotificationState, VoicePersona?>(
          selector: ( state ) => state is PersonaSnapshotMixin
              ? ( state as PersonaSnapshotMixin ).personaFor( widget.senderId )
              : null,
          builder: ( context, persona ) => Row(
            mainAxisSize: MainAxisSize.min,
            children    : [
              if ( persona != null ) ...[
                PersonaBadge(
                  persona  : persona,
                  senderId : widget.senderId,
                  diameter : 28,
                ),
                const SizedBox( width: 8 ),
              ],
              Flexible(
                child: Text(
                  widget.senderId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            key      : const Key( TestKeys.convDatesButton ),
            tooltip  : "Browse by date",
            icon     : const Icon( Icons.calendar_month_outlined ),
            onPressed: () async {
              final bloc = context.read<NotificationBloc>();
              await Navigator.of( context ).push( MaterialPageRoute(
                builder: ( _ ) => BlocProvider<NotificationBloc>.value(
                  value: bloc,
                  child: SenderDatesScreen(
                    senderId  : widget.senderId,
                    userEmail : widget.userEmail,
                  ),
                ),
              ) );
              if ( mounted ) {
                bloc.add( NotificationsLoadConversation(
                  senderId  : widget.senderId,
                  userEmail : widget.userEmail,
                ) );
              }
            },
          ),
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
            final visible = _visible( state.messages );
            final hidden  = state.messages.length - visible.length;
            return Column(
              children: [
                if ( hidden > 0 || _showHidden )
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB( 12, 8, 12, 0 ),
                      child: ActionChip(
                        key     : const Key( TestKeys.conversationHiddenChip ),
                        avatar  : Icon( _showHidden ? Icons.visibility_off : Icons.visibility, size: 16 ),
                        label   : Text( _showHidden
                            ? 'Hide stop-listed again'
                            : '$hidden hidden by your stop-list' ),
                        onPressed: () => setState( () => _showHidden = !_showHidden ),
                      ),
                    ),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? const Center( child: Text( "All messages here are hidden by your stop-list" ) )
                      : Builder( builder: ( context ) {
                          // Group on the chronological list (runs are contiguous
                          // in time), then flip so the newest burst is on top and
                          // each group's latest message is its summary.
                          final groups = collapseByProgressGroup<ConversationMessage>(
                            _oldestFirst( visible ), _groupKey,
                            enabled: _stopList?.collapseGroups ?? true ).reversed.toList();
                          return ListView.separated(
                            padding: const EdgeInsets.all( 12 ),
                            itemCount: groups.length,
                            separatorBuilder: ( _, __ ) => const SizedBox( height: 8 ),
                            itemBuilder: ( _, i ) {
                              final g = groups[ i ];
                              if ( !g.isCollapsed ) return _MessageCard( message: g.items.single );
                              return _CollapsedCards(
                                key   : Key( '${TestKeys.conversationGroupPrefix}${g.key}-${g.latest.id}' ),
                                count : g.count,
                                summary : _MessageCard( message: g.latest ),
                                children: [ for ( final m in g.items.reversed ) _MessageCard( message: m ) ],
                              );
                            },
                          );
                        } ),
                ),
              ],
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
              AbstractBody(
                abstractText : message.abstractText,
                repository   : ServiceLocator.instance<DocRepository>(),
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
            const SizedBox( height: 6 ),
            MessageStamp( timestamp: message.timestamp, id: message.id ),   // lower-left
          ],
        ),
      ),
    );
  }
}

/// Collapsed burst of same-progress-group cards (plan 2026.08.21 §4):
/// latest card + ×N chip; tap to expand in place.
class _CollapsedCards extends StatefulWidget {
  final int          count;
  final Widget       summary;
  final List<Widget> children;
  const _CollapsedCards( { super.key, required this.count, required this.summary, required this.children } );

  @override
  State<_CollapsedCards> createState() => _CollapsedCardsState();
}

class _CollapsedCardsState extends State<_CollapsedCards> {
  bool _expanded = false;

  @override
  Widget build( BuildContext context ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key   : Key( '${TestKeys.conversationGroupTogglePrefix}${widget.key.toString()}' ),
          onTap : () => setState( () => _expanded = !_expanded ),
          child : Row(
            children: [
              Expanded( child: _expanded ? const SizedBox.shrink() : widget.summary ),
              Padding(
                padding: const EdgeInsets.symmetric( horizontal: 8 ),
                child: Chip(
                  visualDensity : VisualDensity.compact,
                  avatar        : Icon( _expanded ? Icons.unfold_less : Icons.unfold_more, size: 14 ),
                  label         : Text( '×${widget.count}' ),
                ),
              ),
            ],
          ),
        ),
        if ( _expanded )
          for ( final c in widget.children ) Padding( padding: const EdgeInsets.only( top: 8 ), child: c ),
      ],
    );
  }
}
