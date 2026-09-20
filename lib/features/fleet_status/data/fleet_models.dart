/// Fleet Status — the wire shapes of `GET /api/arbiter/fleet-state` and the
/// pure formatters the eight columns render through.
///
/// Ported from the web multiplexer's `render/fleetModel.ts` as OBSERVATIONAL
/// EQUIVALENCE, not shared code: the two clients share nothing, so the rule is
/// that the same payload produces the same cell text on both.
///
/// 🔴 THE UNREACHABLE ENVELOPE IS AN HTTP 200, NOT AN ERROR. When the :8001
/// arbiter is down, `/api/arbiter/fleet-state` answers 200 with
/// `{status: "unreachable", health_watcher: null, fleet_arbiter: null}` rather
/// than a 5xx (`arbiter.py:168-176`) — the proxy is up, the upstream watcher is
/// not. A client that dispatches on the HTTP status alone renders that as a
/// fleet with zero seats, which reads as "nobody is working" when it means "we
/// cannot see". [FleetComposite.isUnreachable] is the flag the pane must check.
///
/// ⚠️ `app_timezone` IS OMITTED ON THAT ENVELOPE BY DESIGN (`arbiter.py:158-162`),
/// so it is nullable here and the caller falls back to the device zone. It is
/// display-only for the last-updated stamp and must never block the table.
library;

/// The raw liveness ages plus the arbiter's verdict, per session.
///
/// Every age is nullable because the tooltip renders "n/a" for a missing one
/// rather than dropping the line — a gap the operator can see beats a row that
/// silently shortens.
class FleetLiveness {
  final int?    bridgeAgeS;
  final int?    eventAgeS;
  final int?    commonsAgeS;
  final int?    idlePromptAgeS;
  final int?    freshestAgeS;
  final String? verdict;

  const FleetLiveness( {
    this.bridgeAgeS,
    this.eventAgeS,
    this.commonsAgeS,
    this.idlePromptAgeS,
    this.freshestAgeS,
    this.verdict,
  } );

  /// Parse one `liveness` object.
  ///
  /// Requires:
  ///     - json is the session's `liveness` value, or null when absent
  ///
  /// Ensures:
  ///     - a null or non-map input yields an all-null record, never throws
  ///     - a non-numeric age is dropped to null rather than coerced
  factory FleetLiveness.fromJson( Object? json ) {
    if ( json is! Map ) return const FleetLiveness();
    int? age( String key ) {
      final v = json[ key ];
      return v is num ? v.toInt() : null;
    }
    return FleetLiveness(
      bridgeAgeS     : age( "bridge_age_s" ),
      eventAgeS      : age( "event_age_s" ),
      commonsAgeS    : age( "commons_age_s" ),
      idlePromptAgeS : age( "idle_prompt_age_s" ),
      freshestAgeS   : age( "freshest_age_s" ),
      verdict        : json[ "verdict" ] is String ? json[ "verdict" ] as String : null,
    );
  }

  /// The verdict word the row shows, never null.
  String get verdictLabel => verdict ?? "unknown";
}

/// One row of the fleet table.
class FleetSession {
  final String?       sessionId;
  final String?       persona;
  final String?       state;
  final String?       holdingOn;
  final bool          stuck;
  final String?       role;
  final String?       manager;
  final FleetLiveness liveness;

  const FleetSession( {
    this.sessionId,
    this.persona,
    this.state,
    this.holdingOn,
    this.stuck    = false,
    this.role,
    this.manager,
    this.liveness = const FleetLiveness(),
  } );

  /// Parse one entry of `fleet_arbiter.sessions`.
  ///
  /// Ensures:
  ///     - a non-map input yields an empty session rather than throwing, so one
  ///       malformed row cannot blank the whole pane
  ///     - `stuck` is truthy-coerced the way the web reads it (`!!session.stuck`)
  factory FleetSession.fromJson( Object? json ) {
    if ( json is! Map ) return const FleetSession();
    String? str( String key ) => json[ key ] is String ? json[ key ] as String : null;
    return FleetSession(
      sessionId : str( "session_id" ),
      persona   : str( "persona" ),
      state     : str( "state" ),
      holdingOn : str( "holding_on" ),
      stuck     : json[ "stuck" ] == true,
      role      : str( "role" ),
      manager   : str( "manager" ),
      liveness  : FleetLiveness.fromJson( json[ "liveness" ] ),
    );
  }

