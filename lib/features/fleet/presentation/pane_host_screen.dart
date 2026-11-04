import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A Scaffold around one fleet pane, so a pane can be a navigation destination.
///
/// The panes are body widgets with no Scaffold, AppBar or route. That lets the parity
/// guard hold two of them side by side and compare their rendered cells. A Scaffold in
/// each pane would make the guard impossible to write, so the Scaffold lives here, once.
class PaneHostScreen<B extends StateStreamableSource<Object?>> extends StatelessWidget {
  /// The app bar title.
  final String title;

  /// The pane shown as the screen body.
  final Widget pane;

  /// Builds the bloc for this route.
  ///
  /// It is a factory, not an instance, so the bloc's lifetime follows the route and not
  /// whoever constructed the screen. A pane the operator has not opened then has no bloc
  /// and issues no requests.
  final B Function( BuildContext context ) blocFactory;

  /// Creates a screen that hosts [pane] under a bloc built by [blocFactory].
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
