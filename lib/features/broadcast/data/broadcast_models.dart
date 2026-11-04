import 'package:equatable/equatable.dart';

/// One live Claude Code session, a potential recipient of a broadcast.
///
/// The roster's length is half the Send button's enabled condition. The persona fields are
/// carried because the confirm modal shows chips, not a bare number. "Send to 3 sessions"
/// and "send to Tiffany, María, Mr Radio" differ in information, when someone is about to
/// interrupt the whole fleet.
class ActiveSession extends Equatable {
  /// The session id.
  final String  sessionId;

  /// The sender id, `<address>#<8hex>`.
  final String? senderId;

  /// The persona name.
  final String? personaName;

  /// The persona's icon.
  final String? personaIcon;

  /// The persona's colour.
  final String? personaColor;

  /// When the server last saw the session, as an ISO timestamp.
  final String? lastSeenIso;

  /// Whether the session has speakerphone on.
  final bool    speakerphoneOn;

  /// Creates a session.
  const ActiveSession( {
    required this.sessionId,
    this.senderId,
    this.personaName,
    this.personaIcon,
    this.personaColor,
    this.lastSeenIso,
    this.speakerphoneOn = false,
  } );

  /// Builds a session from one entry of `GET /api/commons/active-sessions`.
  ///
  /// Requires:
  ///   - json is one element of the response's `sessions` list
  ///
  /// Ensures:
  ///   - sessionId is non-null, falling back to the empty string
  ///   - every other field preserves its absent-ness as null rather than a placeholder
  factory ActiveSession.fromJson( Map<String, dynamic> json ) {
    return ActiveSession(
      sessionId      : json[ 'session_id' ]?.toString() ?? '',
      senderId       : json[ 'sender_id' ]?.toString(),
      personaName    : json[ 'persona_name' ]?.toString(),
      personaIcon    : json[ 'persona_icon' ]?.toString(),
      personaColor   : json[ 'persona_color' ]?.toString(),
      lastSeenIso    : json[ 'last_seen_iso' ]?.toString(),
      speakerphoneOn : json[ 'speakerphone_on' ] == true,
    );
  }

  /// What the confirm modal puts on a chip: the persona name, else the session id.
  String get label => personaName ?? sessionId;

  @override
  List<Object?> get props =>
      [ sessionId, senderId, personaName, personaIcon, personaColor, lastSeenIso, speakerphoneOn ];
}

/// The recipient roster.
///
/// An empty roster is a legitimate answer, not an error. Nobody online is the ordinary state
/// at 3am, and it is the case the Send button's second condition exists for. A roster that
/// threw on empty would turn "nobody is listening" into a failure banner.
class ActiveSessionRoster extends Equatable {
  /// The live sessions.
  final List<ActiveSession> sessions;

  /// Creates a roster.
  const ActiveSessionRoster( this.sessions );

  /// An empty roster.
  const ActiveSessionRoster.empty() : sessions = const [];

  /// Parses the response body; a missing or malformed `sessions` yields an empty roster.
  factory ActiveSessionRoster.fromJson( Map<String, dynamic> json ) {
    final raw = json[ 'sessions' ];
    if ( raw is! List ) return const ActiveSessionRoster.empty();

    return ActiveSessionRoster(
      raw
          .whereType<Map>()
          .map( ( e ) => ActiveSession.fromJson( Map<String, dynamic>.from( e ) ) )
          .toList(),
    );
  }

  /// How many sessions are live.
  int  get count   => sessions.length;

  /// True when nobody is live.
  bool get isEmpty => sessions.isEmpty;

  @override
  List<Object?> get props => [ sessions ];
}

/// What the server said when the broadcast was accepted.
///
/// `status == 'queued'` is not a delivery receipt. Reading it as one repeats the mistake the
/// 202 sentinel guards against on the task panes. The pane would paint done what the server
/// only accepted. The `failedRecipients` field says otherwise, so this type is not an int.
class BroadcastSendResult extends Equatable {
  /// The id of the accepted broadcast.
  final String       broadcastId;

  /// How many recipients the server queued it to.
  final int          recipients;

  /// Recipients the server tried and could not reach.
  final List<String> failedRecipients;

