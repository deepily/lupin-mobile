/// The watchable-roster projection: an admin-gated read, separate from fleet-state.
///
/// Fleet-state is a verbatim reverse proxy of the arbiter's `:8001/state` body, gated for
/// any authenticated caller, not only admins. It cannot carry a per-caller field, and
/// `transcript_watchable` is per caller. So the projection computes it and carries its own
/// `require_admin`, and the fleet pane keeps polling fleet-state unchanged.
/// Every failure reads as "not watchable", so the button hides. That avoids offering a
/// watch the server would refuse. The button only hides a refusal; the server is the gate.
library;

/// One projected seat.
class FleetWatchableRow {
  /// The seat's `stable_session_id`, the full id that survives a `/clear`.
  ///
  /// It must be the same string at the same width as the fleet row's `session_id` and the
  /// stream's `cc_session_id`. Three id widths circulate. They are the full id, the
  /// `#<8hex>` suffix of `sender_id`, and a DM's `recipient_session_hash8`. The stream
  /// uses the full one.
  /// [FleetWatchableRoster.watchableSessionIds] joins on exact equality, so a width
  /// mismatch hides the button, the same outcome as "not watchable". That is safe for the
  /// user but invisible to this client. The server side must verify the surfaces agree.
  final String? sessionId;

  /// Which registered project the seat belongs to, from the session bridge.
  final String? project;

  /// When the seat last wrote: the transcript file's mtime.
  ///
  /// The projection must say which source it used, because a `last_ts` that means "row
  /// refreshed" makes a dead seat look live. The phone shows nothing from this field yet;
  /// it is parsed so a later slice can use it without more model work.
  final String? lastTs;

  /// True only for an admin caller and a seat with a live transcript.
  ///
  /// A missing field counts as false. The phone's and the multiplexer's watch affordances
  /// both read this one field, so neither re-derives the rule. An older server then hides
  /// the affordance instead of offering a watch that would be refused.
  final bool transcriptWatchable;

  /// Creates a row; every field defaults to absent and not watchable.
  const FleetWatchableRow( {
    this.sessionId,
    this.project,
    this.lastTs,
    this.transcriptWatchable = false,
  } );

  /// Parses one projected row.
  ///
  /// Ensures:
  ///   - a non-Map, or any absent field, yields nulls and `transcriptWatchable == false`
  ///   - a `transcript_watchable` that is not a bool, such as the string "true", a 1 or a
  ///     null, is false and never coerced; a changed type means the contract moved, and
  ///     guessing would offer a watch on a guess
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
  /// Fleet-state answers `{status: "unreachable"}` with an HTTP 200 when the `:8001`
  /// arbiter is down, and the projection inherits that shape. Reading a 200 as success
  /// would render an empty roster with no explanation, so [isUnreachable] tells the two
  /// apart.
  final String? status;

  /// The projected seats.
  final List<FleetWatchableRow> rows;

  /// True when the projection could not be read.
  ///
  /// That means a 403, a transport failure or a server without the endpoint.
  ///
  /// Distinct from [isUnreachable], where the server succeeds and says the arbiter is
  /// down. Both hide every button. Neither is surfaced today, because a failed projection
  /// call means no error and no dead button.
  final bool unavailable;

  /// Creates a roster; defaults to empty and readable.
  const FleetWatchableRoster( {
    this.status,
    this.rows = const [],
    this.unavailable = false,
  } );

  /// The roster the pane uses when the projection could not be read.
  static const FleetWatchableRoster none =
      FleetWatchableRoster( unavailable: true );

  /// True when the `:8001` arbiter is down, as reported by a successful 200.
  bool get isUnreachable => status == "unreachable";

  /// The seats this caller may watch, by full session id.
  ///
  /// Ensures:
  ///   - empty when [unavailable] or [isUnreachable], so every button hides
  ///   - contains only rows whose `transcript_watchable` is literally true and whose
  ///     `session_id` is a non-empty string; a true flag on an unidentifiable row cannot
  ///     be joined to anything, so it is dropped
  Set<String> get watchableSessionIds {
    if ( unavailable || isUnreachable ) return const <String>{};

    return rows
        .where( ( r ) => r.transcriptWatchable && r.sessionId != null )
        .map( ( r ) => r.sessionId! )
        .toSet();
  }

  /// Parses the projection body.
  ///
  /// Ensures:
  ///   - a non-Map body yields an empty roster that is not [unavailable]: the call
  ///     succeeded and said nothing, which is an empty fleet, not a broken read
  ///   - rows come from `seats`, the live server's key, else `sessions`, `rows`, or
  ///     `fleet_arbiter.sessions`; the first present wins, and none present is an empty
  ///     fleet
  factory FleetWatchableRoster.fromJson( Object? json ) {
    if ( json is! Map ) return const FleetWatchableRoster();

    final status = json[ "status" ];

    // The live server answers `{ status, seats[], session_count }`. `seats` is read first;
    // `sessions` and `rows` stay only as fallbacks for hand-built fixtures that still
    // use them, since neither matches the real body.
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
