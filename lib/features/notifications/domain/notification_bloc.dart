import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/notification_models.dart';
import '../data/notification_repository.dart';
import 'notification_event.dart';
import 'notification_state.dart';

/// Repository-backed inbox + conversation BLoC. Replaces the prior
/// websocket-only skeleton with real REST integration against the
/// 17-endpoint notifications API.
class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final NotificationRepository _repo;

  // Track context so external updates can refresh the right view.
  String? _activeUserEmail;
  String? _activeSenderId;

  NotificationBloc( this._repo ) : super( const NotificationsInitial() ) {
    on<NotificationsLoadInbox>( _onLoadInbox );
    on<NotificationsLoadConversation>( _onLoadConversation );
    on<NotificationsMarkPlayed>( _onMarkPlayed );
    on<NotificationsRespond>( _onRespond );
    on<NotificationsBulkDelete>( _onBulkDelete );
    on<NotificationsDeleteConversation>( _onDeleteConversation );
    on<NotificationsExternalUpdate>( _onExternalUpdate );
  }

  Future<void> _onLoadInbox(
    NotificationsLoadInbox event,
    Emitter<NotificationState> emit,
  ) async {
    _activeUserEmail = event.userEmail;
    emit( const NotificationsLoading() );
    try {
      final senders = await _repo.sendersVisible(
        event.userEmail,
        hours          : event.hours,
        includeHidden  : event.includeHidden,
        excludeOwnJobs : event.excludeOwnJobs,
      );
      emit( NotificationsInboxLoaded(
        senders   : senders,
        userEmail : event.userEmail,
      ) );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onLoadConversation(
    NotificationsLoadConversation event,
    Emitter<NotificationState> emit,
  ) async {
    _activeUserEmail = event.userEmail;
    _activeSenderId  = event.senderId;
    emit( const NotificationsLoading() );
    try {
      final messages = await _repo.conversation(
        event.senderId,
        event.userEmail,
        hours: event.hours,
      );
      emit( NotificationsConversationLoaded(
        senderId  : event.senderId,
        userEmail : event.userEmail,
        messages  : messages,
      ) );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onMarkPlayed(
    NotificationsMarkPlayed event,
    Emitter<NotificationState> emit,
  ) async {
    try {
      await _repo.markPlayed( event.notificationId );
      // Re-emit current view so badges update.
      _refreshCurrent( emit );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onRespond(
    NotificationsRespond event,
    Emitter<NotificationState> emit,
  ) async {
    emit( NotificationsResponding( event.notificationId ) );
    try {
      final ack = await _repo.respond( NotificationResponsePayload(
        notificationId : event.notificationId,
        responseValue  : event.responseValue,
      ) );
      // Best-effort mark-played; backend already does it but keep idempotent.
      try { await _repo.markPlayed( event.notificationId ); } catch ( _ ) {}
      emit( NotificationsResponseAcked( ack ) );
      await _refreshCurrent( emit );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onBulkDelete(
    NotificationsBulkDelete event,
    Emitter<NotificationState> emit,
  ) async {
    try {
      await _repo.bulkDelete(
        event.userEmail,
        hours          : event.hours,
        excludeOwnJobs : event.excludeOwnJobs,
      );
      add( NotificationsLoadInbox( userEmail: event.userEmail ) );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onDeleteConversation(
    NotificationsDeleteConversation event,
    Emitter<NotificationState> emit,
  ) async {
    try {
      await _repo.deleteConversation( event.senderId, event.userEmail );
      add( NotificationsLoadInbox( userEmail: event.userEmail ) );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onExternalUpdate(
    NotificationsExternalUpdate _,
    Emitter<NotificationState> emit,
  ) async {
    await _refreshCurrent( emit );
  }

  /// Re-fetch the current view (inbox or conversation) without changing
  /// emit ordering. No-op if there's no tracked context yet.
  Future<void> _refreshCurrent( Emitter<NotificationState> emit ) async {
    if ( _activeUserEmail == null ) return;
    try {
      if ( _activeSenderId != null && state is NotificationsConversationLoaded ) {
        final msgs = await _repo.conversation(
          _activeSenderId!,
          _activeUserEmail!,
        );
        emit( NotificationsConversationLoaded(
          senderId  : _activeSenderId!,
          userEmail : _activeUserEmail!,
          messages  : msgs,
        ) );
      } else if ( state is NotificationsInboxLoaded ) {
        final senders = await _repo.sendersVisible( _activeUserEmail! );
        emit( NotificationsInboxLoaded(
          senders   : senders,
          userEmail : _activeUserEmail!,
        ) );
      }
    } on NotificationApiException catch ( _ ) {
      // Keep last good state silently — refresh is best-effort.
    }
  }
}
