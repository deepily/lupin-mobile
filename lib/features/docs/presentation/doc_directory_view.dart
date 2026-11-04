import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/doc_link.dart';
import '../data/doc_models.dart';
import '../data/doc_repository.dart';

/// A folder listing in the doc viewer.
///
/// Folders come first, then files, in the server's order, and a tap opens the entry in place.
class DocDirectoryView extends StatelessWidget {
  /// The listing to show.
  final DocDirectoryListing listing;

  /// Fetches the roots for the Roots panel. Null hides the panel.
  final DocRepository? repository;

  /// Shows another place in the same viewer.
  final void Function( DocLink link ) onOpen;

  /// True to unfold the Roots panel on arrival.
  final bool rootsOpen;

  /// Creates a listing view.
  const DocDirectoryView( {
    super.key,
    required this.listing,
    required this.onOpen,
    this.repository,
    this.rootsOpen = false,
  } );

  @override
  Widget build( BuildContext context ) {
    final parent = listing.parent;
    final repo   = repository;

    return ListView(
      key      : const Key( TestKeys.docListing ),
      children : [
        if ( repo != null ) DocRootsPanel( repository: repo, onOpen: onOpen, initiallyOpen: rootsOpen ),
        // The server decides whether "up" exists. `parent` is null at a scope's top and
        // where the parent falls outside the whitelist, so the Roots panel is the way out.
        if ( parent != null )
          ListTile(
            key     : const Key( TestKeys.docListingUp ),
            leading : const Icon( Icons.arrow_upward ),
            title   : const Text( "Up one folder" ),
            onTap   : () => onOpen( docLinkFor( listing.scope, parent ) ),
          ),
        if ( listing.entries.isEmpty )
          const Padding(
            padding : EdgeInsets.all( 24 ),
            child   : Text( "This folder is empty.", key: Key( TestKeys.docListingEmpty ) ),
          ),
        for ( final entry in listing.entries )
          ListTile(
            key      : Key( "${TestKeys.docListingEntryPrefix}${entry.name}" ),
            leading  : Icon( entry.isDirectory ? Icons.folder_outlined : Icons.description_outlined ),
            title    : Text( entry.name ),
            subtitle : entry.isDirectory || entry.sizeBytes == null
                ? null
                : Text( formatByteSize( entry.sizeBytes! ) ),
            // Built from `rel_path` and never from `view_url`; see [docLinkFor].
            onTap    : () => onOpen( docLinkFor( listing.scope, entry.path, label: entry.name ) ),
          ),
      ],
    );
  }
}

/// Every browsable root: each registered repo's allowed folders, plus io.
///
/// It is folded by default and fetched on first unfold.
/// The listing is what the reader came for, and the roots cost a request they may not want.
class DocRootsPanel extends StatefulWidget {
  /// Fetches the scopes the panel lists.
  final DocRepository repository;

  /// Shows the tapped root in the viewer.
  final void Function( DocLink link ) onOpen;

  /// True to start unfolded and fetching from the first frame.
  ///
  /// The global file-viewer button lands this way, where the roots are what the reader
  /// came for.
  final bool initiallyOpen;

  /// Creates a roots panel.
  const DocRootsPanel( { super.key, required this.repository, required this.onOpen, this.initiallyOpen = false } );

  @override
  State<DocRootsPanel> createState() => _DocRootsPanelState();
}

class _DocRootsPanelState extends State<DocRootsPanel> {
  Future<List<DocScope>>? _scopes;

  @override
  void initState() {
    super.initState();
    if ( widget.initiallyOpen ) _scopes = widget.repository.fetchScopes();
  }

  @override
  Widget build( BuildContext context ) {
    return ExpansionTile(
      key               : const Key( TestKeys.docRootsPanel ),
      initiallyExpanded : widget.initiallyOpen,
      leading           : const Icon( Icons.account_tree_outlined ),
      title             : const Text( "Roots" ),
      onExpansionChanged: ( open ) {
        if ( open && _scopes == null ) {
          // A block body, because an arrow would return the Future from the setState
          // callback, which Flutter rejects.
          final scopes = widget.repository.fetchScopes();
          setState( () { _scopes = scopes; } );
        }
      },
      children          : [
        FutureBuilder<List<DocScope>>(
          future : _scopes,
          builder: ( context, snap ) {
            if ( snap.hasError ) {
              final e = snap.error;
              return ListTile(
                title: Text( e is DocApiException ? e.message : "Could not load the roots." ),
              );
            }
            if ( !snap.hasData ) {
              return const Padding(
                padding: EdgeInsets.all( 12 ),
                child  : Center( child: CircularProgressIndicator() ),
              );
            }
            return Column(
              children: [
                for ( final root in rootsFor( snap.data! ) )
                  ListTile(
                    key     : Key( "${TestKeys.docRootPrefix}${root.label}" ),
                    dense   : true,
                    leading : const Icon( Icons.folder_special_outlined ),
                    title   : Text( root.label ),
                    onTap   : () => widget.onOpen( root.link ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One entry in the Roots panel.
class DocRoot {
  /// The text shown for the root.
  final String  label;

  /// The link that opens the root.
  final DocLink link;

  /// Creates a root entry.
  const DocRoot( this.label, this.link );
}

/// The Roots panel's entries: io first, then each scope's allowed folders.
///
/// Ensures:
///   - io is always present, at its root
///   - a scope with no prefixes, or a wildcard one, is offered at its root
///   - otherwise one entry per allowed prefix, trailing slash dropped
List<DocRoot> rootsFor( List<DocScope> scopes ) {
  final out = <DocRoot>[ DocRoot( ioScope, docLinkFor( ioScope, "" ) ) ];
  for ( final scope in scopes ) {
    final prefixes = scope.allowedPrefixes
        .map( ( p ) => p.replaceAll( RegExp( r'^\./|/+$' ), '' ) )
        .toList();
    final wildcard = prefixes.isEmpty || prefixes.any( ( p ) => p.isEmpty || p == "*" );
    if ( wildcard ) {
      out.add( DocRoot( scope.name, docLinkFor( scope.name, "" ) ) );
      continue;
    }
    for ( final prefix in prefixes ) {
      out.add( DocRoot( "${scope.name}/$prefix", docLinkFor( scope.name, prefix ) ) );
    }
  }
  return out;
}

/// A byte count a reader can take in at a glance.
String formatByteSize( int bytes ) {
  if ( bytes < 1024 ) return "$bytes B";
  if ( bytes < 1024 * 1024 ) return "${( bytes / 1024 ).toStringAsFixed( 1 )} KB";
  return "${( bytes / ( 1024 * 1024 ) ).toStringAsFixed( 1 )} MB";
}
