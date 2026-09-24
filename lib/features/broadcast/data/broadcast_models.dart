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

  /// When the server recorded this ack, when it came from the saved read. Null for a
  /// live socket frame, which carries its timestamp on the notification envelope rather
  /// than in the ack itself.
  final DateTime? createdAt;

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

  /// Read an ack out of one entry of `GET /api/notifications/broadcast-acks/{id}`.
  ///
  /// 🔴 THE STATUS KEY IS `ack_status` HERE AND `status` ON THE SOCKET FRAME, AND THAT
  /// ONE LETTER-FOR-LETTER DIFFERENCE IS THE TRAP IN THIS WHOLE READ. The server lifts
  /// the identity fields OUT of `payload` onto the envelope and renames `payload.status`
  /// to `ack_status` on the way (`_project_broadcast_ack`, `notifications.py:2398-2422`),
  /// because the envelope already has a `state` of its own. A reader that reuses the
  /// socket parser finds no `status`, reports every recovered ack with a null one, and
  /// looks like it worked — the tally is even the right SIZE.
  ///
  /// Requires:
  ///   - json is one element of the response's `acks` list, NOT a notification
  ///
  /// Ensures:
  ///   - returns null unless `broadcast_id` is present and non-empty
  ///   - never throws on a malformed row: an ack whose payload was null projects every
  ///     identity field as null server-side, and that row is dropped here rather than
  ///     taking the whole read down with it
  static BroadcastAck? fromSavedAck( Map<String, dynamic> json ) {
    final id = json[ 'broadcast_id' ]?.toString();
    if ( id == null || id.isEmpty ) return null;

    return BroadcastAck(
      broadcastId  : id,
      sessionId    : json[ 'session_id' ]?.toString() ?? '',
      personaName  : json[ 'persona_name' ]?.toString(),
      personaIcon  : json[ 'persona_icon' ]?.toString(),
      personaColor : json[ 'persona_color' ]?.toString(),
      // `ack_status`, not `status`. See the note above.
      status       : json[ 'ack_status' ]?.toString(),
      bodySummary  : json[ 'body_summary' ]?.toString() ?? '',
      createdAt    : DateTime.tryParse( json[ 'created_at' ]?.toString() ?? '' ),
    );
  }

  String get label => personaName ?? sessionId;

  @override
  List<Object?> get props =>
      [ broadcastId, sessionId, personaName, personaIcon, personaColor, status,
        bodySummary, createdAt ];
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
  /// ⚠️ THIS IS NO LONGER PERMANENT, AND THE PARAGRAPH THAT SAID IT WAS HAS BEEN DELETED
  /// RATHER THAN SOFTENED. It read: "the missed ones are not recoverable… it is permanent
  /// for this broadcast." True of `/api/notifications/undelivered`, which is what it was
  /// written about, and false the day `GET /api/notifications/broadcast-acks/{id}` landed
  /// (lupin row `1c7da903`). A recovery read that succeeds moves the tally to
  /// [AckConfidence.recovered]; this value means the read has not happened or did not
  /// answer.
  interrupted,

  /// The listening window broke AND the saved acks were read back, so the tally is the
  /// server's own latest-per-seat answer as of that read.
  ///
  /// 🔴 THIS IS NOT THE SAME CLAIM AS [observed], AND COLLAPSING THEM WOULD THROW AWAY
  /// THE ONE FACT THE OPERATOR ACTUALLY NEEDS. `observed` says nothing was missed
  /// because nothing could have been. This says something WAS missed and then went and
  /// fetched it. The counts can be identical and the sentences must not be, because a
  /// recovered tally is current as of a moment in the past, while an observed one is
  /// current now.
  recovered,
}

