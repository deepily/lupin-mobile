/// Rick's New Ticket card, the phone's half (row b31a9ed9, walk-through item M4).
///
/// A port of the web's `shared/task-create.js`, which both web clients render. Rick,
/// 2026-09-10 (row c9895403): *"create a card that allows me to manually create a new
/// ticket without you having to file it for me … it needs all of the other editor fields
/// like who it's assigned to, priority, approved/disapproved by default approved."*
///
/// 🔴 THE RULES ARE THE WEB'S, WORD FOR WORD WHERE A WORD IS SHOWN. The fields, the
/// defaults, the validation and the outcome sentences all come from that file, so a
/// ticket filed from the phone and one filed from a browser cannot differ. Where the
/// phone's wording differs it is because the web's names a thing a phone does not have
/// (a page to refresh), and each such line says so.
///
/// ⚠️ A 2xx IS NOT ALWAYS "CREATED". A caller without the operator's login who asks for
/// P0 gets a 201 carrying a `petition` field: the row exists at P1 in the holding area
/// and nothing was granted. That is its own outcome, never "created".
library;

const newTicketPriorities = [ 'P0', 'P1', 'P2', 'P3', 'P4', 'P5' ];
const newTicketTypes      = [ 'task', 'bug', 'decision' ];

/// Rick's defaults, by keypress 2026-09-10: P2, approved (live board).
///
/// ⚠️ The epic key default is the STORE's, not his: a create with no `correlation_key`
/// answers 422 "no epic key", and that refusal names `epic:unassigned` as the deliberate
/// answer. So the card pre-fills it, visibly and editably.
const newTicketDefaultPriority       = 'P2';
const newTicketDefaultApproved       = true;
const newTicketDefaultType           = 'task';
const newTicketDefaultProject        = 'lupin';
const newTicketDefaultCorrelationKey = 'epic:unassigned';

/// The declared creator. The server records the validated login whatever this says.
///
/// ⚠️ JUST "rick", ON PURPOSE. A row filed with no owner defaults its owner from
/// `created_by` with only a trailing session hex stripped, so a door name here would
/// become the OWNER — a persona nobody is.
const newTicketCreatedBy = 'rick';

const newTicketTitleRequiredMessage = 'A title is required.';

/// No answer is not a no: a POST can time out AFTER the store saved the row.
///
/// ⚠️ The web says "Search Find for its title"; the phone's find box takes an id, so this
/// points at the board instead.
const newTicketNoAnswerMessage =
    'The store did not answer, so this ticket may already be saved. '
    'Check the Task List for its title before you try again.';

/// Shown on a 401. The web says "refresh the page"; a phone has no page to refresh.
const newTicketAuthRequiredMessage = 'Signed out — sign back in to create tickets.';

/// What the form holds, before any rule is applied.
class NewTicketFields {
  final String title;
  final String details;
  final String ownerPersona;
  final String accountableManager;
  final String priority;
  final bool approved;
  final String itemClass;
  final String correlationKey;
  final String project;

  const NewTicketFields( {
    this.title              = '',
    this.details            = '',
    this.ownerPersona       = '',
    this.accountableManager = '',
    this.priority           = newTicketDefaultPriority,
    this.approved           = newTicketDefaultApproved,
    this.itemClass          = newTicketDefaultType,
    this.correlationKey     = newTicketDefaultCorrelationKey,
    this.project            = newTicketDefaultProject,
  } );
}

/// Either the POST body or the reason it cannot be sent. Exactly one is non-null.
class NewTicketBuild {
  final Map<String, String>? payload;
  final String? error;

  const NewTicketBuild.ok( Map<String, String> this.payload ) : error = null;
  const NewTicketBuild.refused( String this.error ) : payload = null;

  bool get ok => payload != null;
}

/// Turn what the form holds into the POST body, or say why it cannot be sent.
///
/// Ensures:
///   - a blank title → refused, and no payload at all
///   - an unknown priority or type → refused, naming the value
///   - otherwise a payload where:
///       · `status` is "queued" when approved, "not_approved" when not
///       · `body` carries Details; it and the two people fields are OMITTED when blank,
///         so the server's own defaults apply rather than an empty string
///       · a blank project or epic key falls back to its default — the epic key is never
///         omitted, because the store refuses a create without one
///   - pure; never throws
NewTicketBuild buildNewTicketPayload( NewTicketFields f ) {
  final title = f.title.trim();
  if ( title.isEmpty ) return const NewTicketBuild.refused( newTicketTitleRequiredMessage );

  final priority = f.priority.trim().isEmpty ? newTicketDefaultPriority : f.priority.trim();
  if ( !newTicketPriorities.contains( priority ) ) {
    return NewTicketBuild.refused( 'Unknown priority "$priority".' );
  }
  final itemClass = f.itemClass.trim().isEmpty ? newTicketDefaultType : f.itemClass.trim();
  if ( !newTicketTypes.contains( itemClass ) ) {
    return NewTicketBuild.refused( 'Unknown ticket type "$itemClass".' );
  }

  final payload = <String, String>{
    'item_class'      : itemClass,
    'title'           : title,
    'project'         : f.project.trim().isEmpty ? newTicketDefaultProject : f.project.trim(),
    'created_by'      : newTicketCreatedBy,
    'priority'        : priority,
    'status'          : f.approved ? 'queued' : 'not_approved',
    'correlation_key' : f.correlationKey.trim().isEmpty
        ? newTicketDefaultCorrelationKey
        : f.correlationKey.trim(),
  };
  final details = f.details.trim();
  if ( details.isNotEmpty ) payload[ 'body' ] = details;
  final owner = f.ownerPersona.trim();
  if ( owner.isNotEmpty ) payload[ 'owner_persona' ] = owner;
  final manager = f.accountableManager.trim();
  if ( manager.isNotEmpty ) payload[ 'accountable_manager' ] = manager;
  return NewTicketBuild.ok( payload );
}