  /// Recipients the server filtered out.
  final List<String> filteredOut;

  /// The server's status word, such as `queued` or `no-active-sessions`.
  final String       status;

  /// Creates a result.
  const BroadcastSendResult( {
    required this.broadcastId,
    required this.recipients,
    required this.failedRecipients,
    required this.filteredOut,
    required this.status,
  } );

  /// Parses the send response; a missing field takes an empty or zero default.
  factory BroadcastSendResult.fromJson( Map<String, dynamic> json ) {
    return BroadcastSendResult(
      broadcastId      : json[ 'broadcast_id' ]?.toString() ?? '',
      recipients       : ( json[ 'recipients' ] as num? )?.toInt() ?? 0,
      failedRecipients : _stringList( json[ 'failed_recipients' ] ),
      filteredOut      : _stringList( json[ 'filtered_out' ] ),
      status           : json[ 'status' ]?.toString() ?? '',
    );
  }

  /// True when the server enumerated nobody to send to.
  ///
  /// That is distinct from a failure: the request was accepted and had no addressees.
  bool get noActiveSessions => status == 'no-active-sessions';

  /// At least one recipient the server tried and could not reach.
  bool get hasFailures => failedRecipients.isNotEmpty;

  static List<String> _stringList( Object? raw ) {
    if ( raw is! List ) return const [];
    return raw.map( ( e ) => e.toString() ).toList();
  }

  @override
  List<Object?> get props =>
      [ broadcastId, recipients, failedRecipients, filteredOut, status ];
}

/// One seat's acknowledgement of one broadcast.
///
/// Every field that makes an ack an ack lives in `payload`, and `message` is always an empty
/// string. A reader that looks in `message`, where every other notification carries its
/// content, finds nothing. It then reports zero acks and looks like a quiet fleet.
class BroadcastAck extends Equatable {
  /// The broadcast acknowledged.
  final String  broadcastId;

  /// The acknowledging session.
  final String  sessionId;

  /// The persona name.
  final String? personaName;

  /// The persona's icon.
  final String? personaIcon;

  /// The persona's colour.
  final String? personaColor;

  /// The ack's status, such as `pending` or `completed`.
  final String? status;

  /// A short summary of the ack's body; empty when none.
  final String  bodySummary;

  /// When the server recorded this ack, when it came from the saved read.
  ///
  /// It is null for a live socket frame, which carries its timestamp on the notification
  /// envelope and not in the ack.
  final DateTime? createdAt;

  /// Creates an ack.
  const BroadcastAck( {
    required this.broadcastId,
    required this.sessionId,
    this.personaName,
    this.personaIcon,
    this.personaColor,
    this.status,
    this.bodySummary = '',
    this.createdAt,
  } );

  /// Reads an ack out of a `commons_broadcast_ack` notification's raw map.
  ///
  /// Requires:
  ///   - raw is the notification object, not the `notification_queue_update` envelope
  ///
  /// Ensures:
  ///   - returns null unless `type == 'commons_broadcast_ack'` and `payload` carries a
  ///     non-empty `broadcast_id`
  ///   - never throws on a malformed frame; an unreadable ack is dropped, not fatal
  static BroadcastAck? fromNotification( Map<String, dynamic> raw ) {
    if ( raw[ 'type' ]?.toString() != 'commons_broadcast_ack' ) return null;

    final payload = raw[ 'payload' ];
    if ( payload is! Map ) return null;

    final p  = Map<String, dynamic>.from( payload );
    final id = p[ 'broadcast_id' ]?.toString();
    if ( id == null || id.isEmpty ) return null;

    return BroadcastAck(
      broadcastId  : id,
      sessionId    : p[ 'session_id' ]?.toString() ?? '',
      personaName  : p[ 'persona_name' ]?.toString(),
      personaIcon  : p[ 'persona_icon' ]?.toString(),
      personaColor : p[ 'persona_color' ]?.toString(),
      status       : p[ 'status' ]?.toString(),
      bodySummary  : p[ 'body_summary' ]?.toString() ?? '',
    );
  }

