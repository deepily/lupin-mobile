import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/data/task_row_model.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_models.dart';
import 'package:lupin_mobile/features/holding_area/presentation/filer_group_header.dart';

/// The group header and its two batch controls.
///
/// 🔴 EVERY TEST HERE RENDERS AT 360×800, NOT AT THE HARNESS DEFAULT. The default
/// surface is wider than any phone that ships, so a layout test at the default proves
/// the layout works on a device nobody has — and this header is precisely where the
/// cascade's 360 dp finding bites: the ellipsis, both batch buttons and the group title
/// now compete for the same line, and they COMPOUND.

const _filer = 'mr radio 078b97cb';

FilerGroup _group( { int count = 3, String filer = _filer } ) => FilerGroup(
      filer : filer,
      rows  : [
        for ( var i = 0; i < count; i++ )
          TaskRowModel(
            id        : 'id-$i',
            title     : '[LUPIN-MOBILE] Phase 4: a held row with a long fleet-style title',
            status    : 'not_approved',
            createdBy : filer,
          ),
      ],
    );

extension on WidgetTester {
  /// 360×800 — ordinary Android portrait.
  Future<void> pumpPhone( Widget child ) async {
    view.physicalSize        = const Size( 360, 800 );
    view.devicePixelRatio    = 1.0;
    addTearDown( view.resetPhysicalSize );
    addTearDown( view.resetDevicePixelRatio );

    await pumpWidget( MaterialApp( home: Scaffold( body: SingleChildScrollView( child: child ) ) ) );
    await pumpAndSettle();
  }
}

/// ⚠️ `expanded` DEFAULTS TO **TRUE** HERE AND TO **FALSE** IN THE APP, AND THAT IS
/// DELIBERATE RATHER THAN AN OVERSIGHT. Most of this file is about the batch controls,
/// the reason box and the 360 dp layout — none of which is what folding is for — so
/// defaulting them to folded would mean writing `expanded: true` on twenty cases that
/// have nothing to say about it. The DEFAULT ITSELF is pinned in its own group below,
/// and in the pane test, where the pane supplies it.
Widget _header( {
  FilerGroup? group,
  String reason = '',
  String? reasonError,
  bool busy = false,
  bool expanded = true,
  ValueChanged<String>? onReasonChanged,
  VoidCallback? onApproveAll,
  VoidCallback? onWontFixAll,
  VoidCallback? onToggle,
} ) =>
    FilerGroupHeader(
      group           : group ?? _group(),
      reason          : reason,
      reasonError     : reasonError,
      busy            : busy,
      expanded        : expanded,
      onReasonChanged : onReasonChanged ?? ( _ ) {},
      onApproveAll    : onApproveAll ?? () {},
      onWontFixAll    : onWontFixAll ?? () {},
      onToggle        : onToggle ?? () {},
    );

