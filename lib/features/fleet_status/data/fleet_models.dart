/// Fleet Status wire shapes for `GET /api/arbiter/fleet-state`, and the cell formatters.
///
/// This mirrors the web multiplexer's `fleetModel.ts` by observational equivalence, not
/// shared code: the same payload must give the same cell text on both clients.
/// When the `:8001` arbiter is down the endpoint still answers 200, with
/// `{status: "unreachable", health_watcher: null, fleet_arbiter: null}`. Reading only the
/// HTTP status would show a fleet with zero seats, so the pane checks
/// [FleetComposite.isUnreachable]. That envelope omits `app_timezone`, which is nullable;
/// the caller falls back to the device zone. `app_timezone` is display-only and must never block the table.
library;

/// The raw liveness ages plus the arbiter's verdict, per session.
///
/// Every age is nullable because the detail text shows "n/a" for a missing one. A visible
/// gap beats a row that silently shortens.
class FleetLiveness {
  /// Seconds since the session bridge file was last touched.
  final int?    bridgeAgeS;

  /// Seconds since the session's last event.
  final int?    eventAgeS;

  /// Seconds since the session last posted to commons.
  final int?    commonsAgeS;

  /// Seconds since the session's last idle prompt.
  final int?    idlePromptAgeS;

  /// Seconds since the freshest of the signals above.
  final int?    freshestAgeS;

  /// The arbiter's verdict, a free-form string such as `LIVE`, `quiet 3m` or `offline`.
  final String? verdict;

  /// Creates a liveness record; every field defaults to unknown.
  const FleetLiveness( {
    this.bridgeAgeS,
    this.eventAgeS,
    this.commonsAgeS,
    this.idlePromptAgeS,
    this.freshestAgeS,
    this.verdict,
  } );

  /// Parses one `liveness` object.
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

  /// The verdict word the row shows; "unknown" when there is none.
  String get verdictLabel => verdict ?? "unknown";
}

/// One row of the fleet table.
class FleetSession {
  /// The session id.
  final String?       sessionId;

  /// The persona name; null for a session with no persona.
  final String?       persona;

  /// The arbiter's state word for the seat.
  final String?       state;

  /// What the seat is holding on, or null; the literal "none" means nothing.
  final String?       holdingOn;

  /// True when the arbiter marked the seat stuck.
  final bool          stuck;

  /// The seat's role; the table shows "worker" when absent.
  final String?       role;

  /// The manager the seat reports to.
  final String?       manager;

  /// The seat's liveness ages and verdict.
  final FleetLiveness liveness;

  /// Creates one row; every field defaults to absent.
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

  /// Parses one entry of `fleet_arbiter.sessions`.
  ///
  /// Ensures:
  ///     - a non-map input yields an empty session, so one malformed row cannot blank
  ///       the pane
  ///     - `stuck` is true only for the boolean `true`
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

  /// The "Who" cell: the persona, else the session id's first 8 characters, else "unknown".
  String get whoLabel {
    final p = persona;
    if ( p != null && p.isNotEmpty ) return p;
    final s = sessionId;
    if ( s != null && s.isNotEmpty ) return s.length <= 8 ? s : s.substring( 0, 8 );
    return "unknown";
  }

  /// The "Role" cell, defaulting to "worker".
  String get roleLabel => ( role != null && role!.isNotEmpty ) ? role! : "worker";

  /// The "State" cell, defaulting to "unknown".
  String get stateLabel => ( state != null && state!.isNotEmpty ) ? state! : "unknown";

  /// The "Holding on" cell; the literal "none" and an empty value both show an em dash.
  String get holdingLabel {
    final h = holdingOn;
    if ( h == null || h.isEmpty || h == "none" ) return "—";
    return h;
  }

  /// The "Stuck" cell: a check when stuck, an em dash otherwise.
  String get stuckLabel => stuck ? "✓" : "—";

  /// The raw liveness ages, which the web shows on hover and the phone shows on tap.
  ///
  /// A phone has no hover, so the Liveness cell reveals this string on tap. The content
  /// matches the web's; only the gesture differs.
  ///
  /// Ensures:
  ///     - five " · "-joined segments in the web's order: bridge, event, commons,
  ///       idle_prompt, freshest
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

  /// Whether the seat is offline, for the offline toggle.
  ///
  /// True only when `verdict == "offline"` exactly; a row with no verdict stays live. The
  /// verdict is free-form: the fleet reports `LIVE`, `quiet 3m` and `stale 21m`. A stale
  /// seat is not offline, and hiding it would take a seat the operator must chase off the
  /// screen. The web colours a row by the verdict's first word but keys the toggle on the
  /// whole string, as this does. Matching "DEAD" or "OFFLINE" would hide nothing real.
  bool get isOffline => liveness.verdict == "offline";
}

