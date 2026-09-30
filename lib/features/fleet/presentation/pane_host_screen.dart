import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A Scaffold around one fleet pane, so a pane can be a navigation destination.
///
/// 🔴 WHY THIS EXISTS AT ALL. Phases 2 through 5 each built a PANE — a body widget with
/// no Scaffold, no AppBar and no route. Every one of them was tested, merged and green,
/// and not one of them could be opened on a phone: measured 2026-09-22, `TaskListPane`,
/// `HoldingAreaPane`, `FinishedTasksScreen` and `BroadcastPane` were referenced ONLY by
/// their own file and their tests. Four phases of work behind a door nobody had built.
///
/// ⚠️ A PANE IS NOT A SCREEN, AND THAT DISTINCTION IS WORTH KEEPING. The panes are body
/// widgets on purpose — it is what lets the parity guard hold two of them side by side
/// and compare their rendered cells to each other. Giving each one its own Scaffold
/// would have made that guard impossible to write. So the Scaffold lives HERE, once,
/// and the panes stay comparable.
class PaneHostScreen<B extends StateStreamableSource<Object?>> extends StatelessWidget {
  final String title;
  final Widget pane;

  /// Builds the bloc for this route.
  ///
  /// ⚠️ A FACTORY, NOT AN INSTANCE. Passing an instance would tie the bloc's lifetime to
  /// whoever constructed the screen rather than to the route, which is exactly the
  /// property the polling panes need — a pane the operator has not opened must have no
  /// bloc and therefore issue no requests.
  final B Function( BuildContext context ) blocFactory;

  const PaneHostScreen( {
    super.key,
    required this.title,
    required this.pane,
    required this.blocFactory,
  } );

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar : AppBar( title: Text( title ) ),
      body   : BlocProvider<B>(
        create : blocFactory,
        child  : pane,
      ),
    );
  }
}
