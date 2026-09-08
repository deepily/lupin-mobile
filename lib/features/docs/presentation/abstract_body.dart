import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/testing/test_keys.dart';
import '../data/doc_link.dart';
import '../data/doc_repository.dart';
import 'doc_viewer_screen.dart';

/// Renders a notification's `abstract` inline in a card.
///
/// Replaces the plain `Text( abstractText )` the conversation screens used, so
/// the markdown the fleet already writes into abstracts — bold, bullets,
/// tables, inline code — actually formats, and the doc links inside it become
/// tappable.
///
/// Conditional by contract: a null or empty abstract renders NOTHING, exactly
/// as before. The card chrome (tinted rounded container) is drawn here only
/// when there is something to put in it.
class AbstractBody extends StatefulWidget {
  /// The abstract text. Null or empty renders nothing.
  final String? abstractText;

  /// Repository used to fetch a tapped document. Injected so widget tests can
  /// supply a fake without a live server.
  final DocRepository repository;

  /// Lines to show before collapsing behind a "Show more" toggle. Long
  /// abstracts — some are multi-row tables — would otherwise swamp the list.
  final int collapsedMaxLines;

  const AbstractBody( {
    super.key,
    required this.abstractText,
    required this.repository,
    this.collapsedMaxLines = 8,
  } );

  @override
  State<AbstractBody> createState() => _AbstractBodyState();
}

class _AbstractBodyState extends State<AbstractBody> {
  bool _expanded = false;

  /// True when the abstract is long enough to be worth collapsing. Measured in
  /// source lines rather than rendered height: it is cheap, stable across text
  /// scales, and does not need a layout pass to decide.
  bool get _isLong {
    final text = widget.abstractText;
    if ( text == null ) return false;
    return "\n".allMatches( text ).length + 1 > widget.collapsedMaxLines;
  }

  String get _visibleText {
    final text = widget.abstractText!;
    if ( _expanded || !_isLong ) return text;
    final lines = text.split( "\n" );
    return lines.take( widget.collapsedMaxLines ).join( "\n" );
  }

  Future<void> _onTapLink( String href ) async {
    final link = classifyDocHref( href );

    if ( link.isFetchable ) {
      await Navigator.of( context ).push( MaterialPageRoute(
        builder: ( _ ) => DocViewerScreen( link: link, repository: widget.repository ),
      ) );
      return;
    }

    if ( link.kind == DocLinkKind.external ) {
      await _confirmAndLaunch( link );
    }
    // `unknown` links are not offered as tap targets at all — nothing to do.
  }

  /// Leaving the app should be deliberate, so an external URL asks first.
  Future<void> _confirmAndLaunch( DocLink link ) async {
    final go = await showDialog<bool>(
      context: context,
      builder: ( ctx ) => AlertDialog(
        title  : const Text( "Open outside the app?" ),
        content: Text( link.rawHref ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of( ctx ).pop( false ),
            child    : const Text( "Cancel" ),
          ),
          FilledButton(
            onPressed: () => Navigator.of( ctx ).pop( true ),
            child    : const Text( "Open" ),
          ),
        ],
      ),
    );

    if ( go != true ) return;

    final uri = Uri.tryParse( link.rawHref );
    if ( uri == null ) return;
    await launchUrl( uri, mode: LaunchMode.externalApplication );
  }

  @override
  Widget build( BuildContext context ) {
    final text = widget.abstractText;

    // The conditional Rick specified: no abstract, no widget, no chrome.
    if ( text == null || text.isEmpty ) return const SizedBox.shrink();

    final theme    = Theme.of( context );
    final hasDoc   = hasFetchableDocLink( text );
    final baseSize = theme.textTheme.bodySmall;

    return Container(
      key    : const Key( TestKeys.abstractBody ),
      padding: const EdgeInsets.all( 8 ),
      decoration: BoxDecoration(
        color       : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular( 6 ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ( hasDoc )
            Padding(
              padding: const EdgeInsets.only( bottom: 4 ),
              child: Icon(
                Icons.description_outlined,
                key  : const Key( TestKeys.abstractDocBadge ),
                size : 16,
                color: theme.colorScheme.primary,
              ),
            ),
          MarkdownBody(
            data       : _visibleText,
            selectable : false,
            onTapLink  : ( text, href, title ) {
              if ( href != null ) _onTapLink( href );
            },
            styleSheet : MarkdownStyleSheet.fromTheme( theme ).copyWith(
              p          : baseSize,
              listBullet : baseSize,
              tableBody  : baseSize,
              a          : baseSize?.copyWith(
                color         : theme.colorScheme.primary,
                decoration    : TextDecoration.underline,
                decorationColor: theme.colorScheme.primary,
              ),
              blockSpacing: 6,
            ),
          ),
          if ( _isLong )
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key      : const Key( TestKeys.abstractExpandToggle ),
                onPressed: () => setState( () => _expanded = !_expanded ),
                style    : TextButton.styleFrom(
                  padding        : EdgeInsets.zero,
                  minimumSize    : const Size( 0, 28 ),
                  tapTargetSize  : MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text( _expanded ? "Show less" : "Show more" ),
              ),
            ),
        ],
      ),
    );
  }
}
