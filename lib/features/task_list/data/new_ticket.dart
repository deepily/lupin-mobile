/// The phone's New Ticket card: file a ticket without asking someone else to file it.
///
/// This ports the web's `shared/task-create.js`, which both web clients render. The
/// fields, defaults, validation and outcome sentences come from that file. A ticket filed
/// from the phone and one from a browser therefore cannot differ. Where the wording
/// differs, the web's names something a phone lacks, such as a page to refresh.
/// A 2xx is not always "created": a caller without the operator's login who asks for P0
/// gets a 201 with a `petition` field. The row exists at P1 in the holding area and
/// nothing was granted, which is its own outcome.
/// Design: src/docs/decisions/README.md (R-TL-new-ticket-card)
library;

/// The priorities a new ticket may take.
const newTicketPriorities = [ 'P0', 'P1', 'P2', 'P3', 'P4', 'P5' ];

/// The ticket types a new ticket may take.
const newTicketTypes      = [ 'task', 'bug', 'decision' ];

// The card's defaults are P2 and approved, so a new ticket lands on the live board. The
// epic key default is the store's: a create with no `correlation_key` answers 422 "no epic
// key", and that refusal names `epic:unassigned`, so the card pre-fills it, visibly and
// editably.

/// The default priority.
const newTicketDefaultPriority       = 'P2';

/// Whether a new ticket is approved by default.
const newTicketDefaultApproved       = true;

/// The default ticket type.
const newTicketDefaultType           = 'task';

/// The default project.
const newTicketDefaultProject        = 'lupin';

/// The default epic key, which the store accepts as "no epic".
const newTicketDefaultCorrelationKey = 'epic:unassigned';

/// The declared creator; the server records the validated login whatever this says.
///
/// It is just "rick". A row filed with no owner takes its owner from `created_by`, with
/// only a trailing session hex stripped. A door name here would become the owner, a
/// persona nobody is.
const newTicketCreatedBy = 'rick';

/// Shown when the title is blank.
const newTicketTitleRequiredMessage = 'A title is required.';

/// Shown when nothing answered the POST.
///
/// No answer is not a no: a POST can time out after the store saved the row. The web
/// points to Find; the phone's find box takes an id, so this points at the board.
const newTicketNoAnswerMessage =
    'The store did not answer, so this ticket may already be saved. '
    'Check the Task List for its title before you try again.';

/// Shown on a 401. The web says "refresh the page"; a phone has no page to refresh.
const newTicketAuthRequiredMessage = 'Signed out — sign back in to create tickets.';

/// What the form holds, before any rule is applied.
class NewTicketFields {
  /// The ticket title.
  final String title;

  /// The free-text details, sent as the row `body`.
  final String details;

  /// The assignee; blank leaves the server's default owner.
  final String ownerPersona;

  /// The accountable manager; blank leaves the server's default.
  final String accountableManager;

  /// The requested priority.
  final String priority;

  /// Whether the ticket is filed approved (`queued`) or held (`not_approved`).
  final bool approved;

  /// The ticket type, sent as `item_class`.
  final String itemClass;

  /// The epic key, sent as `correlation_key`.
  final String correlationKey;

  /// The project.
  final String project;

  /// Creates the form state; every field has the card's default.
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
  /// The POST body, or null when refused.
  final Map<String, String>? payload;

  /// Why the ticket cannot be sent, or null when it can.
  final String? error;

  /// A buildable ticket.
  const NewTicketBuild.ok( Map<String, String> this.payload ) : error = null;

  /// A refused ticket, with the sentence to show.
  const NewTicketBuild.refused( String this.error ) : payload = null;

  /// True when [payload] is present.
  bool get ok => payload != null;
}

/// Turns what the form holds into the POST body, or says why it cannot be sent.
///
/// Ensures:
///   - a blank title is refused, with no payload at all
///   - an unknown priority or type is refused, naming the value
///   - `status` is "queued" when approved and "not_approved" when not
///   - `body` carries Details; it and the two people fields are omitted when blank, so
///     the server's own defaults apply instead of an empty string
///   - a blank project or epic key falls back to its default; the epic key is never
///     omitted, because the store refuses a create without one
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
///   - a string `detail` passes through verbatim, because refusals on this door name the
///     rule that fired and are written to be read
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

/// The outcomes a create can produce.
enum NewTicketState {
  /// The ticket was created.
  created,

  /// The row exists in the holding area at P1 and its priority was not granted.
  petition,

  /// The caller is signed out (401).
  authRequired,

  /// The store refused the ticket (403).
  refused,

  /// The store rejected the fields (422).
  invalid,

  /// Nothing answered; the ticket may already exist.
  unreachable,

  /// Any other failure.
  failed
}

/// Which outcome a create produced, and the sentence to show.
class NewTicketOutcome {
  /// The outcome kind.
  final NewTicketState state;

  /// The sentence to show the operator.
  final String text;

  /// The row the store created; null except for created and petition outcomes.
  final Map<String, dynamic>? row;

  /// Creates an outcome.
  const NewTicketOutcome( this.state, this.text, { this.row } );
}

/// Words the result of a create POST.
///
/// Ensures:
///   - 2xx with a `petition` field is petition: the row exists but is not on the board
///     and was not granted its priority
///   - any other 2xx is created, naming the short id and which pile the row landed in
///   - 401 is authRequired, 403 refused and 422 invalid, each with the server's detail
///   - status 0 (nothing answered) is unreachable, warning the row may already exist
///   - anything else is failed, naming the status and the server's own words, so a real
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

/// The names offered under "Assigned to": every non-blank name across [lists], once, sorted.
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
  /// The HTTP status, or 0 when nothing answered.
  final int status;

  /// The decoded response body, if any.
  final Object? body;

  /// Creates a response.
  const NewTicketResponse( this.status, this.body );
}
