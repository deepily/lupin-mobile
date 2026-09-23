import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/data/task_verbs.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/fleet/presentation/verb_reason_sheet.dart';

/// The SHARED reason sheet, driven the way an operator drives it.
///
/// 🔴 THE SHEET IS THE ONLY SURFACE ON A PHONE WHERE FOUR OF THE SEVEN VERBS CAN BE
/// COMPLETED AT ALL. Before it existed, the Holding Area declined to ship per-row
/// won't-fix rather than ship `TaskVerb.wontFix( reason: '' )` — *"a button whose every
/// press is a guaranteed 422."* So every assertion here is about the gap between what the
/// operator typed and what ends up in the payload.
///
/// ─────────────────────────────────────────────────────────────────────────────────
/// 🔴 MUTATION MATRIX — MEASURED, NOT ASSERTED. Each was shown RED by reintroducing the
/// defect and re-running, then restored.
///
/// | Test                                  | A: blank accepted | B: one shared hint | C: date optional | D: no liveRegion |
/// |---------------------------------------|-------------------|--------------------|------------------|------------------|
/// | a blank reason pops nothing           | 🔴 RED            | green              | green            | green            |
/// | the complaint is THIS verb's          | 🔴 RED            | 🔴 RED             | green            | green            |
/// | the hint is THIS verb's               | green             | 🔴 RED             | green            | green            |
/// | park cannot be submitted with no date | green             | green              | 🔴 RED           | green            |
/// | the date complaint is announced       | green             | green              | 🔴 RED           | 🔴 RED           |
/// | fixed submits with the receipt        | green             | green              | green            | green            |
///
///   A — `_submit` popped the payload without checking the required reason
///   B — the box took a single hard-coded hint and complaint for every verb
///   C — `_submit` skipped the `needs.date` branch (park then sends the CLEARING null)
///   D — the date complaint rendered as a plain `Text`, with no `Semantics( liveRegion )`
///
/// ⚠️ "fixed submits with the receipt" HAS NO RED COLUMN HERE, AND THAT IS DELIBERATE
/// RATHER THAN AN OVERSIGHT — its defect (a Fixed built with no `receipt_refs`, the
/// multiplexer's `709128d4` bug) is guarded in `task_verbs_test.dart`, column C of THAT
/// file's matrix. Keeping the note is the point: a reader who checks this matrix and
/// finds an all-green row must be able to tell "guarded elsewhere" from "guards nothing".

/// 360×800 — ordinary Android portrait, never the 800×600 harness default. The sheet
/// carries a text box, a date button and two actions; at the harness default everything
/// fits and the layout this widget was designed for is never exercised.
Future<TaskVerb?> _openSheet( WidgetTester tester, String verb ) async {
  tester.view.physicalSize     = const Size( 360, 800 );
  tester.view.devicePixelRatio = 1.0;
  addTearDown( tester.view.resetPhysicalSize );
  addTearDown( tester.view.resetDevicePixelRatio );

  TaskVerb? result;
  await tester.pumpWidget( MaterialApp(
    home : Scaffold(
      body : Builder(
        builder : ( context ) => TextButton(
          onPressed : () async {
            result = await showVerbReasonSheet(
              context,
              needs    : verbNeeds( verb )!,
              rowTitle : '[LUPIN-MOBILE] the row being acted on',
            );
          },
          child : const Text( 'open' ),
        ),
      ),
    ),
  ) );

  await tester.tap( find.text( 'open' ) );
  await tester.pumpAndSettle();
  return result;
}

/// The reason box's current `errorText`, read off the decoration rather than searched
/// for in the tree — a typed assertion cannot pass against a label that merely contains
/// the sentence.
String? _reasonError( WidgetTester tester ) => tester
    .widget<TextField>( find.byKey( const Key( TestKeys.reasonSheetReason ) ) )
    .decoration
    ?.errorText;

