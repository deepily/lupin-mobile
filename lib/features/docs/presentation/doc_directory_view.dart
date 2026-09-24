import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/doc_link.dart';
import '../data/doc_models.dart';
import '../data/doc_repository.dart';

/// A folder listing in the doc viewer (row 61ecfb22, parity with the web's
/// ticket 416d4b00).
///
/// Until 2026-09-24 the phone printed a listing's JSON as source text, so the
/// 📁 Folder button and the Roots panel had nothing to land on. Folders first,
/// then files, as the server sorts them; a tap opens the entry in place.
class DocDirectoryView extends StatelessWidget {
  final DocDirectoryListing listing;

  /// Fetches the roots for the Roots panel. Null hides the panel.
  final DocRepository? repository;

  /// Show another place in the same viewer.
  final void Function( DocLink link ) onOpen;

  const DocDirectoryView( {
    super.key,
    required this.listing,
    required this.onOpen,
    this.repository,
  } );

  @override
  Widget build( BuildContext context ) {
    final parent = listing.parent;
    final repo   = repository;

    return ListView(
      key      : const Key( TestKeys.docListing ),
      children : [
        if ( repo != null ) DocRootsPanel( repository: repo, onOpen: onOpen ),
        // ⚠️ THE SERVER DECIDES WHETHER "UP" EXISTS: `parent` is null at a
        // scope's top and wherever the parent falls outside the whitelist. The
        // Roots panel above is the way out from there.
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
            // 🔴 BUILT FROM `rel_path`, NEVER FROM `view_url` — see [docLinkFor].
            onTap    : () => onOpen( docLinkFor( listing.scope, entry.path, label: entry.name ) ),
          ),
      ],
    );
  }
}

/// Every browsable root: each registered repo's allowed folders, plus io
/// (Rick, 2026-09-24, item 2b).
///
/// Folded by default and fetched on first unfold — the listing is what the
/// reader came for, and the roots cost a request they may never want.
class DocRootsPanel extends StatefulWidget {
  final DocRepository repository;
  final void Function( DocLink link ) onOpen;

  const DocRootsPanel( { super.key, required this.repository, required this.onOpen } );

  @override
  State<DocRootsPanel> createState() => _DocRootsPanelState();
}

class _DocRootsPanelState extends State<DocRootsPanel> {
  Future<List<DocScope>>? _scopes;

  @override
  Widget build( BuildContext context ) {
    return ExpansionTile(
      key               : const Key( TestKeys.docRootsPanel ),
      leading           : const Icon( Icons.account_tree_outlined ),
      title             : const Text( "Roots" ),
      onExpansionChanged: ( open ) {
        if ( open && _scopes == null ) {
          // A block body, not an arrow: an arrow would RETURN the Future from
          // the setState callback, which Flutter rejects.
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
  final String  label;
  final DocLink link;

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