/// The per-persona context-pressure record, for the "% Window" and "Window" columns.
class FleetContextRecord {
  /// The percentage of the context window consumed, as the server rounded it.
  final double? consumptionPctOfWindow;

  /// The context window size in tokens.
  final int?    windowSize;

  /// Creates a record; both fields default to unmeasured.
  const FleetContextRecord( { this.consumptionPctOfWindow, this.windowSize } );

  /// Parses one `context_pressure.personas` value.
  ///
  /// Ensures:
  ///     - a non-map input yields an all-null record; "unmeasured" is a real state the
  ///       columns show as an em dash, not an error
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
  /// The envelope status; "unreachable" when the arbiter could not be reached.
  final String?                           status;

  /// The server's timezone for the last-updated stamp; null on the unreachable envelope.
  final String?                           appTimezone;

  /// The fleet table rows.
  final List<FleetSession>                sessions;

  /// Context records keyed by the persona string exactly as the server sent it.
  final Map<String, FleetContextRecord>   personas;

  /// Creates a composite; everything defaults to empty.
  const FleetComposite( {
    this.status,
    this.appTimezone,
    this.sessions = const [],
    this.personas = const {},
  } );

  /// Parses the composite.
  ///
  /// Requires:
  ///     - json is the decoded response body
  ///
  /// Ensures:
  ///     - `status: "unreachable"` parses with empty sessions; the envelope is a 200 and
  ///       is not a transport failure
  ///     - a missing or malformed `fleet_arbiter.sessions` yields an empty list
  ///     - `app_timezone` is null when the server omitted it, as the unreachable
  ///       envelope always does
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

  /// True when the arbiter could not be reached and the server said so in a 200.
  ///
  /// The pane renders this as "we cannot see the fleet", never as a fleet with no seats.
  bool get isUnreachable => status == "unreachable";

  /// The context record for one session, joined on the exact persona string.
  ///
  /// The join is exact-key, as on the web, because the two maps come from different
  /// producers and their keys are not case-normalised. A case-insensitive join would show
  /// numbers the web does not, so the phone would look more complete than the desktop.
  ///
  /// Ensures:
  ///     - an unmatched or null persona yields an all-null record, never null
  ///     - the window columns then show an em dash
  FleetContextRecord contextFor( FleetSession session ) {
    final p = session.persona;
    if ( p == null || p.isEmpty ) return const FleetContextRecord();
    return personas[ p ] ?? const FleetContextRecord();
  }
}

// ---------------------------------------------------------------------------
// Formatters, matching the web cell for cell
// ---------------------------------------------------------------------------

/// Formats a context-window size: exact million as "<n>M", exact thousand as "<n>K".
///
/// Anything else prints as the plain integer.
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

/// Formats the percentage of the context window consumed.
///
/// The backend pre-rounds to one decimal and the web prints the number it was given.
/// Re-rounding here would make the two clients disagree on a value neither computed.
///
/// Ensures:
///     - null → "—"
///     - a whole number prints without a trailing ".0" (8.0 → "8%", 32.8 → "32.8%")
String formatConsumptionPct( double? pct ) {
  if ( pct == null ) return "—";
  final whole = pct == pct.roundToDouble();
  return whole ? "${ pct.toInt() }%" : "$pct%";
}

// ---------------------------------------------------------------------------
// The reassignment roster
// ---------------------------------------------------------------------------

/// The personas a task may be reassigned to: the live fleet's personas, alpha-sorted.
///
/// Only live sessions count, because reassigning a row to an offline persona files work
/// with nobody. The rule matches the fleet card's default live view, [FleetSession.isOffline].
/// A row without a verdict stays live, since the arbiter says offline explicitly.
///
/// Requires:
///     - fleet is the composite the fleet pane caches, or null
///
/// Ensures:
///     - null, unreachable, pre-first-poll or malformed `sessions` returns [], not a throw
///       (the owner control then offers only the current owner, since the phone cannot
///       see the fleet)
///     - only live sessions contribute; blank personas dropped; duplicates collapsed
///     - returned alpha-sorted, case-insensitively
List<String> activeReassignTargets( FleetComposite? fleet ) {
  if ( fleet == null || fleet.isUnreachable ) return const <String>[];

  final seen = <String>{};
  for ( final session in fleet.sessions ) {
    if ( session.isOffline ) continue;
    final persona = session.persona;
    if ( persona == null || persona.trim().isEmpty ) continue;
    seen.add( persona );
  }

  final out = seen.toList();
  out.sort( ( a, b ) => a.toLowerCase().compareTo( b.toLowerCase() ) );
  return out;
}