  /// The "Who" cell: persona, else the session id's first 8 characters, else
  /// "unknown". Ported from `fleetModel.ts:68-73`.
  String get whoLabel {
    final p = persona;
    if ( p != null && p.isNotEmpty ) return p;
    final s = sessionId;
    if ( s != null && s.isNotEmpty ) return s.length <= 8 ? s : s.substring( 0, 8 );
    return "unknown";
  }

  /// The "Role" cell, defaulting to worker (`fleetStatusTable.ts:89`).
  String get roleLabel => ( role != null && role!.isNotEmpty ) ? role! : "worker";

  /// The "State" cell (`fleetStatusTable.ts:90`).
  String get stateLabel => ( state != null && state!.isNotEmpty ) ? state! : "unknown";

  /// The "Holding on" cell — the literal string "none" and an empty value both
  /// render as an em dash (`fleetStatusTable.ts:75`, `:91-92`).
  String get holdingLabel {
    final h = holdingOn;
    if ( h == null || h.isEmpty || h == "none" ) return "—";
    return h;
  }

  /// The "Stuck" cell: a check when stuck, an em dash otherwise
  /// (`fleetStatusTable.ts:75`).
  String get stuckLabel => stuck ? "✓" : "—";

  /// The raw-four-ages detail that the web hangs on a `title=` hover.
  ///
  /// 🔴 A PHONE HAS NO HOVER, so this string is reached by TAP on the Liveness
  /// cell rather than by pointing at it. The content is ported verbatim from
  /// `fleetModel.ts:79-90`; only the gesture changes.
  ///
  /// Ensures:
  ///     - four " · "-joined segments, in the web's order
  ///     - a null age renders "n/a", never a blank or a dropped segment
  String get livenessDetail {
    String fmt( int? v ) => v == null ? "n/a" : "${ v }s";
    return [
      "bridge ${ fmt( liveness.bridgeAgeS ) }",
      "event ${ fmt( liveness.eventAgeS ) }",
      "commons ${ fmt( liveness.commonsAgeS ) }",
      "idle_prompt ${ fmt( liveness.idlePromptAgeS ) }",
      "freshest ${ fmt( liveness.freshestAgeS ) }",
    ].join( " · " );
  }

  /// Whether this seat is offline for the purposes of the offline toggle.
  ///
  /// 🔴 THE TEST IS `verdict == "offline"` EXACTLY, AND A ROW WITH NO VERDICT
  /// STAYS LIVE. Ported from `fleetModel.ts:155`, `:161-162` — its own words:
  /// "`liveness.verdict === "offline"`; rows without a verdict stay LIVE."
  ///
  /// ⚠️ THE VERDICT IS A FREE-FORM STRING, NOT AN ENUM, and that is what makes
  /// a hand-rolled predicate here dangerous. Measured live 2026-09-19, the ten
  /// seats reported `LIVE`, `quiet 3m` and `stale 21m` — a stale seat is not an
  /// offline one, and hiding it would take a seat the operator needs to chase
  /// off the screen. The web keys its COLOUR on the first whitespace-delimited
  /// word lowercased (`fleetVerdictClass`, `:211-219`) but keys the TOGGLE on
  /// the whole string, so this does too.
  ///
  /// The first cut of this getter treated a missing verdict, "DEAD" and
  /// "OFFLINE" as offline and did not match the lowercase "offline" the server
  /// actually sends. It would have hidden nothing in the live fleet while
  /// silently hiding every row the arbiter had not yet judged.
  bool get isOffline => liveness.verdict == "offline";
}

/// The per-persona context-pressure record, for the "% Window" and "Window"
/// columns.
class FleetContextRecord {
  final double? consumptionPctOfWindow;
  final int?    windowSize;

  const FleetContextRecord( { this.consumptionPctOfWindow, this.windowSize } );

  /// Parse one `context_pressure.personas` value.
  ///
  /// Ensures:
  ///     - a non-map input yields an all-null record — "unmeasured" is a real
  ///       state the columns render as an em dash, not an error
  factory FleetContextRecord.fromJson( Object? json ) {
    if ( json is! Map ) return const FleetContextRecord();
    final pct = json[ "consumption_pct_of_window" ];
    final win = json[ "window_size" ];
    return FleetContextRecord(
      consumptionPctOfWindow : pct is num ? pct.toDouble() : null,
      windowSize             : win is num ? win.toInt()    : null,
    );
  }
}

/// The whole `/api/arbiter/fleet-state` body.
class FleetComposite {
  final String?                           status;
  final String?                           appTimezone;
  final List<FleetSession>                sessions;
  final Map<String, FleetContextRecord>   personas;

