import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/doc_link.dart';
import '../data/doc_models.dart';
import '../data/doc_repository.dart';
import 'doc_split_host.dart';
import 'doc_viewer_screen.dart';

/// A notification's `abstract`, disclosed on request.
///
/// Rick 2026-09-18: "the whole idea behind using abstracts as a notion is
/// progressive disclosure." The bubble no longer renders the abstract inline.
/// It shows one compact row — an icon and a label — and a tap opens the WHOLE
/// abstract in the document viewer: in the 50/50 split beside the
/// conversation where the surface has one (focus mode), else as a page. The
/// viewer renders it as a full markdown document, and its links (doc links
/// included) are live there.
///
/// Conditional by contract: a null or empty abstract renders NOTHING.
class AbstractBody extends StatelessWidget {
  /// The abstract text. Null or empty renders nothing.
  final String? abstractText;

  /// Repository the viewer uses when a doc link inside the abstract is tapped.
  /// Injected so widget tests can supply a fake without a live server.
  final DocRepository repository;

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

    // The conditional Rick specified: no abstract, no widget, no chrome.
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