  /// Reads an ack out of one entry of `GET /api/notifications/broadcast-acks/{id}`.
  ///
  /// The status key is `ack_status` here and `status` on the socket frame, because the
  /// server renames it. A reader reusing the socket parser reports every recovered ack with
  /// a null status and looks as if it worked.
  ///
  /// Requires:
  ///   - json is one element of the response's `acks` list, not a notification
  ///
  /// Ensures:
  ///   - returns null unless `broadcast_id` is present and non-empty
  ///   - never throws on a malformed row: an ack whose payload was null projects every
  ///     identity field as null on the server, and that row is dropped here instead of
  ///     taking the whole read down
  static BroadcastAck? fromSavedAck( Map<String, dynamic> json ) {
    final id = json[ 'broadcast_id' ]?.toString();
    if ( id == null || id.isEmpty ) return null;

    return BroadcastAck(
      broadcastId  : id,
      sessionId    : json[ 'session_id' ]?.toString() ?? '',
      personaName  : json[ 'persona_name' ]?.toString(),
      personaIcon  : json[ 'persona_icon' ]?.toString(),
      personaColor : json[ 'persona_color' ]?.toString(),
      // `ack_status`, not `status`; see the doc above.
      status       : json[ 'ack_status' ]?.toString(),
      bodySummary  : json[ 'body_summary' ]?.toString() ?? '',
      createdAt    : DateTime.tryParse( json[ 'created_at' ]?.toString() ?? '' ),
    );
  }

  /// What the pane shows for the seat: the persona name, else the session id.
  String get label => personaName ?? sessionId;

  @override
  List<Object?> get props =>
      [ broadcastId, sessionId, personaName, personaIcon, personaColor, status,
        bodySummary, createdAt ];
}

/// Why an ack tally cannot be trusted to be complete.
///
/// Each value is a statement about what this attempt observed, never about how the world
/// is. A pane outlives the condition that made its sentence true. "Acks are unavailable by
/// design" becomes a silent lie once the two stores are bridged. "Acks could not be
/// confirmed" simply stops firing.
/// Design: src/docs/decisions/README.md (R-BC-ack-confidence)
enum AckConfidence {
  /// Every ack that has arrived, arrived while we were listening.
  ///
  /// The tally is what we saw, and there is no reason to think any were missed.
  observed,

  /// The socket was down for part of the broadcast, so acks may have gone unheard.
  ///
  /// The tally is a floor, not a count. It is not permanent. A recovery read that succeeds
  /// moves the tally to [recovered]. This value means the read has not happened or did not
  /// answer.
  interrupted,

  /// The window broke and the saved acks were read back; the tally is the server's answer.
  ///
  /// This is the server's own latest-per-seat answer as of that read. It is not the same
  /// claim as [observed]. Observed says nothing was missed, because nothing could have been.
  /// Recovered says something was missed and then fetched. The counts can match and the
  /// sentences must not, because a recovered tally is current as of a past moment.
  recovered,
}

/// How a broadcast's ack collection ended up.
///
/// Expired and partial are different instructions to the operator, so they are two values.
/// Partial means keep the pane open, since more acks may still come. Expired means the seats
/// that have not answered will not, and chasing them is the next move. Rendering both as
/// "3 of 5 acked" leaves the operator to guess, at the moment right after a resume.
enum AckOutcome {
  /// Every seat the server enumerated has acked.
  complete,

  /// Fewer acks than recipients, and the window is still open.
  partial,

  /// Fewer acks than recipients, and the window has closed; the missing seats are gone.
  expired,
}

/// The running tally for one broadcast.
///
/// Its rendered form has no "expected" denominator. "2 of 14" is a precise-looking lie:
/// after a resume it reads as twelve seats ignoring the operator, when the phone was not
/// listening. The recipient count is kept because the confirm modal needs it before the
/// send. It is not used afterwards to manufacture a fraction.
class AckAggregate extends Equatable {
  /// How long after the send a missing ack stops being "not yet" and becomes "never".
  ///
  /// It is the web's five minutes, measured from a different moment. `broadcast-panel.js`
  /// starts its `AUTO_DISMISS_MS` timer on the first ack and restarts it on each ack. A
  /// broadcast nobody acks therefore never times out there and sits as "0/5 complete"
  /// forever. Measuring from the send also expires the silent case. A phone produces that
  /// case when it was backgrounded the whole time and no first ack started a clock.
  static const ackWindow = Duration( minutes: 5 );

