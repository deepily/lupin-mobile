/// The watchable-roster projection — §3's admin-gated read of
/// `/api/arbiter/fleet-state` plus the three fields fleet-state cannot carry.
///
/// 🔴 THIS IS A SECOND SURFACE, NOT A FIELD ON THE ONE THE PANE ALREADY POLLS, and an
/// earlier revision of the plan said otherwise. `/api/arbiter/fleet-state` is a verbatim
/// reverse-proxy of the standalone arbiter's `:8001/state` body, gated
/// `require_api_key_or_jwt` — authenticated, **not** admin. It therefore cannot carry a
/// per-caller field, and `transcript_watchable` is per-caller by ruling Q5. So the
/// projection computes all three on the way out and carries its own `require_admin`;
/// the fleet pane keeps polling fleet-state exactly as before.
/// (§5, corrected by F-Clayton-C4.)
///
/// ⚠️ EVERY FAILURE READS AS "NOT WATCHABLE", AND THAT DIRECTION IS THE WHOLE DESIGN.
/// A missing field, a missing row, a 403, an older server that has never heard of the
/// projection, or a call that simply failed — all of them hide the button rather than
/// offer a watch the server would refuse. The button only hides a refusal; the server is
/// the gate (§5, F-Clayton-C6).
library;

/// One projected seat.
class FleetWatchableRow {
  /// The seat's `stable_session_id` — the full id that survives a `/clear`.
  ///
  /// 🔴 THE JOIN DEPENDS ON THIS BEING THE SAME STRING AT THE SAME WIDTH as the fleet
  /// row's `session_id` and the stream's `cc_session_id`. Three id widths circulate in
  /// this fleet — the full id, `sender_id`'s `#<8hex>` suffix, and a DM's
  /// `recipient_session_hash8` — and §3 pins the stream to the full one. **Phase 1
  /// verifies the two surfaces agree rather than assuming it (A3.6)**, because a silent
  /// width mismatch shows up as a roster row that cannot be watched.
  ///
  /// ⚠️ ON THE PHONE A MISMATCH IS SAFE-BY-CONSTRUCTION AND THEREFORE INVISIBLE HERE.
  /// [FleetWatchableRoster.watchableSessionIds] joins on exact string equality, so a
  /// width mismatch hides the button — the same outcome as "not watchable". That is the
  /// right direction for the user and the wrong direction for diagnosis, which is
  /// precisely why A3.6 is a server-side check and not something this client can notice.
  final String? sessionId;

  /// Which registered project the seat belongs to. From the session bridge, per §3.
  final String? project;

  /// When the seat last wrote — the transcript file's mtime, per §3.
  ///
  /// ⚠️ THE PROJECTION MUST SAY WHICH SOURCE IT USED, because a `last_ts` that quietly
  /// means "row refreshed" rather than "seat last wrote" makes a dead seat look live
  /// (§3). The phone displays nothing from this field yet; it is parsed so the value is
  /// available to slice 3 without a second round of model work.
  final String? lastTs;

  /// True only for an admin caller and a seat with a live transcript.
  ///
  /// 🔴 A MISSING FIELD COUNTS AS FALSE. Both watch affordances — the phone's and the
  /// multiplexer's chip — read this one field so that neither re-derives the rule, and an
  /// older server or a projection that forgot the field hides the affordance rather than
  /// offering a watch that would be refused (§3).
  final bool transcriptWatchable;

  const FleetWatchableRow( {
    this.sessionId,
    this.project,
    this.lastTs,
    this.transcriptWatchable = false,
  } );

  /// Parse one projected row.
  ///
  /// Ensures:
  ///   - a non-Map, or any absent field, yields nulls and `transcriptWatchable == false`
  ///   - a `transcript_watchable` that is not a bool — a string "true", a 1, a null —
  ///     is **false**, never coerced. A server that changes that field's type is a
  ///     server whose contract has moved, and guessing would offer a watch on a guess
  factory FleetWatchableRow.fromJson( Object? json ) {
    if ( json is! Map ) return const FleetWatchableRow();

    String? str( String key ) {
      final v = json[ key ];
      return v is String && v.isNotEmpty ? v : null;
    }

    final watchable = json[ "transcript_watchable" ];

    return FleetWatchableRow(
      sessionId           : str( "session_id" ),
      project             : str( "project" ),
      lastTs              : str( "last_ts" ),
      transcriptWatchable : watchable is bool && watchable,
    );
  }
}

