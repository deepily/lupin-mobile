import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/testing/test_keys.dart';
import '../data/doc_link.dart';
import '../data/doc_models.dart';
import '../data/doc_repository.dart';
import 'doc_link_tap.dart';

/// Full-screen viewer for a document reached from a notification abstract.
///
/// Polymorphic by content type: markdown renders as markdown, source renders as
/// monospaced text, images render as bytes. HTML and directory listings arrive
/// in P4; until then they fall back to a readable source view rather than an
/// error, because showing the bytes is always better than showing nothing.
class DocViewerScreen extends StatefulWidget {
  /// The document to fetch. Null when [content] is already in hand.
  final DocLink?       link;
  final DocRepository? repository;

  /// Content the caller already has — a notification's abstract (Rick
  /// 2026-09-18: tapping the abstract icon should render the abstract the way
  /// a document renders). Shown as-is; nothing is fetched.
  final DocContent? content;

  /// App-bar title. Defaults to the link's file name.
  final String? title;

  /// Set when the viewer shares the screen instead of owning a route (the
  /// 50/50 split, rows 2416d2c5 / e0843a8a): there is nothing to pop, so the
  /// app bar needs its own close button. Null keeps the plain route behaviour.
  final VoidCallback? onClose;

  const DocViewerScreen( {
    super.key,
    this.link,
    this.repository,
    this.content,
    this.title,
    this.onClose,
  } ) : assert( content != null || ( link != null && repository != null ),
                'give the viewer either content or a link and a repository to fetch it' );

  /// What the app bar shows, and the shared file's name.
  String get displayTitle => title ?? link?.displayName ?? "Document";

  @override
  State<DocViewerScreen> createState() => _DocViewerScreenState();
}

class _DocViewerScreenState extends State<DocViewerScreen> {
  // Explicit load state rather than a FutureBuilder. A FutureBuilder does not
  // subscribe to a future handed to it by setState until the NEXT frame, so a
  // fetch that rejects immediately — a 400 refusal answered from cache, say —
  // completes before anything is listening and surfaces as an unhandled async
  // error instead of the error view. Awaiting here means the result is always
  // observed.
  DocContent? _content;
  Object?     _error;
  bool        _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inHand = widget.content;
    if ( inHand != null ) {
      setState( () {
        _content = inHand;
        _error   = null;
        _loading = false;
      } );
      return;
    }

    setState( () {
      _loading = true;
      _error   = null;
      _content = null;
    } );

    try {
      final content = await widget.repository!.fetch( widget.link! );
      if ( !mounted ) return;
      setState( () {
        _content = content;
        _loading = false;
      } );
    } catch ( e ) {
      if ( !mounted ) return;
      setState( () {
        _error   = e;
        _loading = false;
      } );
    }
  }

  Future<void> _share( DocContent content ) async {
    // Only text is shareable as a file today; an image share would need its own
    // extension handling and is not worth guessing at.
    if ( content.text == null ) return;
    try {
      final dir  = await getTemporaryDirectory();
      final name = widget.link?.displayName ?? "${widget.displayTitle.replaceAll( RegExp( r'[^A-Za-z0-9._-]+' ), '-' )}.md";
      final file = File( "${dir.path}/$name" );
      await file.writeAsString( content.text! );
      await Share.shareXFiles( [ XFile( file.path ) ] );
    } catch ( e ) {
      if ( mounted ) {
        ScaffoldMessenger.of( context ).showSnackBar(
          SnackBar( content: Text( "Share failed: $e" ), backgroundColor: Colors.red ),
        );
      }
    }
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      key: const Key( TestKeys.docViewerScreen ),
      appBar: AppBar(
        leading: widget.onClose == null ? null : IconButton(
          key      : const Key( TestKeys.docViewerCloseButton ),
          icon     : const Icon( Icons.close ),
          tooltip  : "Close document",
          onPressed: widget.onClose,
        ),
        title: Text( widget.displayTitle, overflow: TextOverflow.ellipsis ),
        actions: [
          if ( _content?.text != null )
            IconButton(
              key      : const Key( TestKeys.docViewerShareButton ),
              icon     : const Icon( Icons.share_outlined ),
              tooltip  : "Share",
              onPressed: () => _share( _content! ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if ( _loading )        return const Center( child: CircularProgressIndicator() );
    if ( _error != null )  return _ErrorView( error: _error!, onRetry: _load );
    return _ContentView( content: _content!, repository: widget.repository );
  }
}

/// Renders one fetched document according to its kind.
class _ContentView extends StatelessWidget {
  final DocContent     content;
  final DocRepository? repository;

  const _ContentView( { required this.content, this.repository } );

  @override
  Widget build( BuildContext context ) {
    switch ( content.kind ) {
      case DocContentKind.markdown:
        return Markdown(
          key       : const Key( TestKeys.docViewerMarkdown ),
          data      : content.text ?? "",
          selectable: true,
          padding   : const EdgeInsets.all( 16 ),
          // Links are live here too: an abstract's doc link now lives only in
          // the viewer (Rick 2026-09-18, progressive disclosure), so a tap on
          // it opens the document in place of the abstract.
          onTapLink : ( text, href, title ) {
            if ( href != null ) openMarkdownHref( context: context, href: href, repository: repository );
          },
        );

      case DocContentKind.image:
        return Center(
          child: InteractiveViewer(
            child: Image.memory(
              _asBytes( content.bytes ),
              key: const Key( TestKeys.docViewerImage ),
            ),
          ),
        );

      // HTML and directory listings land here until P4 gives each its own
      // renderer. Showing the source beats showing an error.
      case DocContentKind.html:
      case DocContentKind.directory:
      case DocContentKind.source:
        return SingleChildScrollView(
          padding: const EdgeInsets.all( 16 ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              content.text ?? "",
              key  : const Key( TestKeys.docViewerSource ),
              style: const TextStyle( fontFamily: "monospace", fontSize: 12, height: 1.4 ),
            ),
          ),
        );
    }
  }
}

/// Error state.
///
/// The server's message is shown verbatim — its refusals are written for a
/// human reader and distinguish "this file is credential material" from "this
/// file could not be read", which send you to different places.
class _ErrorView extends StatelessWidget {
  final Object        error;
  final VoidCallback  onRetry;

  const _ErrorView( { required this.error, required this.onRetry } );

  @override
  Widget build( BuildContext context ) {
    final theme   = Theme.of( context );
    final message = error is DocApiException
        ? ( error as DocApiException ).message
        : error.toString();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all( 24 ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon( Icons.error_outline, size: 48, color: theme.colorScheme.error ),
            const SizedBox( height: 16 ),
            SelectableText(
              message,
              key      : const Key( TestKeys.docViewerError ),
              textAlign: TextAlign.center,
              style    : theme.textTheme.bodyMedium,
            ),
            const SizedBox( height: 24 ),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon     : const Icon( Icons.refresh ),
              label    : const Text( "Try again" ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adapt the repository's `List<int>` to the `Uint8List` Image.memory wants.
/// Dio already hands back a Uint8List in practice, so the common path avoids a
/// copy.
Uint8List _asBytes( List<int>? bytes ) {
  if ( bytes == null ) return Uint8List( 0 );
  return bytes is Uint8List ? bytes : Uint8List.fromList( bytes );
}