  /// The broadcast this tally belongs to.
  final String broadcastId;

  /// Recipients the server said it queued to, at send time.
  final int recipientsAtSend;

  /// Acks actually seen, keyed by session so a duplicate frame cannot inflate the tally.
  final Map<String, BroadcastAck> acksBySession;

  /// How far the tally can be trusted to be complete.
  final AckConfidence confidence;

  /// When the send was accepted.
  ///
  /// Null when the caller did not record it, and then this tally never claims
  /// [AckOutcome.expired], because an unknown clock is not an elapsed one.
  final DateTime? sentAt;

  /// Creates a tally.
  const AckAggregate( {
    required this.broadcastId,
    required this.recipientsAtSend,
    this.acksBySession = const {},
    this.confidence    = AckConfidence.observed,
    this.sentAt,
  } );

  /// How many seats have acked.
  int                get ackedCount => acksBySession.length;

  /// The acks seen, one per seat.
  List<BroadcastAck> get acks       => acksBySession.values.toList();

  /// Folds one ack in; idempotent per session, so the same frame twice is one ack.
  ///
  /// Folding never restores confidence. An ack arriving after a reconnect proves the socket
  /// is back and nothing about the ones pushed while it was down. Letting it clear the flag
  /// would re-create the false precision this type exists to prevent.
  ///
  /// Ensures:
  ///   - an ack for a different broadcastId returns this aggregate unchanged
  ///   - confidence is never improved by folding: an interrupted tally stays interrupted
  AckAggregate fold( BroadcastAck ack ) {
    if ( ack.broadcastId != broadcastId ) return this;

    return AckAggregate(
      broadcastId      : broadcastId,
      recipientsAtSend : recipientsAtSend,
      sentAt           : sentAt,
      acksBySession    : { ...acksBySession, ack.sessionId : ack },
      // Confidence is carried over unchanged; see the doc above.
      confidence       : confidence,
    );
  }

  /// Marks the listening window as broken.
  ///
  /// It is not one-way: [reconciled] is the way back, and only a successful read of the saved
  /// acks can take it. Folding a late socket frame cannot.
  AckAggregate interrupted() {
    return AckAggregate(
      broadcastId      : broadcastId,
      recipientsAtSend : recipientsAtSend,
      sentAt           : sentAt,
      acksBySession    : acksBySession,
      confidence       : AckConfidence.interrupted,
    );
  }

  /// Merges the server's saved acks in, lifting an interrupted tally to recovered.
  ///
  /// The saved ack wins for its seat: the server folds rows to one per session, newest
  /// first. A seat the read does not name keeps its live ack, because the read raced it.
  /// Design: src/docs/decisions/README.md (R-BC-ack-confidence)
  ///
  /// Requires:
  ///   - saved is the list from [BroadcastRepository.drainMissedAcks]
  ///
  /// Ensures:
  ///   - acks for another broadcast are ignored, since the socket delivers them here too
  ///   - keying is per seat, so an ack already counted live is not counted twice
  ///   - an empty read still improves confidence, since "nobody acked" is an answer
  ///   - confidence becomes [AckConfidence.recovered] only if it was
  ///     [AckConfidence.interrupted]; an observed tally is not demoted
  ///   - a seat named in [keepLive] keeps what this aggregate already holds
  ///   - [keepLive] is the one exception to saved-wins: a seat that acks while the read is
  ///     in flight is newer than the response, so saved-wins would roll `completed` back
  ///     to the `pending` held when asked
  AckAggregate reconciled(
    Iterable<BroadcastAck> saved, {
    Set<String> keepLive = const {},
  } ) {
    final merged = Map<String, BroadcastAck>.from( acksBySession );
    for ( final ack in saved ) {
      if ( ack.broadcastId != broadcastId ) continue;
      if ( keepLive.contains( ack.sessionId ) ) continue;
      merged[ ack.sessionId ] = ack;
    }

    return AckAggregate(
      broadcastId      : broadcastId,
      recipientsAtSend : recipientsAtSend,
      sentAt           : sentAt,
      acksBySession    : merged,
      confidence       : confidence == AckConfidence.interrupted
          ? AckConfidence.recovered
          : confidence,
    );
  }

