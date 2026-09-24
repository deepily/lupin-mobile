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
import '../../../services/auth/auth_token_provider.dart';
import '../data/doc_upload.dart';
import 'doc_directory_view.dart';
import 'doc_upload_sheet.dart';
import 'doc_link_tap.dart';
import 'doc_panel.dart';
import 'doc_split_host.dart';

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

  /// Opens the phone's file chooser for ⬆ Upload. Null falls back to
  /// [platformDocFilePicker]; when both are null, Upload is not offered.
  final DocFilePicker? pickFile;

  /// Whether to OFFER Upload. Defaults to reading the admin role off the
  /// signed-in token; the server's own admin check is what actually decides.
  final bool Function()? canUpload;

  const DocViewerScreen( {
    super.key,
    this.link,
    this.repository,
    this.content,
    this.title,
    this.onClose,
    this.pickFile,
    this.canUpload,
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

  /// What is on screen now. Starts at the widget's link; the Folder button,
  /// the Roots panel and a tap on a listing entry move it (row 61ecfb22).
  ///
  /// ⚠️ NAVIGATION IS IN PLACE, NOT A PUSHED ROUTE. The viewer also lives inside
  /// the 50/50 split, where a pushed route would cover the conversation it was
  /// opened beside. Back walks [_history] first and leaves only when it is empty.
  DocLink?            _link;
  final List<DocLink> _history = [];

  @override
  void initState() {
    super.initState();
    _link = widget.link;
    _load();
  }

  /// Show [next] in place, remembering where we were for Back.
  void _open( DocLink next ) {
    final current = _link;
    if ( current != null ) _history.add( current );
    _link = next;
    _load();
  }

  /// Step back one place. Returns false when there is nowhere to go back to.
  bool _back() {
    if ( _history.isEmpty ) return false;
    _link = _history.removeLast();
    _load();
    return true;
  }

  /// The app-bar title for what is on screen.
  String get _title {
    final link = _link;
    if ( link == null || ( _history.isEmpty && identical( link, widget.link ) ) ) {
      return widget.displayTitle;
    }
    final listing = _content?.listing;
    if ( listing != null ) {
      return listing.path.isEmpty ? listing.scope : "${listing.scope}/${listing.path}";
    }
    return link.displayName;
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
      final requested = _link!;
      final content   = await widget.repository!.fetch( requested );
      // A slow fetch must not paint over a newer one the user has moved to.
      if ( !mounted || !identical( requested, _link ) ) return;
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

  /// ⬇ Download: the ORIGINAL bytes, not the rendered view (row 61ecfb22,
  /// parity with the web's ticket 668aa0a3). For markdown that is the source.
  ///
  /// A phone has no downloads bar, so the file is written under its own name
  /// and handed to the share sheet, where "Save to Files" or Drive is one tap.
  /// The bytes are the ones this fetch already holds — a second request would
  /// cost data and could answer with a newer file than the one on screen.
  Future<void> _download( DocLink link, DocContent content ) async {
    final bytes = content.bytes;
    if ( bytes == null ) return;
    try {
      final dir  = await getTemporaryDirectory();
      final name = link.displayName.replaceAll( RegExp( r'[^A-Za-z0-9._-]+' ), '-' );
      final file = File( "${dir.path}/${name.isEmpty ? 'download' : name}" );
      await file.writeAsBytes( bytes );
      await Share.shareXFiles( [ XFile( file.path ) ] );
    } catch ( e ) {
      if ( mounted ) {
        ScaffoldMessenger.of( context ).showSnackBar(
          SnackBar( content: Text( "Download failed: $e" ), backgroundColor: Colors.red ),
        );
      }
    }
  }

  /// ⬆ Upload into the folder on screen (row 61ecfb22, lupin 416d4b00).
  ///
  /// Asks the server to REFUSE a taken name first. On the 409 the operator
  /// chooses Replace, Rename to the server's suggestion, or Cancel — as buttons
  /// in a sheet, as on the web, never a silent overwrite.
  Future<void> _upload( DocDirectoryListing listing, DocFilePicker pick ) async {
    final messenger = ScaffoldMessenger.of( context );
    final picked    = await pick();
    if ( picked == null || !mounted ) return;

    final dir  = uploadDirFor( listing.scope, listing.path );
    var   mode = DocUploadConflictMode.refuse;
    try {
      while ( true ) {
        try {
          final stored = await widget.repository!.upload( dir: dir, file: picked, onConflict: mode );
          if ( !mounted ) return;
          messenger.showSnackBar( SnackBar(
            key    : const Key( TestKeys.docUploadDone ),
            content: Text( stored.replaced ? "Replaced ${stored.name}" : "Uploaded ${stored.name}" ),
          ) );
          _load();   // the listing now holds the new file
          return;
        } on DocUploadConflict catch ( clash ) {
          if ( !mounted || mode != DocUploadConflictMode.refuse ) rethrow;
          final choice = await showDocUploadConflictSheet( context, clash, picked.name );
          if ( choice == null ) return;   // Cancel
          mode = choice;
        }
      }
    } on DocUploadConflict catch ( clash ) {
      messenger.showSnackBar( SnackBar( content: Text( clash.message ), backgroundColor: Colors.red ) );
    } on DocApiException catch ( e ) {
      // The server's words: a read-only mount says it is not writable, a
      // credential says it was refused, an oversized file names the cap.
      messenger.showSnackBar( SnackBar(
        key            : const Key( TestKeys.docUploadError ),
        content        : Text( e.message ),
        backgroundColor: Colors.red,
      ) );
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
    final host    = DocSplitHost.maybeOf( context );
    final link    = _link;
    final content = _content;
    // A FILE on screen, fetched from a link: never a listing, never an error,
    // never content handed in by the caller — the web's own rule for the bar.
    final isFile  = link != null && content != null && !_loading &&
                    content.kind != DocContentKind.directory;
    final folder  = isFile ? folderLinkFor( link ) : null;
    // ⬆ Upload: on a listing, for admins, when a picker exists.
    final listing = !_loading ? content?.listing : null;
    final picker  = widget.pickFile ?? platformDocFilePicker;
    final offerUp = listing != null && picker != null && widget.repository != null &&
                    ( widget.canUpload ?? () => tokenHasAdminRole( readAccessToken() ) )();

    return PopScope(
      canPop                : _history.isEmpty,
      onPopInvokedWithResult: ( didPop, _ ) {
        if ( !didPop ) _back();
      },
      child: Scaffold(
      key: const Key( TestKeys.docViewerScreen ),
      appBar: AppBar(
        leading: _history.isNotEmpty
            ? IconButton(
                key      : const Key( TestKeys.docViewerBackButton ),
                icon     : const Icon( Icons.arrow_back ),
                tooltip  : "Back",
                onPressed: _back,
              )
            : widget.onClose == null ? null : IconButton(
                key      : const Key( TestKeys.docViewerCloseButton ),
                icon     : const Icon( Icons.close ),
                tooltip  : "Close document",
                onPressed: widget.onClose,
              ),
        title: Text( _title, overflow: TextOverflow.ellipsis ),
        actions: [
          if ( isFile && content.bytes != null )
            IconButton(
              key      : const Key( TestKeys.docViewerDownloadButton ),
              icon     : const Icon( Icons.download_outlined ),
              tooltip  : "Download the original file",
              onPressed: () => _download( link, content ),
            ),
          // 📁 Folder, beside Download (Rick, 2026-09-24): the listing of the
          // folder this file lives in.
          if ( folder != null )
            IconButton(
              key      : const Key( TestKeys.docViewerFolderButton ),
              icon     : const Icon( Icons.folder_open_outlined ),
              tooltip  : "Show this file's folder",
              onPressed: () => _open( folder ),
            ),
          if ( offerUp )
            IconButton(
              key      : const Key( TestKeys.docViewerUploadButton ),
              icon     : const Icon( Icons.upload_outlined ),
              tooltip  : "Upload a file into this folder",
              onPressed: () => _upload( listing, picker ),
            ),
          // Rick 2026-09-18: on an open Fold, choose where the document sits —
          // beside the conversation, or below it so tables get the full width.
          // Only inside a split, and only where the choice exists.
          if ( host != null && docPlacementIsChoosable( MediaQuery.sizeOf( context ) ) )
            IconButton(
              key      : const Key( TestKeys.docViewerPlacementToggle ),
              icon     : Icon( host.belowWhenWide ? Icons.vertical_split_outlined : Icons.horizontal_split_outlined ),
              tooltip  : host.belowWhenWide ? "Show beside the conversation" : "Show below the conversation",
              onPressed: host.togglePlacement,
            ),
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
    ),
    );
  }

  Widget _buildBody() {
    if ( _loading )        return const Center( child: CircularProgressIndicator() );
    if ( _error != null )  return _ErrorView( error: _error!, onRetry: _load );
    return _ContentView( content: _content!, repository: widget.repository, onOpen: _open );
  }
}

/// Renders one fetched document according to its kind.
class _ContentView extends StatelessWidget {
  final DocContent     content;
  final DocRepository? repository;

  /// Show another place in this viewer — a listing entry, a parent, a root.
  final void Function( DocLink link ) onOpen;

  const _ContentView( { required this.content, required this.onOpen, this.repository } );

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

      case DocContentKind.directory:
        return DocDirectoryView(
          listing    : content.listing!,
          repository : repository,
          onOpen     : onOpen,
        );

      // The web's words: say so plainly and point at the button.
      case DocContentKind.binary:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all( 24 ),
            child: Text(
              "No preview for this file type — use Download above.",
              key      : Key( TestKeys.docViewerNoPreview ),
              textAlign: TextAlign.center,
            ),
          ),
        );

      // HTML lands here until it earns its own renderer. Showing the source
      // beats showing an error.
      case DocContentKind.html:
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
