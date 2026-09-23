import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_verbs.dart';

/// The verb table — the pure half of the shared reason sheet.
///
/// 🔴 ONE TEST PER VERB'S PAYLOAD KEY, WHICH IS THE ACCEPTANCE THIS ROW WAS WRITTEN
/// AGAINST. Four of the seven payloads are invisible from the endpoint alone and each has
/// drawn blood on some client: park's different key, un-park's explicit null, fixed's
/// receipt, and the four complaints that must not collapse into one sentence.
///
/// ─────────────────────────────────────────────────────────────────────────────────
/// 🔴 MUTATION MATRIX — MEASURED, NOT ASSERTED. Every group below was shown RED against
/// the defect it guards by reintroducing that defect and re-running.
///
/// | Test                                   | A: park→reason | B: unpark key dropped | C: fixed receipt dropped | D: one shared complaint |
/// |----------------------------------------|----------------|-----------------------|--------------------------|-------------------------|
/// | park files under park_reason           | 🔴 RED         | green                 | green                    | green                   |
/// | un-park sends an EXPLICIT null         | green          | 🔴 RED                | green                    | green                   |
/// | fixed carries the receipt and no reason| green          | green                 | 🔴 RED                   | green                   |
/// | each verb earns its OWN complaint      | green          | green                 | green                    | 🔴 RED                  |
///
///   A — `buildTaskVerb` routed park's text through `TaskVerb.demote`-style `reason`
///   B — `TaskVerb.unpark` "simplified" to omit `next_chase_ts` instead of sending null
///   C — `TaskVerb.fixed` built without `receipt_refs` (the multiplexer's `709128d4` bug)
///   D — `verbReasonComplaint` collapsed to a single "A reason is required."
///
/// ⚠️ EVERY ROW HAS A RED AND NO COLUMN IS EMPTY. A test with no red column guards
/// nothing, and a defect with no red row is a defect this file would ship.
void main() {
  group( 'the table', () {
    test( 'seven verbs, in the shared module\'s order', () {
      expect( kTaskVerbs, [ 'park', 'drop', 'demote', 'wont_fix', 'fixed', 'unpark', 'approve' ] );
      for ( final verb in kTaskVerbs ) {
        expect( verbNeeds( verb ), isNotNull, reason: '$verb has no obligations record' );
      }
    } );

    // An unknown verb must be a REFUSAL, never a partially-populated record whose
    // `.status` is absent — the web file's own hazard note: a caller that gets a truthy
    // answer for "toString" POSTs a transition with no target status.
    test( 'an unknown verb returns null rather than a hollow record', () {
      expect( verbNeeds( 'toString' ), isNull );
      expect( verbNeeds( 'hashCode' ), isNull );
      expect( verbNeeds( '' ), isNull );
      expect( verbNeeds( null ), isNull );
    } );

    test( 'only park and demote ask for a date', () {
      final dated = kTaskVerbs.where( ( v ) => verbNeeds( v )!.date ).toList();
      expect( dated, [ 'park', 'demote' ] );
    } );

    test( 'only wont_fix and fixed are terminal', () {
      final terminal = kTaskVerbs.where( ( v ) => verbNeeds( v )!.terminal ).toList();
      expect( terminal, [ 'wont_fix', 'fixed' ] );
    } );

    // Approve and un-park are the only two a press can send without asking anything.
    test( 'approve and un-park are the only verbs that need no sheet', () {
      final direct = kTaskVerbs.where( ( v ) => !verbNeeds( v )!.needsSheet ).toList();
      expect( direct, [ 'unpark', 'approve' ] );
    } );
  } );

  group( 'payloads — one per verb', () {
    test( 'approve is a STATUS change to queued', () {
      expect( buildTaskVerb( 'approve' ).payload, { 'to_status' : 'queued' } );
    } );

    // 🔴 AN EXPLICIT NULL, NOT AN OMITTED KEY. "Send nothing" and "send null" are
    // different requests and only one of them clears (`taskVerbs.ts:304-313`). Rick ruled
    // it: a surviving chase date re-chases him about a row already back on his board.
    test( 'un-park sends an EXPLICIT null next_chase_ts', () {
      final payload = buildTaskVerb( 'unpark' ).payload;
      expect( payload[ 'to_status' ], 'queued' );
      expect( payload.containsKey( 'next_chase_ts' ), isTrue,
          reason: 'omitting the key leaves the stored chase untouched — a different '
                  'request from the one that clears it' );
      expect( payload[ 'next_chase_ts' ], isNull );
    } );

    // 🔴 PARK FILES UNDER `park_reason`. One verb out of the four uses a different key
    // for the same box, and a park filed under the generic key lands with no decisive
    // sentence attached — the whole thing the field exists to carry.
    test( 'park files its reason under park_reason, never reason', () {
      final payload = buildTaskVerb(
        'park',
        reason  : '  Rick said not this quarter  ',
        chaseTs : DateTime.utc( 2026, 10, 1 ),
      ).payload;

      expect( payload[ 'to_status' ], 'parked' );
      expect( payload[ 'park_reason' ], 'Rick said not this quarter',
          reason: 'the reason is trimmed before it goes on the wire' );
      expect( payload.containsKey( 'reason' ), isFalse,
          reason: 'the server keys the two apart; a park under `reason` carries no '
                  'decisive sentence' );
      expect( payload[ 'next_chase_ts' ], '2026-10-01T00:00:00.000Z' );
    } );

    test( 'demote files under reason and carries its triage date', () {
      final payload = buildTaskVerb(
        'demote',
        reason  : 'needs a decision first',
        chaseTs : DateTime.utc( 2026, 10, 5 ),
      ).payload;

      expect( payload[ 'to_status' ], 'not_approved' );
      expect( payload[ 'reason' ], 'needs a decision first' );
      expect( payload.containsKey( 'park_reason' ), isFalse );
      expect( payload[ 'next_chase_ts' ], '2026-10-05T00:00:00.000Z' );
    } );

    test( 'drop files under reason and carries no date', () {
      final payload = buildTaskVerb( 'drop', reason: 'overtaken by events' ).payload;
      expect( payload[ 'to_status' ], 'dropped' );
      expect( payload[ 'reason' ], 'overtaken by events' );
      expect( payload.containsKey( 'next_chase_ts' ), isFalse );
    } );

    test( 'wont_fix files under reason and is terminal', () {
      final verb = buildTaskVerb( 'wont_fix', reason: 'will not be done' );
      expect( verb.terminal, isTrue );
      expect( verb.payload[ 'to_status' ], 'wont_fix' );
      expect( verb.payload[ 'reason' ], 'will not be done' );
    } );

    // 🔴 THE RECEIPT IS THE WHOLE VERB. The store refuses a `->done` with no receipt; the
    // multiplexer picked this verb up in `709128d4` without it and EVERY Fixed press was
    // refused by the server. The value is not trusted — the key being present is what
    // matters — but the CLIENT TAG must say mobile, or a phone's writes file as desktop.
    test( 'fixed carries the operator attestation and NO reason', () {
      final verb = buildTaskVerb( 'fixed' );
      expect( verb.terminal, isTrue );
      expect( verb.payload[ 'to_status' ], 'done' );

      final receipts = verb.payload[ 'receipt_refs' ] as Map<String, dynamic>;
      expect( receipts[ 'operator_attestation' ], kMobileOperatorAttestation );
      expect( kMobileOperatorAttestation, contains( 'mobile' ),
          reason: 'a phone stamping (multiplexer) files its writes as desktop ones' );

      expect( verb.payload.containsKey( 'reason' ), isFalse );
      expect( verb.payload.containsKey( 'park_reason' ), isFalse );
    } );

    // The date is serialised in UTC because the handset's zone is not the server's. A
    // chase filed in local time re-chases at the wrong hour, or across a date boundary
    // on the wrong day.
    test( 'a local-time chase date is serialised as UTC', () {
      final local = DateTime( 2026, 10, 1, 23, 30 );
      final sent  = buildTaskVerb( 'park', reason: 'x', chaseTs: local )
          .payload[ 'next_chase_ts' ] as String;

      expect( sent, endsWith( 'Z' ) );
      expect( DateTime.parse( sent ).isAtSameMomentAs( local ), isTrue );
    } );
  } );

  group( 'a blank required field never reaches the wire', () {
    test( 'a verb that requires a reason refuses a blank one', () {
      for ( final verb in [ 'park', 'drop', 'demote', 'wont_fix' ] ) {
        expect( () => buildTaskVerb( verb, reason: '   ', chaseTs: DateTime.utc( 2026 ) ),
            throwsArgumentError,
            reason: '$verb with whitespace for a reason is a guaranteed 422' );
        expect( () => buildTaskVerb( verb, chaseTs: DateTime.utc( 2026 ) ),
            throwsArgumentError, reason: '$verb with no reason at all' );
      }
    } );

    // 🔴 A PARK WITH NO DATE IS NOT A PARK WITH NO DATE — IT IS A PARK THAT CLEARS ONE.
    // `TaskVerb.park` always puts the key in the body, so building one without a date
    // would send the CLEARING value silently. The refusal is what stops that.
    test( 'park and demote refuse a missing date', () {
      expect( () => buildTaskVerb( 'park', reason: 'a reason' ), throwsArgumentError );
      expect( () => buildTaskVerb( 'demote', reason: 'a reason' ), throwsArgumentError );
    } );

    test( 'an unknown verb is refused rather than posted', () {
      expect( () => buildTaskVerb( 'toString' ), throwsArgumentError );
      expect( () => buildTaskVerb( 'delete_everything' ), throwsArgumentError );
    } );
  } );

  group( 'complaints — four verbs, four sentences', () {
    // 🔴 "A REASON IS REQUIRED" IS TRUE OF FOUR OF THEM AND TEACHES NONE OF THEM.
    // Merging the controls was the ask; merging what they mean was not.
    test( 'no two reason verbs share a complaint', () {
      final reasonVerbs = [ 'park', 'drop', 'demote', 'wont_fix' ];
      final complaints  = reasonVerbs.map( verbReasonComplaint ).toList();

      expect( complaints.toSet(), hasLength( reasonVerbs.length ),
          reason: 'a shared sentence tells the operator which box to fill and nothing '
                  'about what belongs in it' );
      for ( final c in complaints ) {
        expect( c, isNot( 'A reason is required.' ),
            reason: 'the generic sentence is the defect, not the fallback' );
      }
    } );

    test( 'park asks for a QUOTE and demote for the reason it goes back', () {
      expect( verbReasonComplaint( 'park' ), contains( 'quote' ) );
      expect( verbReasonComplaint( 'demote' ), contains( 'triage' ) );
      expect( verbReasonComplaint( 'wont_fix' ), contains( 'refusal' ) );
    } );

    test( 'park and demote mean different things by a date, and say so', () {
      expect( verbDateComplaint( 'park' ), contains( 'chase' ) );
      expect( verbDateComplaint( 'demote' ), contains( 'triage' ) );
      expect( verbDateComplaint( 'park' ), isNot( verbDateComplaint( 'demote' ) ) );
    } );
  } );

  group( 'legality', () {
    List<String> enabledOn( String? status ) => verbLegality( status )
        .where( ( e ) => e.enabled )
        .map( ( e ) => e.verb )
        .toList();

    test( 'every status returns all seven entries, in table order', () {
      for ( final status in [ 'queued', 'parked', 'not_approved', 'done', null ] ) {
        final entries = verbLegality( status );
        expect( entries.map( ( e ) => e.verb ).toList(), kTaskVerbs,
            reason: 'illegal verbs are GREYED, never removed — a control that vanishes '
                    'teaches nothing about why the move is not available' );
      }
    } );

    // 🔴 A TERMINAL ROW OFFERS NOTHING. The server's validate_transition refuses every
    // edge out of done / dropped / wont_fix.
    test( 'a terminal row offers nothing, and each entry says why', () {
      for ( final status in [ 'done', 'dropped', 'wont_fix' ] ) {
        expect( enabledOn( status ), isEmpty, reason: '$status is append-only' );
        for ( final entry in verbLegality( status ) ) {
          expect( entry.why, contains( status ),
              reason: 'the refusal names the row\'s OWN status, not a generic one' );
          expect( entry.why, contains( 'append-only' ) );
        }
      }
    } );

    test( 'park is legal only from queued or in_progress', () {
      expect( enabledOn( 'queued' ), contains( 'park' ) );
      expect( enabledOn( 'in_progress' ), contains( 'park' ) );
      expect( enabledOn( 'parked' ), isNot( contains( 'park' ) ) );
      expect( enabledOn( 'not_approved' ), isNot( contains( 'park' ) ) );
    } );

    // ⚠️ OPPOSITE ENDS OF ONE DOOR, so exactly one is ever live on a row. Offering both
    // hands the operator a no-op the store rejects as a FAILURE.
    test( 'approve and demote are never both live on one row', () {
      for ( final status in [ 'queued', 'in_progress', 'parked', 'not_approved' ] ) {
        final live = enabledOn( status );
        expect( live.contains( 'approve' ) && live.contains( 'demote' ), isFalse,
            reason: 'both offered on a $status row' );
      }
      expect( enabledOn( 'not_approved' ), contains( 'approve' ) );
      expect( enabledOn( 'queued' ), contains( 'demote' ) );
    } );

    test( 'un-park is legal only on a parked row', () {
      expect( enabledOn( 'parked' ), contains( 'unpark' ) );
      expect( enabledOn( 'queued' ), isNot( contains( 'unpark' ) ) );
    } );

    // An EXPIRED park still reads `parked` — expiry is computed at read time and never
    // rewrites the row — so the verb is offered on it. Rick's case, row 49b87212.
    test( 'drop, won\'t-fix and fixed are legal from every non-terminal status', () {
      for ( final status in [ 'queued', 'in_progress', 'parked', 'not_approved', 'blocked' ] ) {
        expect( enabledOn( status ), containsAll( [ 'drop', 'wont_fix', 'fixed' ] ),
            reason: 'refused on a $status row' );
      }
    } );

    // Degrade-safe: an unknown or missing status is OPEN, because a typo'd status is
    // more safely shown than silently dropped.
    test( 'a missing status is treated as open, not terminal', () {
      expect( enabledOn( null ), isNotEmpty );
      expect( enabledOn( '' ), isNotEmpty );
    } );

    test( 'status matching is case-insensitive', () {
      expect( enabledOn( 'PARKED' ), contains( 'unpark' ) );
      expect( enabledOn( 'Not_Approved' ), contains( 'approve' ) );
    } );
  } );
}
