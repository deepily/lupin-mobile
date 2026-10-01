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
/// What it renders depends on the content type: markdown as markdown, source as
/// monospaced text, images as bytes, and directory listings as a browsable list.
/// HTML falls back to a readable source view, because showing the bytes beats an error.
class DocViewerScreen extends StatefulWidget {
  /// The document to fetch, null when [content] is already in hand.
  final DocLink?       link;

  /// Fetches documents and listings, required whenever [link] is used.
  final DocRepository? repository;

  /// Content the caller already has, such as an abstract.
  ///
  /// It is shown as-is and nothing is fetched.
  final DocContent? content;

  /// App-bar title, defaulting to the link's file name.
  final String? title;

  /// Closes the viewer when it shares the screen instead of owning a route.
  ///
  /// In the split there is nothing to pop, so the app bar needs its own close button.
  /// Null keeps the plain route behaviour.
  final VoidCallback? onClose;

  /// Opens the phone's file chooser for Upload.
  ///
  /// Null falls back to [platformDocFilePicker]; when both are null, Upload is not offered.
  final DocFilePicker? pickFile;

  /// Whether to offer Upload.
  ///
  /// It defaults to reading the admin role off the signed-in token. The server's own
  /// admin check is what actually decides.
  final bool Function()? canUpload;

  /// True to open with the Roots panel unfolded, for the global file-viewer button.
  ///
  /// It applies to the first place shown only.
  final bool rootsOpen;

  /// Creates a viewer for either [content] or a [link] plus a [repository].
  const DocViewerScreen( {
    super.key,
    this.link,
    this.repository,
    this.content,
    this.title,
    this.onClose,
    this.pickFile,
    this.canUpload,
    this.rootsOpen = false,
  } ) : assert( content != null || ( link != null && repository != null ),
                'give the viewer either content or a link and a repository to fetch it' );

  /// What the app bar shows, and the shared file's name.
  String get displayTitle => title ?? link?.displayName ?? "Document";

  @override
  State<DocViewerScreen> createState() => _DocViewerScreenState();
}

class _DocViewerScreenState extends State<DocViewerScreen> {
  // Explicit load state rather than a FutureBuilder. A FutureBuilder does not subscribe
  // to a future handed to it by setState until the next frame, so a fetch that rejects
  // at once would finish before anything listens and surface as an unhandled async
  // error. Awaiting here means the result is always observed.
  DocContent? _content;
  Object?     _error;
  bool        _loading = true;

  /// What is on screen now, starting at the widget's link.
  ///
  /// The Folder button, the Roots panel and a tap on a listing entry move it.
  /// Navigation is in place and not a pushed route.
  /// The viewer also lives in the split, where a pushed route would cover the conversation.
  /// Back walks [_history] first and leaves only when it is empty.
  DocLink?            _link;
  final List<DocLink> _history = [];

  @override
  void initState() {
    super.initState();
    _link = widget.link;
    _load();
  }

  /// Shows [next] in place, remembering where we were for Back.
  void _open( DocLink next ) {
    final current = _link;
    if ( current != null ) _history.add( current );
    _link = next;
    _load();
  }

  /// Steps back one place, returning false when there is nowhere to go back to.
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

  /// Downloads the original bytes, not the rendered view, which for markdown is the source.
  ///
  /// A phone has no downloads bar, so the file is written under its own name.
  /// It is then handed to the share sheet, where "Save to Files" or Drive is one tap.
  /// It reuses the bytes this fetch already holds, because a second request would cost
  /// data and could return a newer file than the one shown.
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

  /// Uploads into the folder on screen.
  ///
  /// It asks the server to refuse a taken name first. On the 409 the operator chooses
  /// Replace, Rename to the server's suggestion, or Cancel, as buttons in a sheet.
  /// A name is never overwritten silently.
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
      // The server's words: a read-only mount says it is not writable and an oversized
      // file names the cap.
      messenger.showSnackBar( SnackBar(
        key            : const Key( TestKeys.docUploadError ),
        content        : Text( e.message ),
        backgroundColor: Colors.red,
      ) );
    }
  }

  /// Shares the text of [content] as a file, since only text is shareable today.
  Future<void> _share( DocContent content ) async {
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
    // A file fetched from a link: never a listing, an error, or content handed in by the caller.
    final isFile  = link != null && content != null && !_loading &&
                    content.kind != DocContentKind.directory;
    final folder  = isFile ? folderLinkFor( link ) : null;
    // Upload is offered on a listing, for admins, when a picker exists.
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
          // The Folder button, beside Download, shows the listing of the file's folder.
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
          // On an open Fold the user chooses where the document sits: beside the
          // conversation, or below it so tables get the full width. The toggle appears
          // only inside a split, and only where the choice exists.
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
    return _ContentView(
      content    : _content!,
      repository : widget.repository,
      onOpen     : _open,
      rootsOpen  : widget.rootsOpen && _history.isEmpty && identical( _link, widget.link ),
    );
  }
}

/// Renders one fetched document according to its kind.
class _ContentView extends StatelessWidget {
  final DocContent     content;
  final DocRepository? repository;

  /// Shows another place in this viewer: a listing entry, a parent, or a root.
  final void Function( DocLink link ) onOpen;

  /// Unfolds the Roots panel on a listing.
  final bool rootsOpen;

  const _ContentView( { required this.content, required this.onOpen, this.repository, this.rootsOpen = false } );

  @override
  Widget build( BuildContext context ) {
    switch ( content.kind ) {
      case DocContentKind.markdown:
        return Markdown(
          key       : const Key( TestKeys.docViewerMarkdown ),
          data      : content.text ?? "",
          selectable: true,
          padding   : const EdgeInsets.all( 16 ),
          // Links are live here. An abstract's doc link lives only in the viewer, so a tap
          // opens the document in place of the abstract.
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
          rootsOpen  : rootsOpen,
        );

      // Say plainly that there is no preview, and point at the Download button.
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

      // HTML lands here until it has its own renderer, since source beats an error.
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
/// The server's message is shown verbatim.
/// Its refusals are written for a reader and tell a credential file from an unreadable one.
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

/// Adapts the repository's `List<int>` to the `Uint8List` that Image.memory wants.
///
/// Dio already returns a Uint8List in practice, so the common path avoids a copy.
Uint8List _asBytes( List<int>? bytes ) {
  if ( bytes == null ) return Uint8List( 0 );
  return bytes is Uint8List ? bytes : Uint8List.fromList( bytes );
}