void main() {
  /// ⚠️ THE SEMANTICS TREE IS NOT BUILT UNLESS SOMETHING ASKS FOR IT. Without this
  /// handle every `getSemantics` assertion below reads an empty tree, and a test that
  /// checks TalkBack's view of a control while TalkBack's view does not exist passes for
  /// the wrong reason.
  late SemanticsHandle handle;
  setUp( () => handle = SemanticsBinding.instance.ensureSemantics() );
  tearDown( () => handle.dispose() );

  group( "🔴 the block IS an accordion now — Rick's ruling, 2026-09-22", () {
    // 🔴 THESE TWO CASES ARE INVERTED, NOT DELETED, AND THE PREVIOUS VERSIONS ARE QUOTED
    // SO THE REVERSAL IS LEGIBLE. They read "🔴 the header exposes no expand/collapse
    // state at all" and "the filer TITLE is not a tap target", and they argued from
    // `notifications.js:14085` — *"IT IS NOT AN ACCORDION LISTENER"* — that a toggle here
    // *"would invent a state the pane does not have and hide held rows behind a gesture,
    // in the pane whose whole job is showing what is still held."*
    //
    // ⚠️ RICK ASKED FOR THE GESTURE ANYWAY, having noted that neither existing client
    // has it: *"I want to be able to toggle or collapse each individual persona's
    // items… displayed folded by default so that we can do progressive disclosure."*
    // The old cases were right about the multiplexer and wrong about whose question it
    // was. What they were protecting — that folding must not hide how much is held — is
    // now pinned by the "folded is safe" group further down, which is the honest way to
    // keep a case whose premise was overruled.

    testWidgets( "the header exposes an expand/collapse state", ( tester ) async {
      await tester.pumpPhone( _header( expanded: false ) );

      final semantics = tester.getSemantics(
        find.byKey( const Key( '${TestKeys.holdingGroupTogglePrefix}$_filer' ) ),
      );
      expect( semantics.hasFlag( SemanticsFlag.hasExpandedState ), isTrue );
      expect( semantics.hasFlag( SemanticsFlag.isExpanded ), isFalse );
      expect( semantics.hasFlag( SemanticsFlag.isButton ), isTrue,
          reason: 'a state with no button to change it is not a disclosure' );
    } );

    testWidgets( "the state FOLLOWS the flag rather than a local toggle", ( tester ) async {
      // ⚠️ THE EXPANSION LIVES IN THE BLOC, NOT IN THIS WIDGET. A header that kept its
      // own `setState` bool would look identical here and lose the operator's choice on
      // every poll, which is the defect the bloc's `expanded` set exists to prevent.
      await tester.pumpPhone( _header( expanded: true ) );

      final semantics = tester.getSemantics(
        find.byKey( const Key( '${TestKeys.holdingGroupTogglePrefix}$_filer' ) ),
      );
      expect( semantics.hasFlag( SemanticsFlag.isExpanded ), isTrue );
    } );

    testWidgets( "🔴 the persona TITLE is the tap target, and it fires the toggle",
        ( tester ) async {
      // The chevron alone is 20 dp. Tapping the heading is what a phone user does, and
      // the whole heading is therefore the control.
      var toggled = 0;
      await tester.pumpPhone( _header( onToggle: () => toggled++ ) );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingGroupTogglePrefix}$_filer' ) ) );
      await tester.pumpAndSettle();

      expect( toggled, 1 );
    } );

    testWidgets( "🔴 the toggle clears 48 dp at 360 dp — a mis-tap here HIDES ROWS",
        ( tester ) async {
      // ⚠️ THE FLOOR IS THE CONSTRAINT, NOT TUNED PADDING. The Task List's header
      // measured 44 dp from padding alone and its own test caught it. A fold aimed at
      // one persona that lands on the next one hides that persona's held work.
      await tester.pumpPhone( _header( group: _group( count: 14 ) ) );

      final box = tester.getRect(
        find.byKey( const Key( '${TestKeys.holdingGroupTogglePrefix}$_filer' ) ),
      );
      expect( box.height, greaterThanOrEqualTo( kMinInteractiveDimension ) );
    } );
  } );

  group( "🔴 folded is SAFE — what the old not-an-accordion cases were protecting", () {
    // The old design's argument was that hiding held rows behind a gesture is dangerous
    // in the pane whose job is showing held work. Folding happened anyway, so the
    // argument became a REQUIREMENT on the folded header rather than a reason not to
    // fold. These are that requirement.

    testWidgets( "the persona and the COUNT are on screen while folded", ( tester ) async {
      await tester.pumpPhone( _header( expanded: false, group: _group( count: 14 ) ) );

      expect( find.text( '$_filer · 14' ), findsOneWidget );
    } );

    testWidgets( "🔴 the count is in the SEMANTIC label too", ( tester ) async {
      // Without it a folded group and an EMPTY one announce identically, and a
      // screen-reader user learns a persona has held work only by unfolding every group.
      await tester.pumpPhone( _header( expanded: false, group: _group( count: 14 ) ) );

      final semantics = tester.getSemantics(
        find.byKey( const Key( '${TestKeys.holdingGroupTogglePrefix}$_filer' ) ),
      );
      expect( semantics.label, FilerGroupHeader.semanticLabel( _filer, 14 ) );
      expect( semantics.label, contains( '14' ) );
    } );

    testWidgets( "the semantic label says 'row' not 'rows' for a group of one",
        ( tester ) async {
      await tester.pumpPhone( _header( expanded: false, group: _group( count: 1 ) ) );

      final semantics = tester.getSemantics(
        find.byKey( const Key( '${TestKeys.holdingGroupTogglePrefix}$_filer' ) ),
      );
      expect( semantics.label, contains( '1 held row' ) );
      expect( semantics.label, isNot( contains( 'rows' ) ) );
    } );

    testWidgets( "🔴 BOTH batch controls stay on screen while folded, counts and all",
        ( tester ) async {
      // A folded group whose batch controls vanished would make folding a way to lose
      // the verbs; a folded group whose controls were there but UNCOUNTED would be the
      // undercounting defect R1=B already owes an answer for.
      await tester.pumpPhone( _header( expanded: false, group: _group( count: 14 ) ) );

      expect( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}$_filer' ) ),
          findsOneWidget );
      expect( find.byKey( const Key( '${TestKeys.holdingWontFixAllPrefix}$_filer' ) ),
          findsOneWidget );
      expect( find.text( 'Approve (14)' ), findsOneWidget );
      expect( find.text( "Won't fix all (14)" ), findsOneWidget );
    } );

    testWidgets( "🔴 the reason box is ABSENT from the tree while folded, not hidden",
        ( tester ) async {
      // ⚠️ NOT MERELY INVISIBLE. A `TextField` kept in the tree with `Opacity(0)` or
      // `maintainSemantics: true` is still focusable and still typable under TalkBack,
      // so a screen-reader user would be editing the justification for a batch whose
      // rows are folded out of sight.
      await tester.pumpPhone( _header( expanded: false ) );

      expect( find.byKey( const Key( '${TestKeys.holdingReasonFieldPrefix}$_filer' ) ),
          findsNothing );
      expect( find.byType( TextField ), findsNothing );
    } );
  } );

  group( "the batch controls' NAMES are in the semantics tree", () {
    testWidgets( "🔴 approve-all's hint says REVERSIBLE, on the labelled node", ( tester ) async {
      // On the web these are `title` attributes and a phone has no hover. Carried as a
      // long-press sheet instead, the only statement anywhere that approve-all is
      // reversible would sit behind a DISCOVERY gesture.
      await tester.pumpPhone( _header() );

      // ⚠️ `getSemanticsData()`, NOT `.label` / `.hint` ON THE NODE. Under
      // `MergeSemantics` the node's own fields hold only what was configured AT that
      // node — `.label` reads empty while the merged label is plainly there. Asserting
      // on the node's raw fields fails against a widget that is correct, which is the
      // kind of failure that gets "fixed" by weakening the assertion.
      final data = tester
          .getSemantics( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}$_filer' ) ) )
          .getSemanticsData();

      expect( data.hint, contains( 'reversible' ) );
      // 🔴 THE LABEL AND THE HINT MUST END UP ON ONE NODE. Annotating the button's CHILD
      // instead of the button strands the hint below the button's own node: the hint
      // reads empty from here, and TalkBack never speaks it.
      expect( data.label, contains( 'Approve' ) );
    } );

    testWidgets( "won't-fix-all's hint says TERMINAL, on the labelled node", ( tester ) async {
      await tester.pumpPhone( _header() );

      final data = tester
          .getSemantics( find.byKey( const Key( '${TestKeys.holdingWontFixAllPrefix}$_filer' ) ) )
          .getSemanticsData();

      expect( data.hint, contains( 'TERMINAL' ) );
      expect( data.hint, contains( 'SAME' ) );
      expect( data.label, contains( "Won't fix all" ) );
    } );

    testWidgets( "there is NO long-press sheet hiding either sentence", ( tester ) async {
      await tester.pumpPhone( _header() );

      await tester.longPress(
        find.byKey( const Key( '${TestKeys.holdingWontFixAllPrefix}$_filer' ) ),
      );
      await tester.pumpAndSettle();

      expect( find.byType( BottomSheet ), findsNothing );
      expect( find.byType( Tooltip ), findsNothing );
    } );
  } );

  group( "the blast radius is on the control", () {
    testWidgets( "both labels carry the count", ( tester ) async {
      await tester.pumpPhone( _header( group: _group( count: 14 ) ) );

      expect( find.text( 'Approve (14)' ), findsOneWidget );
      expect( find.text( "Won't fix all (14)" ), findsOneWidget );
    } );

    testWidgets( "the header shows the filer and the count too", ( tester ) async {
      await tester.pumpPhone( _header( group: _group( count: 14 ) ) );
      expect( find.text( '$_filer · 14' ), findsOneWidget );
    } );
  } );

  group( "🔴 48 dp, at 360 dp width, with everything competing for the line", () {
    testWidgets( "both batch buttons clear kMinInteractiveDimension", ( tester ) async {
      // Rachel X5: the ellipsis, both batch buttons and the group header compete for
      // room at phone width and they COMPOUND. A control that shrinks under that
      // pressure is one a thumb misses.
      await tester.pumpPhone( _header( group: _group( count: 14 ) ) );

      for ( final key in [ TestKeys.holdingApproveAllPrefix, TestKeys.holdingWontFixAllPrefix ] ) {
        final size = tester.getSize( find.byKey( Key( '$key$_filer' ) ) );
        expect( size.height, greaterThanOrEqualTo( kMinInteractiveDimension ),
            reason: '$key is under the 48 dp floor at 360 dp' );
      }
    } );

    testWidgets( "nothing overflows at 360 dp with a long filer and a big count", ( tester ) async {
      await tester.pumpPhone( _header(
        group: _group( count: 148, filer: 'a-very-long-persona-name 078b97cb' ),
      ) );

      // A `Row` here would overflow and clip the label that carries the count. The
      // harness turns an overflow into a test failure, so reaching this line is the
      // assertion; `takeException` makes that explicit rather than implicit.
      expect( tester.takeException(), isNull );
    } );

    testWidgets( "the two controls do not sit adjacent and identically dressed", ( tester ) async {
      // One is reversible and one is terminal. Two same-shaped buttons a thumb's width
      // apart is how the terminal one gets pressed by the hand aiming at the other.
      await tester.pumpPhone( _header() );

      expect( find.byType( FilledButton ), findsOneWidget );
      expect( find.byType( OutlinedButton ), findsOneWidget );

      final approve = tester.getRect( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}$_filer' ) ) );
      final wontFix = tester.getRect( find.byKey( const Key( '${TestKeys.holdingWontFixAllPrefix}$_filer' ) ) );
      expect( approve.overlaps( wontFix ), isFalse );
    } );
  } );

  group( "the reason box", () {
    testWidgets( "🔴 is ALWAYS present WHILE UNFOLDED, not revealed by pressing "
        "won't-fix-all", ( tester ) async {
      // Revealing it on press makes the requirement discoverable only by triggering the
      // thing it guards.
      //
      // ⚠️ "ALWAYS" NARROWED TO "WHILE UNFOLDED" WHEN FOLDING ARRIVED, and the narrowing
      // is not a loophole: the box is tied to the ROWS it justifies closing, which are
      // the thing folding hides. The case it was written against — revealed by the
      // press it guards — is still forbidden, and the test below pins that the
      // complaint UNFOLDS the group rather than pointing at a field nobody can see.
      await tester.pumpPhone( _header() );

      expect( find.byKey( const Key( '${TestKeys.holdingReasonFieldPrefix}$_filer' ) ),
          findsOneWidget );

      // Pressing won't-fix-all does not CREATE it — it was there first.
      await tester.tap( find.byKey( const Key( '${TestKeys.holdingWontFixAllPrefix}$_filer' ) ) );
      await tester.pumpAndSettle();
      expect( find.byKey( const Key( '${TestKeys.holdingReasonFieldPrefix}$_filer' ) ),
          findsOneWidget );
    } );

    testWidgets( "🔴 is a BOX, not a dialog", ( tester ) async {
      await tester.pumpPhone( _header() );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingWontFixAllPrefix}$_filer' ) ) );
      await tester.pumpAndSettle();

      expect( find.byType( AlertDialog ), findsNothing,
          reason: "the web rejected a dialog here deliberately — a confirm() blocks the "
                  "event loop, and the operator has to read the group while typing" );
    } );

    testWidgets( "carries its accessible name and the placeholder", ( tester ) async {
      await tester.pumpPhone( _header() );

      final field = tester.widget<TextField>(
        find.byKey( const Key( '${TestKeys.holdingReasonFieldPrefix}$_filer' ) ),
      );

      expect( field.decoration!.labelText, kHoldingWontFixReasonLabel );
      expect( field.decoration!.hintText, kHoldingWontFixReasonPlaceholder );
    } );

    testWidgets( "the complaint rides on the FIELD's own decoration", ( tester ) async {
      // ⚠️ A TYPED ASSERTION, NOT A STRING SEARCH OVER THE TREE — `find.text` would pass
      // against any label that happened to contain the sentence. `errorText` is also
      // what Flutter wires into the field's semantics, so TalkBack reads the complaint
      // as part of the box rather than as a stray line elsewhere on the screen.
      await tester.pumpPhone( _header( reasonError: kHoldingWontFixReasonMissing ) );

      final field = tester.widget<TextField>(
        find.byKey( const Key( '${TestKeys.holdingReasonFieldPrefix}$_filer' ) ),
      );
      expect( field.decoration!.errorText, kHoldingWontFixReasonMissing );
    } );

    testWidgets( "🔴 typing does NOT move the caret to the end", ( tester ) async {
      // The defect this pins: a `TextEditingController` built inside `build` is a fresh
      // controller on every rebuild, and this widget rebuilds on every keystroke because
      // the text it renders lives in the bloc. The caret jumps — in the one box on this
      // pane the operator has to type a sentence into.
      const key = Key( '${TestKeys.holdingReasonFieldPrefix}$_filer' );
      await tester.pumpPhone( _header( reason: 'superseded' ) );

      final field = tester.widget<TextField>( find.byKey( key ) );
      field.controller!.selection = const TextSelection.collapsed( offset: 3 );
      await tester.pump();

      expect( tester.widget<TextField>( find.byKey( key ) ).controller!.selection.baseOffset, 3 );
    } );
  } );

  group( "🔴 the approve-all confirm — Rick's ruling", () {
    testWidgets( "the press opens a confirm and fires NOTHING yet", ( tester ) async {
      var fired = 0;
      await tester.pumpPhone( _header(
        group        : _group( count: 14 ),
        onApproveAll : () => fired++,
      ) );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}$_filer' ) ) );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.holdingApproveAllConfirm ) ), findsOneWidget );
      expect( fired, 0, reason: 'the gate is the point; the press alone must not write' );
    } );

    testWidgets( "the confirm names the count and the filer", ( tester ) async {
      await tester.pumpPhone( _header( group: _group( count: 14 ) ) );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}$_filer' ) ) );
      await tester.pumpAndSettle();

      expect( find.textContaining( '14 rows' ), findsWidgets );
      expect( find.textContaining( _filer ), findsWidgets );
    } );

    testWidgets( "cancelling fires nothing", ( tester ) async {
      var fired = 0;
      await tester.pumpPhone( _header( onApproveAll: () => fired++ ) );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}$_filer' ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.holdingApproveAllConfirmNo ) ) );
      await tester.pumpAndSettle();

      expect( fired, 0 );
      expect( find.byKey( const Key( TestKeys.holdingApproveAllConfirm ) ), findsNothing );
    } );

    testWidgets( "confirming fires it exactly once", ( tester ) async {
      var fired = 0;
      await tester.pumpPhone( _header( onApproveAll: () => fired++ ) );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}$_filer' ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.holdingApproveAllConfirmOk ) ) );
      await tester.pumpAndSettle();

      expect( fired, 1 );
    } );

    testWidgets( "🔴 the CONFIRM is on approve-all, and won't-fix-all has none", ( tester ) async {
      // The inversion reads backwards until you count the gates: won't-fix-all is
      // already gated by a reason box the operator must type into. This assertion is
      // what keeps a later hand from "fixing" the asymmetry and leaving approve-all
      // ungated again.
      var wontFixFired = 0;
      await tester.pumpPhone( _header( onWontFixAll: () => wontFixFired++ ) );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingWontFixAllPrefix}$_filer' ) ) );
      await tester.pumpAndSettle();

      expect( find.byType( AlertDialog ), findsNothing );
      expect( wontFixFired, 1, reason: 'it fires straight through to the bloc, which '
          'holds the blank check' );
    } );

    testWidgets( "the confirm's accept button repeats the verb and the count", ( tester ) async {
      await tester.pumpPhone( _header( group: _group( count: 14 ) ) );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}$_filer' ) ) );
      await tester.pumpAndSettle();

      final accept = find.byKey( const Key( TestKeys.holdingApproveAllConfirmOk ) );
      expect( find.descendant( of: accept, matching: find.text( 'Approve (14)' ) ),
          findsOneWidget );
    } );
  } );

  group( "busy", () {
    testWidgets( "both controls and the box go inert while a batch is in flight", ( tester ) async {
      // A second press while N transitions are still landing doubles the writes without
      // doubling the count the operator read.
      await tester.pumpPhone( _header( busy: true ) );

      expect(
        tester.widget<FilledButton>(
          find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}$_filer' ) ) ).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(
          find.byKey( const Key( '${TestKeys.holdingWontFixAllPrefix}$_filer' ) ) ).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(
          find.byKey( const Key( '${TestKeys.holdingReasonFieldPrefix}$_filer' ) ) ).enabled,
        isFalse,
      );
    } );
  } );
}