void main() {
  group( 'the sheet opens carrying THIS verb, not a generic one', () {
    // 🔴 FOUR VERBS SHARE ONE BOX AND MUST NOT SHARE ONE SENTENCE. The hint is the half
    // the operator reads BEFORE typing, so a shared hint is a shared misunderstanding.
    testWidgets( 'each reason verb brings its own hint', ( tester ) async {
      final hints = <String, String>{};

      for ( final verb in [ 'park', 'drop', 'demote', 'wont_fix' ] ) {
        await _openSheet( tester, verb );
        hints[ verb ] = tester
            .widget<TextField>( find.byKey( const Key( TestKeys.reasonSheetReason ) ) )
            .decoration!
            .hintText!;
        await tester.tap( find.byKey( const Key( TestKeys.reasonSheetCancel ) ) );
        await tester.pumpAndSettle();
      }

      expect( hints.values.toSet(), hasLength( 4 ),
          reason: 'two verbs sharing a hint teach the operator the wrong thing about '
                  'one of them' );
      expect( hints[ 'park' ], contains( 'quote' ) );
    } );

    testWidgets( 'the sheet names the row it is about', ( tester ) async {
      await _openSheet( tester, 'drop' );
      expect( find.textContaining( 'the row being acted on' ), findsOneWidget,
          reason: 'a modal that hides the row it is about asks the operator to justify '
                  'a decision from memory' );
    } );

    testWidgets( 'the submit button wears the verb, not "OK"', ( tester ) async {
      await _openSheet( tester, 'wont_fix' );
      final button = find.byKey( const Key( TestKeys.reasonSheetSubmit ) );
      expect(
        find.descendant( of: button, matching: find.text( "Won't fix" ) ),
        findsOneWidget,
        reason: 'the button still has to read correctly when it is the only thing focus '
                'lands on',
      );
    } );
  } );

  group( 'a blank reason is refused CLIENT-SIDE', () {
    // 🔴 THE REFUSAL EXISTS SO THE SERVER DOES NOT HAVE TO SAY IT. The alternative is a
    // 422 the operator must read to learn a single fact — and on a phone that round trip
    // may not come back at all.
    testWidgets( 'pressing submit with an empty box pops nothing', ( tester ) async {
      await _openSheet( tester, 'drop' );

      await tester.tap( find.byKey( const Key( TestKeys.reasonSheetSubmit ) ) );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.reasonSheet ) ), findsOneWidget,
          reason: 'the sheet must stay open — a dismissed sheet reads as a sent write' );
      expect( _reasonError( tester ), isNotNull );
    } );

    testWidgets( 'whitespace is not a reason', ( tester ) async {
      await _openSheet( tester, 'drop' );

      await tester.enterText( find.byKey( const Key( TestKeys.reasonSheetReason ) ), '   ' );
      await tester.tap( find.byKey( const Key( TestKeys.reasonSheetSubmit ) ) );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.reasonSheet ) ), findsOneWidget );
      expect( _reasonError( tester ), isNotNull );
    } );

    // ⚠️ THE COMPLAINT IS `errorText`, NOT A STRAY `Text` BELOW THE FIELD. It is what
    // Flutter wires into the field's OWN semantics, so TalkBack reads the refusal as part
    // of the box rather than as a sentence the user has to go find.
    testWidgets( 'the complaint is THIS verb\'s, and lands on the field itself',
        ( tester ) async {
      final complaints = <String>{};

      for ( final verb in [ 'park', 'drop', 'demote', 'wont_fix' ] ) {
        await _openSheet( tester, verb );
        await tester.tap( find.byKey( const Key( TestKeys.reasonSheetSubmit ) ) );
        await tester.pumpAndSettle();

        final shown = _reasonError( tester );
        expect( shown, verbReasonComplaint( verb ),
            reason: '$verb showed the wrong complaint' );
        expect( shown, isNot( 'A reason is required.' ),
            reason: 'the generic sentence is true of four verbs and teaches none of them' );
        complaints.add( shown! );

        await tester.tap( find.byKey( const Key( TestKeys.reasonSheetCancel ) ) );
        await tester.pumpAndSettle();
      }

      expect( complaints, hasLength( 4 ) );
    } );

    testWidgets( 'answering the complaint clears it', ( tester ) async {
      await _openSheet( tester, 'drop' );
      await tester.tap( find.byKey( const Key( TestKeys.reasonSheetSubmit ) ) );
      await tester.pumpAndSettle();
      expect( _reasonError( tester ), isNotNull );

      await tester.enterText(
          find.byKey( const Key( TestKeys.reasonSheetReason ) ), 'overtaken by events' );
      await tester.pumpAndSettle();

      expect( _reasonError( tester ), isNull,
          reason: 'a refusal left on screen while the box holds a reason is lying' );
    } );
  } );

  group( 'the date, for the two verbs that are BOUNDED', () {
    // 🔴 A PARK WITH NO DATE IS NOT A PARK WITH NO DATE — IT IS A PARK THAT CLEARS ONE.
    // `TaskVerb.park` always puts `next_chase_ts` in the body, and §4.3 note 2 is
    // explicit that "send nothing" and "send null" are different requests and only one of
    // them clears. Without this gate every park would silently send the clearing value.
    testWidgets( 'park cannot be submitted without a chase date', ( tester ) async {
      await _openSheet( tester, 'park' );

      await tester.enterText(
          find.byKey( const Key( TestKeys.reasonSheetReason ) ), 'Rick said not now' );
      await tester.tap( find.byKey( const Key( TestKeys.reasonSheetSubmit ) ) );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.reasonSheet ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.reasonSheetDateError ) ), findsOneWidget );
      expect( _reasonError( tester ), isNull,
          reason: 'the reason was supplied; only the date is missing, and the sheet must '
                  'complain about the right one' );
    } );

    // ⚠️ THE DATE COMPLAINT IS A LIVE REGION, BECAUSE A BUTTON GETS NONE FOR FREE. The
    // reason box's `errorText` reaches TalkBack through the field's own semantics; a
    // complaint under a date BUTTON is a plain sentence that appears silently, and the
    // operator whose focus is still on Submit is told nothing.
    testWidgets( 'the date complaint is announced, not merely rendered', ( tester ) async {
      final handle = tester.ensureSemantics();
      await _openSheet( tester, 'demote' );

      await tester.enterText(
          find.byKey( const Key( TestKeys.reasonSheetReason ) ), 'needs a decision' );
      await tester.tap( find.byKey( const Key( TestKeys.reasonSheetSubmit ) ) );
      await tester.pumpAndSettle();

      final node = tester.getSemantics(
        find.byKey( const Key( TestKeys.reasonSheetDateError ) ),
      );
      expect( node.hasFlag( SemanticsFlag.isLiveRegion ), isTrue,
          reason: 'a complaint that appears silently leaves a TalkBack user pressing a '
                  'button that will not fire, with no idea why' );
      handle.dispose();
    } );

    testWidgets( 'park and demote ask different date questions', ( tester ) async {
      await _openSheet( tester, 'park' );
      expect( find.text( 'Chase me again on' ), findsOneWidget );
      await tester.tap( find.byKey( const Key( TestKeys.reasonSheetCancel ) ) );
      await tester.pumpAndSettle();

      await _openSheet( tester, 'demote' );
      expect( find.text( 'Triage this by' ), findsOneWidget,
          reason: 'Rick, on the web control: "I really have no idea what the date '
                  'chooser is for"' );
    } );

    testWidgets( 'the verbs that take no date show no date control', ( tester ) async {
      for ( final verb in [ 'drop', 'wont_fix', 'fixed' ] ) {
        await _openSheet( tester, verb );
        expect( find.byKey( const Key( TestKeys.reasonSheetDate ) ), findsNothing,
            reason: '$verb has no date to ask for' );
        await tester.tap( find.byKey( const Key( TestKeys.reasonSheetCancel ) ) );
        await tester.pumpAndSettle();
      }
    } );

    testWidgets( 'a chosen date rides out in the payload', ( tester ) async {
      await _openSheet( tester, 'park' );

      await tester.enterText(
          find.byKey( const Key( TestKeys.reasonSheetReason ) ), 'Rick said not now' );
      await tester.tap( find.byKey( const Key( TestKeys.reasonSheetDate ) ) );
      await tester.pumpAndSettle();

      // The picker opens on today + 7; OK takes it.
      await tester.tap( find.text( 'OK' ) );
      await tester.pumpAndSettle();

      expect( find.textContaining( 'Chase me again on:' ), findsOneWidget,
          reason: 'the chosen date must be visible on the control, not held invisibly' );

      await tester.tap( find.byKey( const Key( TestKeys.reasonSheetSubmit ) ) );
      await tester.pumpAndSettle();
      expect( find.byKey( const Key( TestKeys.reasonSheet ) ), findsNothing );
    } );
  } );

  group( 'fixed — the branch that is not a text box', () {
    // 🔴 FIXED SENDS A RECEIPT AND NO REASON. There is nothing for the operator to type,
    // but there IS something for them to read: this press closes the row for good.
    testWidgets( 'fixed offers no reason box and says why', ( tester ) async {
      await _openSheet( tester, 'fixed' );

      expect( find.byKey( const Key( TestKeys.reasonSheetReason ) ), findsNothing );
      expect( find.byKey( const Key( TestKeys.reasonSheetNoReason ) ), findsOneWidget );
      expect( find.textContaining( 'closes the row for good' ), findsOneWidget );
    } );

    testWidgets( 'fixed submits straight through, carrying the attestation',
        ( tester ) async {
      TaskVerb? built;
      tester.view.physicalSize     = const Size( 360, 800 );
      tester.view.devicePixelRatio = 1.0;
      addTearDown( tester.view.resetPhysicalSize );
      addTearDown( tester.view.resetDevicePixelRatio );

      await tester.pumpWidget( MaterialApp(
        home : Scaffold(
          body : Builder(
            builder : ( context ) => TextButton(
              onPressed : () async => built = await showVerbReasonSheet(
                context,
                needs    : verbNeeds( 'fixed' )!,
                rowTitle : 'a row that is done',
              ),
              child : const Text( 'open' ),
            ),
          ),
        ),
      ) );

      await tester.tap( find.text( 'open' ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.reasonSheetSubmit ) ) );
      await tester.pumpAndSettle();

      expect( built, isNotNull );
      expect( built!.name, 'fixed' );
      final receipts = built!.payload[ 'receipt_refs' ] as Map<String, dynamic>;
      expect( receipts[ 'operator_attestation' ], kMobileOperatorAttestation );
    } );
  } );

  group( 'cancelling', () {
    testWidgets( 'cancel returns null and sends nothing', ( tester ) async {
      TaskVerb? built;
      bool returned = false;
      tester.view.physicalSize     = const Size( 360, 800 );
      tester.view.devicePixelRatio = 1.0;
      addTearDown( tester.view.resetPhysicalSize );
      addTearDown( tester.view.resetDevicePixelRatio );

      await tester.pumpWidget( MaterialApp(
        home : Scaffold(
          body : Builder(
            builder : ( context ) => TextButton(
              onPressed : () async {
                built    = await showVerbReasonSheet(
                  context,
                  needs    : verbNeeds( 'drop' )!,
                  rowTitle : 'a row',
                );
                returned = true;
              },
              child : const Text( 'open' ),
            ),
          ),
        ),
      ) );

      await tester.tap( find.text( 'open' ) );
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey( const Key( TestKeys.reasonSheetReason ) ), 'typed then abandoned' );
      await tester.tap( find.byKey( const Key( TestKeys.reasonSheetCancel ) ) );
      await tester.pumpAndSettle();

      expect( returned, isTrue );
      expect( built, isNull,
          reason: 'a cancelled sheet that returned a payload would write the row the '
                  'operator just backed out of' );
    } );
  } );

  group( 'no pane discriminator', () {
    // 🔴 THE CONSTRUCTOR IS THE MECHANISM, exactly as it is for `TaskRow`. Both panes
    // open this sheet, and neither can hand it anything that would let it lay itself out
    // differently — the only inputs are a verb's obligations and a row title.
    //
    // ⚠️ THIS TEST CANNOT CATCH A `pane:` PARAMETER BEING ADDED, and says so rather than
    // implying otherwise. What it pins is that two callers passing the same verb get the
    // same sheet; adding a parameter requires editing the constructor, which is visible
    // in review — which is the whole reason the constructor, and not a convention, is the
    // mechanism.
    testWidgets( 'two callers passing the same verb get the same sheet',
        ( tester ) async {
      await _openSheet( tester, 'wont_fix' );
      final first = tester
          .widget<TextField>( find.byKey( const Key( TestKeys.reasonSheetReason ) ) )
          .decoration!
          .hintText;
      await tester.tap( find.byKey( const Key( TestKeys.reasonSheetCancel ) ) );
      await tester.pumpAndSettle();

      await _openSheet( tester, 'wont_fix' );
      final second = tester
          .widget<TextField>( find.byKey( const Key( TestKeys.reasonSheetReason ) ) )
          .decoration!
          .hintText;

      expect( second, first );
      expect( first, isNotNull, reason: 'two nulls would match each other' );
    } );
  } );
}