/// The server's `detail`, from a body that may be a map, JSON-ish text, or nothing.
///
/// Ensures:
///   - a string `detail` passes through verbatim — the refusals on this door name the
///     rule that fired, and are written to be read
///   - a pydantic list of errors becomes their `msg` fields joined with "; "
///   - plain text comes back trimmed; anything else comes back ""
///   - never throws
String newTicketDetailFrom( Object? body ) {
  if ( body is String ) return body.trim();
  if ( body is! Map ) return '';
  final detail = body[ 'detail' ];
  if ( detail is String ) return detail;
  if ( detail is List ) {
    return detail
        .map( ( e ) => e is Map && e[ 'msg' ] is String ? e[ 'msg' ] as String : e.toString() )
        .join( '; ' );
  }
  return '';
}

enum NewTicketState { created, petition, authRequired, refused, invalid, unreachable, failed }

/// Which outcome a create produced, and the sentence to show.
class NewTicketOutcome {
  final NewTicketState state;
  final String text;

  /// The row the store created, on [NewTicketState.created] and
  /// [NewTicketState.petition]; null otherwise.
  final Map<String, dynamic>? row;

  const NewTicketOutcome( this.state, this.text, { this.row } );
}

/// Ensures:
///   - 2xx with a `petition` field → petition: the row exists but is NOT on the board and
///     was NOT granted its priority
///   - any other 2xx → created, naming the short id and which pile the row landed in
///   - 401 → authRequired · 403 → refused · 422 → invalid, each with the server's detail
///   - status 0 (nothing answered) → unreachable, warning the row may already exist
///   - anything else → failed, naming the status and the server's own words, so a real
///     cause is never replaced by "try again"
NewTicketOutcome describeNewTicketResult( int status, Object? body ) {
  if ( status >= 200 && status < 300 ) {
    final row     = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final id      = row[ 'id' ];
    final shortId = id is String ? id.substring( 0, id.length < 8 ? id.length : 8 ) : '';
    if ( row[ 'petition' ] != null && row[ 'petition' ] != false ) {
      return NewTicketOutcome(
        NewTicketState.petition,
        'Filed $shortId in the holding area and sent for approval — it is not on the board yet.',
        row : row,
      );
    }
    final pile = row[ 'status' ] == 'queued' ? 'on the board' : 'in the holding area';
    return NewTicketOutcome( NewTicketState.created, 'Created $shortId — $pile.', row: row );
  }
  if ( status == 401 ) {
    return const NewTicketOutcome( NewTicketState.authRequired, newTicketAuthRequiredMessage );
  }
  final detail = newTicketDetailFrom( body );
  if ( status == 403 ) {
    return NewTicketOutcome(
      NewTicketState.refused,
      detail.isNotEmpty ? detail : 'The store refused this ticket.',
    );
  }
  if ( status == 422 ) {
    return NewTicketOutcome(
      NewTicketState.invalid,
      detail.isNotEmpty ? detail : 'The store could not accept this ticket.',
    );
  }
  if ( status == 0 ) {
    return const NewTicketOutcome( NewTicketState.unreachable, newTicketNoAnswerMessage );
  }
  return NewTicketOutcome(
    NewTicketState.failed,
    detail.isNotEmpty
        ? 'The store answered $status: $detail'
        : 'The store answered $status and gave no reason.',
  );
}

/// The names offered under "Assigned to": every non-blank name across [lists], once
/// each, sorted.
List<String> newTicketAssigneeOptions( Iterable<Iterable<String?>> lists ) {
  final seen = <String>{};
  for ( final list in lists ) {
    for ( final name in list ) {
      final value = name?.trim() ?? '';
      if ( value.isNotEmpty ) seen.add( value );
    }
  }
  return seen.toList()..sort();
}

/// What the POST came back with: a status (0 when nothing answered) and a body.
class NewTicketResponse {
  final int status;
  final Object? body;

  const NewTicketResponse( this.status, this.body );
}
