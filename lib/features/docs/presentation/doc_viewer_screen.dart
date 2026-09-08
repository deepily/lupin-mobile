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

/// Full-screen viewer for a document reached from a notification abstract.
///
/// Polymorphic by content type: markdown renders as markdown, source renders as
/// monospaced text, images render as bytes. HTML and directory listings arrive
/// in P4; until then they fall back to a readable source view rather than an
/// error, because showing the bytes is always better than showing nothing.
class DocViewerScreen extends StatefulWidget {
  final DocLink       link;
  final DocRepository repository;

  const DocViewerScreen( {
    super.key,
    required this.link,
    required this.repository,
  } );

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
    setState( () {
      _loading = true;
      _error   = null;
      _content = null;
    } );

    try {
      final content = await widget.repository.fetch( widget.link );
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
      final file = File( "${dir.path}/${widget.link.displayName}" );
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
        title: Text( widget.link.displayName, overflow: TextOverflow.ellipsis ),
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
    return _ContentView( content: _content! );
  }
}

/// Renders one fetched document according to its kind.
class _ContentView extends StatelessWidget {
  final DocContent content;

  const _ContentView( { required this.content } );

  @override
  Widget build( BuildContext context ) {
    switch ( content.kind ) {
      case DocContentKind.markdown:
        return Markdown(
          key       : const Key( TestKeys.docViewerMarkdown ),
          data      : content.text ?? "",
          selectable: true,
          padding   : const EdgeInsets.all( 16 ),
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