/// How a broadcast's ack collection ended up — the question a recovered tally can
/// finally answer and an interrupted one never could.
///
/// 🔴 EXPIRED AND PARTIAL ARE DIFFERENT INSTRUCTIONS TO THE OPERATOR, WHICH IS THE WHOLE
/// REASON THEY ARE NOT ONE VALUE. `partial` means keep the pane open, more acks are
/// plausibly still coming. `expired` means the seats that have not answered are not
/// going to, and chasing them is the next move. Rendering both as "3 of 5 acked" leaves
/// the operator to guess which one they are looking at, and they will guess wrong at
/// exactly the moment it matters — right after a resume, when the tally has just moved.
enum AckOutcome {
  /// Every seat the server enumerated has acked.
  complete,

  /// Fewer acks than recipients, and the window is still open.
  partial,

  /// Fewer acks than recipients, and the window has closed. The missing seats are
  /// missing for good.
  expired,
}

/// The running tally for one broadcast.
///
/// ⚠️ IT DELIBERATELY HAS NO "EXPECTED" DENOMINATOR IN ITS RENDERED FORM. "2 of 14" is
/// the precise-looking lie this whole phase was written around: after a resume it reads
/// as twelve seats ignoring the operator, when what actually happened is that the phone
/// was not listening. The recipient count is kept because the confirm modal needs it
/// BEFORE the send; it is not used to manufacture a fraction afterwards.
class AckAggregate extends Equatable {
  /// How long after the send a missing ack stops being "not yet" and becomes "never".
  ///
  /// ⚠️ THE WEB'S FIVE MINUTES, MEASURED FROM A DIFFERENT MOMENT, AND THE DIVERGENCE IS
  /// DELIBERATE. `broadcast-panel.js` starts its `AUTO_DISMISS_MS` timer on the FIRST ack
  /// and restarts it on every one after — so a broadcast nobody acks at all never times
  /// out there, and sits as "0/5 complete" forever. Measuring from the send instead
  /// expires the silent case too, which is the case a phone actually produces: the app
  /// was backgrounded the whole time and there was never a first ack to start a clock.
  static const ackWindow = Duration( minutes: 5 );

  final String broadcastId;

  /// Recipients the server said it queued to, at send time.
  final int recipientsAtSend;

  /// Acks actually seen, keyed by session so a duplicate frame cannot inflate the tally.
  final Map<String, BroadcastAck> acksBySession;

  final AckConfidence confidence;

  /// When the send was accepted. Null when the caller did not record it, and then this
  /// tally never claims [AckOutcome.expired] — an unknown clock is not an elapsed one.
  final DateTime? sentAt;

  const AckAggregate( {
    required this.broadcastId,
    required this.recipientsAtSend,
    this.acksBySession = const {},
    this.confidence    = AckConfidence.observed,
    this.sentAt,
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
      sentAt           : sentAt,
      acksBySession    : { ...acksBySession, ack.sessionId : ack },
      // 🔴 FOLDING NEVER RESTORES CONFIDENCE. An ack arriving after a reconnect proves
      // the socket is back; it proves nothing about the ones pushed while it was down.
      // Letting a later arrival clear the flag would quietly re-manufacture the exact
      // false precision this type exists to prevent.
      confidence       : confidence,
    );
  }

  /// Mark the listening window as broken.
  ///
  /// ⚠️ NO LONGER ONE-WAY — [reconciled] is the way back, and only a successful read of
  /// the saved acks can take it. Folding a late socket frame still cannot (see [fold]).
  AckAggregate interrupted() {
    return AckAggregate(
      broadcastId      : broadcastId,
      recipientsAtSend : recipientsAtSend,
      sentAt           : sentAt,
      acksBySession    : acksBySession,
      confidence       : AckConfidence.interrupted,
    );
  }

