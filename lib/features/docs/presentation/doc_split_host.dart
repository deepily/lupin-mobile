import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/notification_audio/notification_preferences.dart';
import '../data/doc_link.dart';
import '../data/doc_models.dart';
import '../data/doc_repository.dart';
import 'doc_panel.dart';
import 'doc_viewer_screen.dart';

/// A real split, not an overlay: the child and the open document share one layout.
///
/// The child gets half the space and the document the other half, so the conversation's
/// bubbles reflow into their half and nothing is covered. A dialog over a full-width
/// layout would leave them running on behind the document.
/// Placement follows [docPanelPlacementFor]: side by side at 600 logical pixels and up,
/// stacked on a phone-shaped screen.
/// Design: src/docs/decisions/README.md (R-DOC-split-reflow)
class DocSplitHost extends StatefulWidget {
  /// The surface that shares the screen with the document.
  ///
  /// In focus mode that is the rail and the conversation.
  final Widget child;

  /// Repository handed to the viewer, resolved lazily when a document is opened.
  ///
  /// Resolving it at build time would make every screen that mounts a host require a
  /// registered DocRepository, which the conversation itself does not need.
  final DocRepository Function() repository;

  /// Where the beside-or-below choice is remembered.
  ///
  /// Null keeps it for this screen's lifetime only.
  final NotificationPreferences? prefs;

  /// Creates a split host around [child].
  const DocSplitHost( {
    super.key,
    required this.child,
    required this.repository,
    this.prefs,
  } );

  /// The nearest host, or null when there is none.
  ///
  /// A surface with no host, such as the legacy conversation screens, keeps opening
  /// documents full screen or in the panel.
  static DocSplitHostState? maybeOf( BuildContext context ) =>
      context.findAncestorStateOfType<DocSplitHostState>();

  @override
  State<DocSplitHost> createState() => DocSplitHostState();
}

/// The state behind [DocSplitHost], which callers use to open and close documents.
class DocSplitHostState extends State<DocSplitHost> {
  DocLink?    _link;
  bool        _rootsOpen = false;
  DocContent? _text;
  String?     _textTitle;
  late bool   _belowWhenWide = widget.prefs?.docsBelowWhenWide ?? false;

  // Flipping beside or below must not refetch the document over a cell network.
  // Row and Column are different parents, so without a GlobalKey Flutter would discard
  // the viewer and build a new one, whose initState fetches again. A GlobalKey moves the
  // same state to the new parent, keeping the scroll position. The conversation gets one
  // too, so opening or closing a document keeps its scroll and any half-typed reply.
  final GlobalKey _childKey = GlobalKey( debugLabel: 'doc-split-child' );
  GlobalKey       _docKey   = GlobalKey( debugLabel: 'doc-split-viewer' );

  /// True when, on a wide screen, the document sits below the conversation.
  bool get belowWhenWide => _belowWhenWide;

  /// Flips between beside and below, and remembers the choice.
  ///
  /// The viewer's title-bar toggle calls it. Narrow screens are always below, so it
  /// changes nothing there.
  void togglePlacement() {
    setState( () => _belowWhenWide = !_belowWhenWide );
    widget.prefs?.setDocsBelowWhenWide( _belowWhenWide );
  }

  /// The document currently sharing the screen, or null.
  DocLink? get link => _link;

  /// True while in-hand text (an abstract), not a fetched document, is open.
  bool get showsText => _text != null;

  /// Shows [link] beside or below the child, replacing any open document.
  void open( DocLink link ) {
    if ( !link.isFetchable ) return;
    setState( () {
      _link      = link;
      _rootsOpen = false;
      _text      = null;
      _textTitle = null;
      _docKey    = GlobalKey( debugLabel: 'doc-split-viewer' );   // a NEW document is a new viewer
    } );
  }

  /// Shows io's listing with every root unfolded above it, for the global file-viewer button.
  ///
  /// Any scope is then one tap away, and Upload is right there.
  void openRoots() {
    setState( () {
      _link      = docLinkFor( ioScope, "" );
      _rootsOpen = true;
      _text      = null;
      _textTitle = null;
      _docKey    = GlobalKey( debugLabel: 'doc-split-viewer' );
    } );
  }

  /// Shows [markdown] the caller already has, such as an abstract, in the same half.
  ///
  /// It replaces any open document.
  void openText( { required String title, required String markdown } ) {
    setState( () {
      _link      = null;
      _text      = DocContent( kind: DocContentKind.markdown, mediaType: "text/markdown", text: markdown );
      _textTitle = title;
      _docKey    = GlobalKey( debugLabel: 'doc-split-viewer' );
    } );
  }

  /// Closes the document and gives the child the whole screen back.
  void close() => setState( () {
    _link      = null;
    _text      = null;
    _textTitle = null;
  } );

  @override
  Widget build( BuildContext context ) {
    final link  = _link;
    final text  = _text;
    final child = KeyedSubtree( key: _childKey, child: widget.child );
    if ( link == null && text == null ) return child;

    final placement = docPanelPlacementFor( MediaQuery.sizeOf( context ), belowWhenWide: _belowWhenWide );
    final doc = SizedBox(
      key   : const Key( TestKeys.docPanel ),
      child : text != null
          ? DocViewerScreen(
              key        : _docKey,
              content    : text,
              title      : _textTitle,
              repository : widget.repository(),
              onClose    : close,
            )
          : DocViewerScreen(
              key        : _docKey,
              link       : link,
              repository : widget.repository(),
              onClose    : close,
              rootsOpen  : _rootsOpen,
            ),
    );

    // Equal halves with a divider, so the seam shows on both themes.
    // `Expanded` on both sides makes the child re-lay out and not keep its full width.
    return placement == DocPanelPlacement.rightHalf
      ? Row(
          key: const Key( TestKeys.docSplitRow ),
          children: [
            Expanded( child: child ),
            const VerticalDivider( width: 1 ),
            Expanded( child: doc ),
          ],
        )
      : Column(
          key: const Key( TestKeys.docSplitColumn ),
          children: [
            Expanded( child: child ),
            const Divider( height: 1 ),
            Expanded( child: doc ),
          ],
        );
  }
}