  /// Judges whether the broadcast is complete, still open, or closed with seats missing.
  ///
  /// Requires:
  ///   - now is the moment to judge against, injected so a test does not have to sleep
  ///
  /// Ensures:
  ///   - returns [AckOutcome.complete] when every enumerated recipient has acked
  ///   - returns [AckOutcome.expired] only when [sentAt] is known and [ackWindow] has
  ///     elapsed, since an unknown send time is never an elapsed one
  ///   - otherwise returns [AckOutcome.partial]
  AckOutcome outcomeAt( DateTime now ) {
    if ( recipientsAtSend > 0 && ackedCount >= recipientsAtSend ) return AckOutcome.complete;

    final sent = sentAt;
    if ( sent != null && now.difference( sent ) >= ackWindow ) return AckOutcome.expired;

    return AckOutcome.partial;
  }

  /// The outcome as of now.
  ///
  /// It is evaluated at build time and nothing schedules a rebuild at the boundary. A pane
  /// left in the foreground across the five-minute mark shows `partial` until the next emit,
  /// which is an ack, a resume or a reconnect. Each of those is also when the operator
  /// returns to the screen, so the sentence is current whenever it is read. No timer was added
  /// because this bloc has none and the case it would cover is a screen nobody is looking at.
  AckOutcome get outcome => outcomeAt( DateTime.now() );

  @override
  List<Object?> get props =>
      [ broadcastId, recipientsAtSend, acksBySession, confidence, sentAt ];

  /// The sentence the pane shows: a statement about the attempt, never about the world.
  ///
  /// Requires:
  ///   - now is the moment to judge the window against
  ///
  /// Ensures:
  ///   - an interrupted tally says acks could not be confirmed and never presents the tally
  ///     as exact
  ///   - the word "of" followed by a denominator never appears in the interrupted form
  ///   - an interrupted tally is never described as complete, whatever the counts say,
  ///     because a floor that reaches the denominator is still a floor
  ///   - a recovered tally says where its number came from
  ///   - an expired tally says the missing seats are not coming
  String summaryAt( DateTime now ) {
    if ( confidence == AckConfidence.interrupted ) {
      return ackedCount == 0
          ? 'Acks could not be confirmed — the app was not listening for part of this broadcast.'
          : 'At least $ackedCount acked — acks could not be confirmed after the app stopped listening.';
    }

    final missing   = recipientsAtSend - ackedCount;
    final recovered = confidence == AckConfidence.recovered;

    switch ( outcomeAt( now ) ) {
      case AckOutcome.complete:
        return recovered
            ? 'All $recipientsAtSend acked — read back after the app stopped listening.'
            : '$ackedCount of $recipientsAtSend acked';

      case AckOutcome.expired:
        // The web's "K timed out", in words a phone screen can carry; this is the one arm
        // that tells the operator to chase somebody.
        return '$ackedCount of $recipientsAtSend acked — $missing did not answer in time.';

      case AckOutcome.partial:
        return recovered
            ? '$ackedCount of $recipientsAtSend acked — read back after the app stopped listening.'
            : '$ackedCount of $recipientsAtSend acked';
    }
  }

  /// The sentence the pane shows as of now.
  String get summary => summaryAt( DateTime.now() );
}

/// One read of recent broadcast history.
///
/// [disabled] is not the same answer as an empty [entries]. The server's kill switch
/// answers `disabled: true` and a quiet fleet answers an empty list. Collapsing the two
/// told the operator "nothing happened" when the truth was "you turned this off".
class BroadcastHistory extends Equatable {
  /// True when the server's kill switch has the history disabled.
  final bool disabled;

  /// The history entries, as the server sent them.
  final List<Map<String, dynamic>> entries;

  /// Creates a history read.
  const BroadcastHistory( { this.disabled = false, this.entries = const [] } );

  @override
  List<Object?> get props => [ disabled, entries ];
}