  /// Merge the server's saved acks in, and stop apologising for a gap that has been
  /// filled.
  ///
  /// 🔴 THE SAVED ACK WINS FOR ITS SEAT, AND THAT IS THE LATEST-WINS RULE, NOT A
  /// PREFERENCE FOR THE NETWORK. `get_latest_acks_for_broadcast` folds the rows to one
  /// per session, newest first, before they leave the server
  /// (`notification_repository.py:653-720`). So for any seat this read names, the row it
  /// carries IS that seat's latest ack as of the read — later than the live frame we may
  /// be holding, which is frequently a `pending` that has since become `completed`.
  /// Keeping the live one instead would show a stale status beside a current count.
  ///
  /// A seat the read does NOT name keeps whatever we saw live: the read raced it, and
  /// dropping it would be a recovery that loses acks.
  ///
  /// Requires:
  ///   - saved is the list from [BroadcastRepository.drainMissedAcks]
  ///
  /// Ensures:
  ///   - acks whose broadcastId is not this one are IGNORED — one seat, one pane, and
  ///     the socket delivers other broadcasts' acks to the same client
  ///   - keying is per seat, so an ack already counted live is not counted twice
  ///   - an empty read is not a failure: confidence still improves, because "nobody
  ///     acked" is an answer the server gave us (`notifications.py:2453-2456`)
  ///   - confidence becomes [AckConfidence.recovered] only if it was
  ///     [AckConfidence.interrupted]; an already-[AckConfidence.observed] tally is not
  ///     demoted to a claim about a past moment
  AckAggregate reconciled( Iterable<BroadcastAck> saved ) {
    final merged = Map<String, BroadcastAck>.from( acksBySession );
    for ( final ack in saved ) {
      if ( ack.broadcastId != broadcastId ) continue;
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

  /// Complete, still open, or closed with seats missing.
  ///
  /// Requires:
  ///   - now is the moment to judge against; injected so a test does not have to sleep
  ///
  /// Ensures:
  ///   - returns [AckOutcome.complete] when every enumerated recipient has acked
  ///   - returns [AckOutcome.expired] only when [sentAt] is known AND [ackWindow] has
  ///     elapsed — an unknown send time is never treated as an elapsed one
  ///   - otherwise returns [AckOutcome.partial]
  AckOutcome outcomeAt( DateTime now ) {
    if ( recipientsAtSend > 0 && ackedCount >= recipientsAtSend ) return AckOutcome.complete;

    final sent = sentAt;
    if ( sent != null && now.difference( sent ) >= ackWindow ) return AckOutcome.expired;

    return AckOutcome.partial;
  }

  /// ⚠️ EVALUATED AT BUILD TIME, AND NOTHING SCHEDULES A REBUILD AT THE BOUNDARY. A pane
  /// held in the foreground, untouched, across the five-minute mark keeps showing
  /// `partial` until the next emit — an ack, a resume, a reconnect. Every one of those is
  /// also the moment the operator comes back to the screen, so in practice the sentence
  /// is current whenever it is being read. A timer was NOT added for it: this bloc has
  /// none by design, and the one case it would cover is a screen nobody is looking at.
  AckOutcome get outcome => outcomeAt( DateTime.now() );

  @override
  List<Object?> get props =>
      [ broadcastId, recipientsAtSend, acksBySession, confidence, sentAt ];

  /// The sentence the pane shows. A statement about the attempt, never about the world.
  ///
  /// Requires:
  ///   - now is the moment to judge the window against
  ///
  /// Ensures:
  ///   - when confidence is [AckConfidence.interrupted] the text says acks could not be
  ///     confirmed and never presents the tally as exact
  ///   - the word "of" followed by a denominator never appears in the interrupted form
  ///   - an interrupted tally is NEVER described as complete, whatever the counts say,
  ///     because a floor that happens to reach the denominator is still a floor
  ///   - a recovered tally says where its number came from, and an expired one says the
  ///     missing seats are not coming
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
        // The web's "K timed out", in words a phone screen can carry. This is the one
        // arm that tells the operator to go chase somebody.
        return '$ackedCount of $recipientsAtSend acked — $missing did not answer in time.';

      case AckOutcome.partial:
        return recovered
            ? '$ackedCount of $recipientsAtSend acked — read back after the app stopped listening.'
            : '$ackedCount of $recipientsAtSend acked';
    }
  }

  String get summary => summaryAt( DateTime.now() );
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