  const FleetComposite( {
    this.status,
    this.appTimezone,
    this.sessions = const [],
    this.personas = const {},
  } );

  /// Parse the composite.
  ///
  /// Requires:
  ///     - json is the decoded response body
  ///
  /// Ensures:
  ///     - `status: "unreachable"` parses successfully with empty sessions —
  ///       the envelope is a 200 and must not be read as a transport failure
  ///     - a missing or malformed `fleet_arbiter.sessions` yields an empty list
  ///       rather than throwing
  ///     - `app_timezone` is null when the server omitted it (the unreachable
  ///       envelope always omits it)
  factory FleetComposite.fromJson( Object? json ) {
    if ( json is! Map ) return const FleetComposite();

    final arbiter  = json[ "fleet_arbiter" ];
    final rawRows  = arbiter is Map ? arbiter[ "sessions" ] : null;
    final sessions = rawRows is List
        ? rawRows.map( FleetSession.fromJson ).toList( growable: false )
        : const <FleetSession>[];

    final pressure = json[ "context_pressure" ];
    final rawMap   = pressure is Map ? pressure[ "personas" ] : null;
    final personas = <String, FleetContextRecord>{};
    if ( rawMap is Map ) {
      rawMap.forEach( ( key, value ) {
        if ( key is String ) personas[ key ] = FleetContextRecord.fromJson( value );
      } );
    }

    return FleetComposite(
      status      : json[ "status" ]       is String ? json[ "status" ]       as String : null,
      appTimezone : json[ "app_timezone" ] is String ? json[ "app_timezone" ] as String : null,
      sessions    : sessions,
      personas    : personas,
    );
  }

  /// 🔴 The arbiter could not be reached, and the server said so in a 200.
  ///
  /// The pane must render this as "we cannot see the fleet", never as a fleet
  /// with no seats in it.
  bool get isUnreachable => status == "unreachable";

  /// The context record for one session, joined the way the web joins it.
  ///
  /// ⚠️ THE JOIN IS EXACT-KEY ON THE PERSONA STRING, and that is a port rather
  /// than an oversight (`fleetStatusTable.ts:96` —
  /// `personas[ session.persona ] || {}`). The two maps are populated by
  /// different producers and their keys are not case-normalised: measured live
  /// 2026-09-19, `context_pressure.personas` carried
  /// `Krishna · Rachel · Rio · Tiffany · chloe · maria · maya · mr radio · sam`
  /// against sessions whose `persona` matched 9 of 10 exactly. The single miss
  /// was a session with a NULL persona, which correctly falls back to the short
  /// session id for "Who" and an em dash for both window columns.
  ///
  /// A case-insensitive or fuzzy join here would show numbers the web does not,
  /// which breaks observational equivalence in the direction that is hardest to
  /// notice — the phone would look MORE complete while disagreeing with the
  /// desktop about the same fleet.
  ///
  /// Ensures:
  ///     - an unmatched or null persona yields an all-null record, never null
  FleetContextRecord contextFor( FleetSession session ) {
    final p = session.persona;
    if ( p == null || p.isEmpty ) return const FleetContextRecord();
    return personas[ p ] ?? const FleetContextRecord();
  }
}

// ---------------------------------------------------------------------------
// Formatters — ported cell-for-cell from fleetModel.ts:177-191
// ---------------------------------------------------------------------------

/// Compact context-window size: exact-million → "<n>M", exact-thousand →
/// "<n>K", else the integer. Pure.
///
/// Ensures:
///     - null, zero or negative → "—"
///     - 1000000 → "1M"; 200000 → "200K"; 1234 → "1234"
String formatWindowSize( int? windowSize ) {
  if ( windowSize == null || windowSize <= 0 ) return "—";
  if ( windowSize % 1000000 == 0 ) return "${ windowSize ~/ 1000000 }M";
  if ( windowSize % 1000    == 0 ) return "${ windowSize ~/ 1000 }K";
  return "$windowSize";
}

/// "% of context window consumed". Pure.
///
/// ⚠️ THE BACKEND PRE-ROUNDS TO ONE DECIMAL and the web prints the number it
/// was given (`fleetModel.ts:188-191`). Re-rounding here would make the two
/// clients disagree on a value neither of them computed.
///
/// Ensures:
///     - null → "—"
///     - a whole number prints without a trailing ".0" (8.0 → "8%", 32.8 → "32.8%")
String formatConsumptionPct( double? pct ) {
  if ( pct == null ) return "—";
  final whole = pct == pct.roundToDouble();
  return whole ? "${ pct.toInt() }%" : "$pct%";
}
