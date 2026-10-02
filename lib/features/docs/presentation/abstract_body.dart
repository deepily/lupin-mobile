import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/doc_link.dart';
import '../data/doc_models.dart';
import '../data/doc_repository.dart';
import 'doc_split_host.dart';
import 'doc_viewer_screen.dart';

/// A notification's abstract, disclosed on request.
///
/// The bubble shows one compact row, an icon and a label, and a tap opens the whole
/// abstract in the document viewer. Where the surface has a split (focus mode) it opens
/// beside the conversation, otherwise as a page.
/// The viewer renders it as a full markdown document with live links.
/// A null or empty abstract renders nothing.
/// Design: src/docs/decisions/README.md (R-DOC-abstract-disclosure)
class AbstractBody extends StatelessWidget {
  /// The abstract text. Null or empty renders nothing.
  final String? abstractText;

  /// Repository the viewer uses when a doc link inside the abstract is tapped.
  ///
  /// It is injected so widget tests can supply a fake without a live server.
  final DocRepository repository;

  /// Creates an abstract row.
  const AbstractBody( {
    super.key,
    required this.abstractText,
    required this.repository,
  } );

  void _open( BuildContext context, String text ) {
    final host = DocSplitHost.maybeOf( context );
    if ( host != null ) {
      host.openText( title: "Abstract", markdown: text );
      return;
    }
    Navigator.of( context ).push( MaterialPageRoute<void>(
      builder: ( _ ) => DocViewerScreen(
        content    : DocContent( kind: DocContentKind.markdown, mediaType: "text/markdown", text: text ),
        title      : "Abstract",
        repository : repository,
      ),
    ) );
  }

  @override
  Widget build( BuildContext context ) {
    final text = abstractText;

    // No abstract means no widget and no chrome.
    if ( text == null || text.isEmpty ) return const SizedBox.shrink();

    final theme  = Theme.of( context );
    final hasDoc = hasFetchableDocLink( text );
    final color  = theme.colorScheme.primary;

    return Material(
      key          : const Key( TestKeys.abstractBody ),
      color        : theme.colorScheme.surfaceContainerHighest,
      borderRadius : BorderRadius.circular( 6 ),
      child: InkWell(
        key          : const Key( TestKeys.abstractOpenButton ),
        onTap        : () => _open( context, text ),
        borderRadius : BorderRadius.circular( 6 ),
        child: Padding(
          padding: const EdgeInsets.symmetric( horizontal: 8, vertical: 6 ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon( hasDoc ? Icons.description_outlined : Icons.article_outlined, size: 20, color: color ),
              const SizedBox( width: 6 ),
              Flexible(
                child: Text(
                  hasDoc ? "Abstract · has a document" : "Abstract",
                  style    : theme.textTheme.labelMedium?.copyWith( color: color ),
                  overflow : TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