/// The projection's whole answer.
class FleetWatchableRoster {
  /// The envelope's `status`, when it carries one.
  ///
  /// 🔴 `fleet-state` ANSWERS `{status: "unreachable"}` WITH AN HTTP 200 when the
  /// standalone arbiter at `:8001` is down — that envelope is deliberate, because
  /// fleet-state is a reverse-proxy to `:8001/state`. So the projection inherits the
  /// same shape, and reading a 200 as success would render an empty roster with no
  /// explanation. §3's A3.7 requires the two be distinguishable, and
  /// [isUnreachable] is how this client tells them apart.
  final String? status;

  final List<FleetWatchableRow> rows;

  /// True when the projection could not be read at all — a 403, a transport failure, or
  /// a server that does not have the endpoint.
  ///
  /// ⚠️ DISTINCT FROM [isUnreachable], WHICH IS THE SERVER SUCCEEDING AND SAYING THE
  /// ARBITER IS DOWN. Both hide every button; they are different facts and the pane may
  /// one day want to say so. Today neither is surfaced, because §5 is explicit that a
  /// failed projection call means "no error, no dead button".
  final bool unavailable;

  const FleetWatchableRoster( {
    this.status,
    this.rows = const [],
    this.unavailable = false,
  } );

  /// The roster the pane uses when the projection could not be read.
  static const FleetWatchableRoster none =
      FleetWatchableRoster( unavailable: true );

  /// The `:8001` arbiter is down, as reported by a successful 200.
  bool get isUnreachable => status == "unreachable";

  /// The seats this caller may watch, by full session id.
  ///
  /// Ensures:
  ///   - empty when [unavailable] or [isUnreachable], so every button hides
  ///   - contains only rows whose `transcript_watchable` is literally true AND whose
  ///     `session_id` is a non-empty string — a true flag on an unidentifiable row
  ///     cannot be joined to anything, so it is dropped rather than carried
  Set<String> get watchableSessionIds {
    if ( unavailable || isUnreachable ) return const <String>{};

    return rows
        .where( ( r ) => r.transcriptWatchable && r.sessionId != null )
        .map( ( r ) => r.sessionId! )
        .toSet();
  }

  /// Parse the projection body.
  ///
  /// Ensures:
  ///   - a non-Map body yields an empty roster that is NOT [unavailable] — the call
  ///     succeeded and said nothing, which is an empty fleet, not a broken read
  ///   - rows are read from `sessions`, the key `/arbiter/fleet-state` uses inside
  ///     `fleet_arbiter`, and from a top-level `rows` as the alternative the projection
  ///     may choose. Whichever is present wins; neither being present is an empty fleet
  factory FleetWatchableRoster.fromJson( Object? json ) {
    if ( json is! Map ) return const FleetWatchableRoster();

    final status = json[ "status" ];

    // 🔴 PINNED BY THE CAPTURE (2026-09-29): the live server answers
    // `{ status, seats[], session_count }` (lupin cc_transcript.py:81). The two
    // spellings this used to guess — `sessions` and `rows` — are BOTH wrong for
    // the real body, so on a real phone every watch button stayed hidden while
    // every hand-written test passed. The first captured watchable_roster.json
    // turned C5.9's field arm red on exactly that. `seats` is read first; the old
    // spellings stay only as fallbacks for the hand-built fixtures still using them.
    final nested = json[ "fleet_arbiter" ];
    final raw    = json[ "seats" ]
        ?? json[ "sessions" ]
        ?? json[ "rows" ]
        ?? ( nested is Map ? nested[ "sessions" ] : null );

    return FleetWatchableRoster(
      status : status is String ? status : null,
      rows   : raw is List
          ? raw.map( FleetWatchableRow.fromJson ).toList( growable: false )
          : const [],
    );
  }
}
