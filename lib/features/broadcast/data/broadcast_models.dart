import 'package:equatable/equatable.dart';

/// One live Claude Code session — a potential recipient.
///
/// The roster's LENGTH is half the Send button's enabled condition, so this type exists
/// mostly to be counted. The persona fields are carried because the confirm modal shows
/// chips, not a bare number: "send to 3 sessions" and "send to Tiffany, María, Mr Radio"
/// are different amounts of information at the moment someone is about to interrupt the
/// whole fleet.
class ActiveSession extends Equatable {
  final String  sessionId;
  final String? senderId;
  final String? personaName;
  final String? personaIcon;
  final String? personaColor;
  final String? lastSeenIso;
  final bool    speakerphoneOn;

  const ActiveSession( {
    required this.sessionId,
    this.senderId,
    this.personaName,
    this.personaIcon,
    this.personaColor,
    this.lastSeenIso,
    this.speakerphoneOn = false,
  } );

  /// Build from one entry of `GET /api/commons/active-sessions`.
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

  /// What the confirm modal puts on a chip.
  String get label => personaName ?? sessionId;

  @override
  List<Object?> get props =>
      [ sessionId, senderId, personaName, personaIcon, personaColor, lastSeenIso, speakerphoneOn ];
}

/// The recipient roster.
///
/// ⚠️ AN EMPTY ROSTER IS A LEGITIMATE ANSWER, NOT AN ERROR. Nobody being online is the
/// ordinary state at 3am, and it is the exact case the Send button's second condition
/// exists for. A roster that threw on empty would turn "nobody is listening" into a
/// failure banner and lose the distinction.
class ActiveSessionRoster extends Equatable {
  final List<ActiveSession> sessions;

  const ActiveSessionRoster( this.sessions );

  const ActiveSessionRoster.empty() : sessions = const [];

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

  int  get count   => sessions.length;
  bool get isEmpty => sessions.isEmpty;

  @override
  List<Object?> get props => [ sessions ];
}

/// What the server said when the broadcast was accepted.
///
/// 🔴 `status == 'queued'` IS NOT A DELIVERY RECEIPT, and reading it as one is the same
/// hazard the 202 sentinel exists for on the task panes — the pane paints a thing done
/// that the server only accepted. [failedRecipients] is the field that says otherwise and
/// it is why this type is not just an int.
class BroadcastSendResult extends Equatable {
  final String       broadcastId;
  final int          recipients;
  final List<String> failedRecipients;
  final List<String> filteredOut;
  final String       status;

  const BroadcastSendResult( {
    required this.broadcastId,
    required this.recipients,
    required this.failedRecipients,
    required this.filteredOut,
    required this.status,
  } );

  factory BroadcastSendResult.fromJson( Map<String, dynamic> json ) {
    return BroadcastSendResult(
      broadcastId      : json[ 'broadcast_id' ]?.toString() ?? '',
      recipients       : ( json[ 'recipients' ] as num? )?.toInt() ?? 0,
      failedRecipients : _stringList( json[ 'failed_recipients' ] ),
      filteredOut      : _stringList( json[ 'filtered_out' ] ),
      status           : json[ 'status' ]?.toString() ?? '',
    );
  }

  /// The server enumerated nobody to send to. Distinct from a failure: the request was
  /// accepted and simply had no addressees.
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
/// 🔴 EVERY FIELD THAT MAKES AN ACK AN ACK LIVES IN `payload`, AND `message` IS AN EMPTY
/// STRING BY DESIGN (`commons_ack_watcher.py`, `_push_ack_event`). A reader that goes
/// looking in `message` — which is where every OTHER notification carries its content —
/// finds nothing, reports zero acks, and looks like a quiet fleet.
class BroadcastAck extends Equatable {
  final String  broadcastId;
  final String  sessionId;
  final String? personaName;
  final String? personaIcon;
  final String? personaColor;
  final String? status;
  final String  bodySummary;

  const BroadcastAck( {
    required this.broadcastId,
    required this.sessionId,
    this.personaName,
    this.personaIcon,
    this.personaColor,
    this.status,
    this.bodySummary = '',
  } );

  /// Read an ack out of a `commons_broadcast_ack` notification's raw map.
  ///
  /// Requires:
  ///   - raw is the notification object, NOT the `notification_queue_update` envelope
  ///
  /// Ensures:
  ///   - returns null unless `type == 'commons_broadcast_ack'` AND `payload` carries a
  ///     non-empty `broadcast_id`
  ///   - never throws on a malformed frame — an unreadable ack is dropped, not fatal
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

  String get label => personaName ?? sessionId;

