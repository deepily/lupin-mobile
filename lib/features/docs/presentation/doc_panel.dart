import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/doc_link.dart';
import '../data/doc_repository.dart';
import 'doc_viewer_screen.dart';

/// Where a tapped doc link opens.
///
/// The document takes the right half of the screen when the phone is open. It takes the
/// bottom half when the phone is folded shut or in an ordinary tall layout.
/// Either way the conversation that linked it stays readable beside it.
/// Design: src/docs/decisions/README.md (R-DOC-panel-placement)
enum DocPanelPlacement {
  /// The document fills the right half of the screen.
  rightHalf,

  /// The document fills the bottom half of the screen.
  bottomHalf
}

/// Width, in logical pixels, at which the screen counts as open.
///
/// 600 is Material's boundary between a compact window and a medium one.
/// An unfolded Fold's inner screen is well past it and its outer screen well under it.
/// Width alone therefore tells them apart, where an aspect-ratio test would call a
/// slightly tall unfolded screen a phone.
const double docPanelSplitWidth = 600;

/// Which half a document opens in on a screen of [size].
///
/// Ensures:
///   - returns [DocPanelPlacement.bottomHalf] on a narrow screen, always
///   - on a wide screen (width >= [docPanelSplitWidth]) returns
///     [DocPanelPlacement.bottomHalf] when [belowWhenWide] (tables get the
///     full width), else [DocPanelPlacement.rightHalf]
DocPanelPlacement docPanelPlacementFor( Size size, { bool belowWhenWide = false } ) =>
    size.width >= docPanelSplitWidth && !belowWhenWide
        ? DocPanelPlacement.rightHalf
        : DocPanelPlacement.bottomHalf;

/// True when [size] is wide enough that beside-or-below is a real choice.
bool docPlacementIsChoosable( Size size ) => size.width >= docPanelSplitWidth;

/// Opens [link] in a panel over half of the screen.
///
/// The half not covered stays visible behind a light scrim.
/// Tapping it, the viewer's back arrow or the system back gesture closes the panel.
/// The panel is a [DocViewerScreen], so loading, errors and sharing behave as full screen.
///
/// Requires:
///   - link.isFetchable is true
///
/// Ensures:
///   - completes when the panel is closed
Future<void> showDocPanel( {
  required BuildContext  context,
  required DocLink       link,
  required DocRepository repository,
} ) {
  return showGeneralDialog<void>(
    context            : context,
    barrierDismissible : true,
    barrierLabel       : 'Close document',
    barrierColor       : Colors.black26,
    transitionDuration : const Duration( milliseconds: 180 ),
    pageBuilder        : ( dialogContext, _, __ ) {
      final size      = MediaQuery.sizeOf( dialogContext );
      final placement = docPanelPlacementFor( size );
      final right     = placement == DocPanelPlacement.rightHalf;
      return Align(
        alignment: right ? Alignment.centerRight : Alignment.bottomCenter,
        child: SizedBox(
          key    : const Key( TestKeys.docPanel ),
          width  : right ? size.width / 2  : size.width,
          height : right ? size.height     : size.height / 2,
          child  : Material(
            elevation    : 8,
            clipBehavior : Clip.antiAlias,
            child        : DocViewerScreen( link: link, repository: repository ),
          ),
        ),
      );
    },
  );
}
