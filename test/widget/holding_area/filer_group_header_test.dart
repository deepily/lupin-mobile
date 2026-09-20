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

Widget _header( {
  FilerGroup? group,
  String reason = '',
  String? reasonError,
  bool busy = false,
  ValueChanged<String>? onReasonChanged,
  VoidCallback? onApproveAll,
  VoidCallback? onWontFixAll,
} ) =>
    FilerGroupHeader(
      group           : group ?? _group(),
      reason          : reason,
      reasonError     : reasonError,
      busy            : busy,
      onReasonChanged : onReasonChanged ?? ( _ ) {},
      onApproveAll    : onApproveAll ?? () {},
      onWontFixAll    : onWontFixAll ?? () {},
    );

void main() {
  /// ⚠️ THE SEMANTICS TREE IS NOT BUILT UNLESS SOMETHING ASKS FOR IT. Without this
  /// handle every `getSemantics` assertion below reads an empty tree, and a test that
  /// checks TalkBack's view of a control while TalkBack's view does not exist passes for
  /// the wrong reason.
  late SemanticsHandle handle;
  setUp( () => handle = SemanticsBinding.instance.ensureSemantics() );
  tearDown( () => handle.dispose() );

  group( "the block is NOT an accordion", () {
    testWidgets( "🔴 the header exposes no expand/collapse state at all", ( tester ) async {
      // `notifications.js:14085` — *"IT IS NOT AN ACCORDION LISTENER"*. Normalising this
      // to the Task List's collapsible header would invent a state the pane does not
      // have and hide held rows behind a gesture, in the pane whose whole job is
      // showing what is still held.
      await tester.pumpPhone( _header() );

      final semantics = tester.getSemantics( find.byType( FilerGroupHeader ) );
      expect(
        semantics.hasFlag( SemanticsFlag.hasExpandedState ),
        isFalse,
        reason: 'an expanded state here would mean a collapse exists',
      );
    } );

    testWidgets( "the filer TITLE is not a tap target", ( tester ) async {
      // ⚠️ SCOPED TO THE TITLE, NOT TO THE WHOLE BLOCK. The block contains two buttons
      // and buttons contain ink — asserting "no InkWell anywhere under the header" fails
      // on the controls this pane is FOR, which is the test being wrong rather than the
      // widget. What must not be tappable is the group heading, because a tappable
      // heading is what a collapse looks like.
      await tester.pumpPhone( _header() );

      expect(
        find.ancestor( of: find.text( '$_filer · 3' ), matching: find.byType( InkWell ) ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.text( '$_filer · 3' ), matching: find.byType( GestureDetector ) ),
        findsNothing,
      );
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
    testWidgets( "🔴 is ALWAYS present, not revealed by pressing won't-fix-all", ( tester ) async {
      // Revealing it on press makes the requirement discoverable only by triggering the
      // thing it guards.
      await tester.pumpPhone( _header() );

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
