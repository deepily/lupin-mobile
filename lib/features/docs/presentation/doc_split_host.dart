import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/notification_audio/notification_preferences.dart';
import '../data/doc_link.dart';
import '../data/doc_models.dart';
import '../data/doc_repository.dart';
import 'doc_panel.dart';
import 'doc_viewer_screen.dart';

/// A REAL split, not an overlay (rows 2416d2c5 / e0843a8a — Rick: "the
/// notification bubbles are still covered up by the doc link document, when
/// they should re-render in the leftmost 50%").
///
/// The first fix opened the document in a half-screen dialog. The document sat
/// in the right half, but the conversation underneath was still laid out at
/// full width, so the bubbles it was meant to keep readable ran on behind it.
/// This host instead puts both in one layout: the child is given half the
/// space and the document the other half, so the bubbles reflow into their
/// half and nothing is occluded.
///
/// Placement follows [docPanelPlacementFor]: side by side at 600 logical
/// pixels and up (an unfolded Fold), stacked on a phone-shaped screen.
class DocSplitHost extends StatefulWidget {
  /// The surface that shares the screen with the document — the rail and the
  /// conversation, in focus mode.
  final Widget child;

  /// Repository handed to the viewer, resolved LAZILY — only when a document
  /// is actually opened. A host that resolved it at build time would make
  /// every screen that mounts one require a registered DocRepository, which
  /// is a dependency the conversation itself does not have.
  final DocRepository Function() repository;

  /// Where the beside/below choice is remembered. Null keeps it for this
  /// screen's lifetime only (tests, and surfaces without preferences).
  final NotificationPreferences? prefs;

  const DocSplitHost( {
    super.key,
    required this.child,
    required this.repository,
    this.prefs,
  } );

  /// The nearest host, or null when there is none. A surface with no host
  /// (the legacy conversation screens) keeps opening documents full screen
  /// or in the panel — nothing is forced to adopt the split.
  static DocSplitHostState? maybeOf( BuildContext context ) =>
      context.findAncestorStateOfType<DocSplitHostState>();

  @override
  State<DocSplitHost> createState() => DocSplitHostState();
}

class DocSplitHostState extends State<DocSplitHost> {
  DocLink?    _link;
  DocContent? _text;
  String?     _textTitle;
  late bool   _belowWhenWide = widget.prefs?.docsBelowWhenWide ?? false;

  // Rick 2026-09-18: flipping beside ⇄ below RE-FETCHED the document — over a
  // cell network, for a layout change. Row and Column are different parents,
  // so without a GlobalKey Flutter throws the viewer away and builds a new
  // one, whose initState fetches again. A GlobalKey moves the SAME state to
  // the new parent: no refetch, scroll position kept. The conversation gets
  // one too, so opening or closing a document stops resetting its scroll and
  // any half-typed reply.
  final GlobalKey _childKey = GlobalKey( debugLabel: 'doc-split-child' );
  GlobalKey       _docKey   = GlobalKey( debugLabel: 'doc-split-viewer' );

  /// On a wide screen, does the document sit below the conversation?
  bool get belowWhenWide => _belowWhenWide;

  /// Flip beside ⇄ below, and remember it (Rick 2026-09-18: the viewer's
  /// title-bar toggle). Narrow screens are always below; this changes them
  /// nothing.
  void togglePlacement() {
    setState( () => _belowWhenWide = !_belowWhenWide );
    widget.prefs?.setDocsBelowWhenWide( _belowWhenWide );
  }

  /// The document currently sharing the screen, or null.
  DocLink? get link => _link;

  /// True while in-hand text (an abstract), not a fetched document, is open.
  bool get showsText => _text != null;

  /// Show [link] beside (or below) the child, replacing any open document.
  void open( DocLink link ) {
    if ( !link.isFetchable ) return;
    setState( () {
      _link      = link;
      _text      = null;
      _textTitle = null;
      _docKey    = GlobalKey( debugLabel: 'doc-split-viewer' );   // a NEW document is a new viewer
    } );
  }

  /// Show [markdown] the caller already has — a notification's abstract —
  /// in the same half, replacing any open document (Rick 2026-09-18).
  void openText( { required String title, required String markdown } ) {
    setState( () {
      _link      = null;
      _text      = DocContent( kind: DocContentKind.markdown, mediaType: "text/markdown", text: markdown );
      _textTitle = title;
      _docKey    = GlobalKey( debugLabel: 'doc-split-viewer' );
    } );
  }

  /// Close the document and give the child the whole screen back.
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
            ),
    );

    // Equal halves, and a divider so the seam is visible on both themes.
    // `Expanded` on both sides is what makes the child RE-LAY OUT rather than
    // keep its full-width layout under a panel.
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
