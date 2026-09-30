/// 🔴 `PaneHostScreen` HAD NO TEST OF ANY KIND — measured 2026-09-22, it was referenced
/// only by its own file and `home_screen.dart`.
///
/// **Why that matters more than it looks.** This widget is the door for two of the five
/// fleet surfaces (`TaskListPane` and `HoldingAreaPane`). Its own header states three
/// contracts, and nothing checked any of them:
///
///   1. it gives the pane a Scaffold, so a body widget can be a navigation destination;
///   2. it provides the bloc to the pane — a pane that cannot `read` its bloc throws;
///   3. **the bloc's lifetime is the ROUTE's**, which is why `blocFactory` is a factory
///      and not an instance. Its words: *"a pane the operator has not opened must have no
///      bloc and therefore issue no requests."*
///
/// Contract 3 is the load-bearing one and the easiest to break silently: passing an
/// instance instead of a factory, or hoisting the provider above the route, leaves every
/// pane test green while a closed pane keeps polling the server.
///
/// ⚠️ THE BLOC HERE IS A CUBIT, DELIBERATELY. A `Bloc` with at least one `on<Event>`
/// handler never returns from `close()` inside a `testWidgets` body — `close()` waits on
/// handler-subscription cancellation, which completes only on the real event loop, and the
/// fake-async zone never turns while the body is parked on an await. That trap cost three
/// seats an evening each. A Cubit satisfies `StateStreamableSource` just as well, and the
/// property under test belongs to `PaneHostScreen`, not to any particular bloc.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/presentation/pane_host_screen.dart';

/// Stands in for a pane's bloc. Counts its own construction and closure so the lifetime
/// contract can be asserted rather than assumed.
class _SpyCubit extends Cubit<int> {
  _SpyCubit() : super( 0 ) { constructed += 1; }

  static int constructed = 0;
  bool closed = false;

  void bump() => emit( state + 1 );

  @override
  Future<void> close() {
    closed = true;
    return super.close();
  }
}

/// A pane in the shape the real ones take: a body widget with no Scaffold that reads its
/// bloc from the context it was given.
class _SpyPane extends StatelessWidget {
  const _SpyPane();

  @override
  Widget build( BuildContext context ) {
    final count = context.watch<_SpyCubit>().state;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text( 'count $count', key: const Key( 'spy-pane-count' ) ),
        TextButton(
          key     : const Key( 'spy-pane-bump' ),
          onPressed: () => context.read<_SpyCubit>().bump(),
          child   : const Text( 'bump' ),
        ),
      ],
    );
  }
}

void main() {
  setUp( () { _SpyCubit.constructed = 0; } );

  Widget hostUnder( { required _SpyCubit Function() factory, String title = 'Task List' } ) {
    return MaterialApp(
      home: PaneHostScreen<_SpyCubit>(
        title       : title,
        pane        : const _SpyPane(),
        blocFactory : ( _ ) => factory(),
      ),
    );
  }

  testWidgets( 'wraps the pane in a Scaffold and titles the AppBar', ( tester ) async {
    // ⚠️ NO `addTearDown( cubit.close )` HERE, AND THE OMISSION IS DELIBERATE. `BlocProvider`
    // owns the instance it is handed and closes it on dispose, so a teardown close is a
    // SECOND close — which deadlocks inside a `testWidgets` body. Measured on this file:
    // the first test hung indefinitely until the teardown was removed. The provider owning
    // the lifetime is the contract anyway, which is what the pop test below asserts.
    final cubit = _SpyCubit();

    await tester.pumpWidget( hostUnder( factory: () => cubit ) );
    await tester.pump();

    expect( find.byType( Scaffold ), findsOneWidget,
        reason: 'the panes have no Scaffold of their own on purpose — this is where it lives' );
    expect( find.widgetWithText( AppBar, 'Task List' ), findsOneWidget );
    expect( find.byType( _SpyPane ), findsOneWidget );
  } );

  testWidgets( 'provides the bloc to the pane, so the pane can read and drive it', ( tester ) async {
    final cubit = _SpyCubit();   // provider-owned; see the note in the first test

    await tester.pumpWidget( hostUnder( factory: () => cubit ) );
    await tester.pump();

    expect( find.text( 'count 0' ), findsOneWidget );

    await tester.tap( find.byKey( const Key( 'spy-pane-bump' ) ) );
    await tester.pump();

    expect( find.text( 'count 1' ), findsOneWidget,
        reason: 'if the provider were missing the pane would have thrown on read, and if it '
                'were not wired to THIS instance the tap would go nowhere visible' );
  } );

  testWidgets( '🔴 the factory is called exactly once for one mounted route', ( tester ) async {
    await tester.pumpWidget( hostUnder( factory: _SpyCubit.new ) );
    await tester.pump();

    expect( _SpyCubit.constructed, 1,
        reason: 'a rebuild must not construct a second bloc — that would restart polling and '
                'orphan the first instance' );

    // Force rebuilds of the host and confirm no second construction follows.
    await tester.tap( find.byKey( const Key( 'spy-pane-bump' ) ) );
    await tester.pump();
    await tester.tap( find.byKey( const Key( 'spy-pane-bump' ) ) );
    await tester.pump();

    expect( _SpyCubit.constructed, 1 );
    expect( find.text( 'count 2' ), findsOneWidget );
  } );

  testWidgets( '🔴 THE LIFETIME CONTRACT — popping the route closes the bloc', ( tester ) async {
    late _SpyCubit made;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: ( context ) => Scaffold(
            body: TextButton(
              key      : const Key( 'open-pane' ),
              onPressed: () => Navigator.of( context ).push(
                MaterialPageRoute<void>(
                  builder: ( _ ) => PaneHostScreen<_SpyCubit>(
                    title       : 'Holding Area',
                    pane        : const _SpyPane(),
                    blocFactory : ( _ ) { made = _SpyCubit(); return made; },
                  ),
                ),
              ),
              child: const Text( 'open' ),
            ),
          ),
        ),
      ),
    );

    // A pane the operator has NOT opened must have no bloc at all.
    expect( _SpyCubit.constructed, 0,
        reason: 'the factory must not run until the route is mounted — an unopened pane that '
                'has a bloc is an unopened pane that polls the server' );

    await tester.tap( find.byKey( const Key( 'open-pane' ) ) );
    await tester.pumpAndSettle();
    expect( _SpyCubit.constructed, 1 );
    expect( made.closed, isFalse );

    // Leaving the pane must take its bloc with it.
    Navigator.of( tester.element( find.byType( _SpyPane ) ) ).pop();
    await tester.pumpAndSettle();

    expect( made.closed, isTrue,
        reason: 'the bloc outliving its route is how a closed pane keeps issuing requests — '
                'the exact reason blocFactory is a factory and not an instance' );
  } );
}