  @override
  List<Object?> get props =>
      [ broadcastId, sessionId, personaName, personaIcon, personaColor, status, bodySummary ];
}

/// Why an ack tally cannot be trusted to be complete.
///
/// 🔴 THIS ENUM IS THE ACCEPTANCE CLAUSE. Each value is a statement about what THIS
/// ATTEMPT observed, never about how the world is. That wording was settled on store row
/// `384591dd` after the clause went through three wrong shapes, and the reason is that a
/// pane outlives the condition that made its sentence true: "acks are unavailable by
/// design" becomes a silent lie the day the two stores are bridged, whereas "acks could
/// not be confirmed" simply stops firing.
enum AckConfidence {
  /// Every ack that has arrived, arrived while we were listening. The tally is what we
  /// saw and we have no reason to think we missed any.
  observed,

  /// The socket was not connected for part of this broadcast's life, so acks may have
  /// been pushed at nobody. The tally is a FLOOR, not a count.
  ///
  /// ⚠️ AND THE MISSED ONES ARE NOT RECOVERABLE. They are not in
  /// `/api/notifications/undelivered`, and the io_tbl row written for an ack carries a
  /// type label and an empty string — `payload` is never passed to it. So this is not a
  /// "refresh to find out": it is permanent for this broadcast.
  interrupted,
}

/// The running tally for one broadcast.
///
/// ⚠️ IT DELIBERATELY HAS NO "EXPECTED" DENOMINATOR IN ITS RENDERED FORM. "2 of 14" is
/// the precise-looking lie this whole phase was written around: after a resume it reads
/// as twelve seats ignoring the operator, when what actually happened is that the phone
/// was not listening. The recipient count is kept because the confirm modal needs it
/// BEFORE the send; it is not used to manufacture a fraction afterwards.
class AckAggregate extends Equatable {
  final String broadcastId;

  /// Recipients the server said it queued to, at send time.
  final int recipientsAtSend;

  /// Acks actually seen, keyed by session so a duplicate frame cannot inflate the tally.
  final Map<String, BroadcastAck> acksBySession;

  final AckConfidence confidence;

  const AckAggregate( {
    required this.broadcastId,
    required this.recipientsAtSend,
    this.acksBySession = const {},
    this.confidence    = AckConfidence.observed,
  } );

  int                get ackedCount => acksBySession.length;
  List<BroadcastAck> get acks       => acksBySession.values.toList();

  /// Fold one ack in. Idempotent per session — the same frame twice is one ack.
  ///
  /// Requires:
  ///   - ack.broadcastId identifies some broadcast; acks for OTHER broadcasts are ignored
  ///
  /// Ensures:
  ///   - an ack for a different broadcastId returns this aggregate unchanged
  ///   - confidence is never improved by folding: an interrupted tally stays interrupted
  AckAggregate fold( BroadcastAck ack ) {
    if ( ack.broadcastId != broadcastId ) return this;

    return AckAggregate(
      broadcastId      : broadcastId,
      recipientsAtSend : recipientsAtSend,
      acksBySession    : { ...acksBySession, ack.sessionId : ack },
      // 🔴 FOLDING NEVER RESTORES CONFIDENCE. An ack arriving after a reconnect proves
      // the socket is back; it proves nothing about the ones pushed while it was down.
      // Letting a later arrival clear the flag would quietly re-manufacture the exact
      // false precision this type exists to prevent.
      confidence       : confidence,
    );
  }

  /// Mark the listening window as broken. One-way.
  AckAggregate interrupted() {
    return AckAggregate(
      broadcastId      : broadcastId,
      recipientsAtSend : recipientsAtSend,
      acksBySession    : acksBySession,
      confidence       : AckConfidence.interrupted,
    );
  }

  @override
  List<Object?> get props => [ broadcastId, recipientsAtSend, acksBySession, confidence ];

  /// The sentence the pane shows. A statement about the attempt, never about the world.
  ///
  /// Ensures:
  ///   - when confidence is [AckConfidence.interrupted] the text says acks could not be
  ///     confirmed and never presents the tally as exact
  ///   - the word "of" followed by a denominator never appears in the interrupted form
  String get summary {
    if ( confidence == AckConfidence.interrupted ) {
      return ackedCount == 0
          ? 'Acks could not be confirmed — the app was not listening for part of this broadcast.'
          : 'At least $ackedCount acked — acks could not be confirmed after the app stopped listening.';
    }
    return '$ackedCount of $recipientsAtSend acked';
  }
}

/// One read of recent broadcast history.
///
/// 🔴 [disabled] IS NOT THE SAME ANSWER AS AN EMPTY [entries]. The server's kill switch
/// answers `disabled: true`; a quiet fleet answers an empty list. Collapsing the two
/// told the operator "nothing happened" when the truth was "you turned this off"
/// (row a3ebeb18, 2026-09-23).
class BroadcastHistory extends Equatable {
  final bool disabled;
  final List<Map<String, dynamic>> entries;

  const BroadcastHistory( { this.disabled = false, this.entries = const [] } );

  @override
  List<Object?> get props => [ disabled, entries ];
}
