import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../core/testing/test_keys.dart';
import '../data/transcript_models.dart';

/// One block, rendered according to its `kind`.
///
/// Prose and tool content do not share a renderer, because of mangling and not injection.
/// `kind: text` renders as markdown; tool calls, tool results and thinking render as plain
/// text. A markdown renderer turns a raw file dump into markup, so a diff or a config file
/// renders wrong. Plain text cannot mangle and cannot execute.
/// The `switch` has a default arm that renders, not one that drops. A kind the client does
/// not recognise renders as plain text, never dropped and never thrown on. A three-literal
/// switch with no fallback would silently render nothing.
/// Use `flutter_markdown_plus`, never `flutter_markdown`, which is discontinued. The `_plus`
/// package is the maintained continuation, pinned in `pubspec.yaml` and used in
/// `doc_viewer_screen.dart`.
class TranscriptBlockView extends StatefulWidget {
  /// The block to render.
  final TranscriptBlock block;

  /// Fetches this block's full text over REST.
  ///
  /// It is called at most once, on the first expand of a server-truncated block.
  final Future<void> Function()? onFetchFull;

  /// Creates the view.
  const TranscriptBlockView( {
    super.key,
    required this.block,
    this.onFetchFull,
  } );

  @override
  State<TranscriptBlockView> createState() => _TranscriptBlockViewState();
}

class _TranscriptBlockViewState extends State<TranscriptBlockView> {
  bool _expanded = false;
  bool _fetched  = false;

  @override
  void initState() {
    super.initState();
    // Prose renders open; tool calls, tool results and thinking arrive collapsed. A build
    // that rendered every block expanded would fail a test on this line.
    // Design: src/docs/decisions/README.md (R-TR-tool-collapsed)
    _expanded = !widget.block.kind.startsCollapsed;
  }

  @override
  Widget build( BuildContext context ) {
    final block = widget.block;

    // The only kind that reaches `Markdown`. Everything else, including a kind invented
    // after this file was written, goes to `SelectableText`.
    if ( block.kind == TranscriptBlockKind.text ) {
      return Padding(
        padding : const EdgeInsets.symmetric( horizontal: 12, vertical: 4 ),
        child   : MarkdownBody(
          key        : const Key( TestKeys.transcriptProse ),
          data       : block.text,
          selectable : true,
        ),
      );
    }

    // Claude Code records most thinking with EMPTY text. There is nothing to fold, so this
    // is a plain dim label with no chip, no chevron and no tap target, as the web client
    // does ("thinking (not recorded)").
    if ( block.isUnrecordedThinking ) return _unrecordedThinking( context );

    return _collapsible( context, block );
  }

  Widget _unrecordedThinking( BuildContext context ) {
    final theme = Theme.of( context );
    return Padding(
      padding : const EdgeInsets.symmetric( horizontal: 12, vertical: 2 ),
      child   : Padding(
        padding : const EdgeInsets.only( left: 22, top: 6, bottom: 6 ),
        child   : Text(
          "Thinking (not recorded)",
          key   : const Key( TestKeys.transcriptUnrecordedThinking ),
          style : theme.textTheme.labelMedium?.copyWith(
            fontFamily : "monospace",
            color      : theme.hintColor,
          ),
        ),
      ),
    );
  }

  // A one-line header that toggles, over a monospace body. The header is the whole hit
  // target and carries its own `Semantics`, because the visible text is a bare label such as
  // "Thinking..." and a screen reader would otherwise announce an unnamed control.
  Widget _collapsible( BuildContext context, TranscriptBlock block ) {
    final theme = Theme.of( context );

    return Padding(
      padding : const EdgeInsets.symmetric( horizontal: 12, vertical: 2 ),
      child   : Column(
        crossAxisAlignment : CrossAxisAlignment.stretch,
        children : [
          Semantics(
            button   : true,
            label    : "${ _headerLabel( block ) }, ${ _expanded ? "expanded" : "collapsed" }",
            child    : InkWell(
              key   : Key( "${ TestKeys.transcriptChipPrefix }${ _kindSlug( block ) }" ),
              onTap : () => _toggle( block ),
              child : ConstrainedBox(
                constraints : const BoxConstraints( minHeight: kMinInteractiveDimension ),
                child       : Row(
                  children : [
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size  : 18,
                      color : theme.hintColor,
                    ),
                    const SizedBox( width: 4 ),
                    Expanded(
                      child: Text(
                        _headerLabel( block ),
                        style    : theme.textTheme.labelMedium?.copyWith(
                          fontFamily : "monospace",
                          color      : theme.colorScheme.primary,
                        ),
                        overflow : TextOverflow.ellipsis,
                      ),
                    ),
                    if ( block.truncated )
                      // The marker is drawn whether or not the block is expanded: it is a fact
                      // about the content, and it is visible before the expand that fetches
                      // the rest.
                      Padding(
                        padding : const EdgeInsets.only( left: 6 ),
                        child   : Text(
                          "truncated",
                          key   : const Key( TestKeys.transcriptTruncatedMarker ),
                          style : theme.textTheme.labelSmall?.copyWith(
                            color : theme.colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if ( _expanded )
            // Monospace `SelectableText` with no `Markdown` ancestor, for tool output and for
            // `thinking`, which is model scratch text and must not be re-flowed as prose. It
            // is selectable and copyable, with no input.
            Padding(
              padding : const EdgeInsets.only( left: 22, top: 2, bottom: 6 ),
              child   : SelectableText(
                block.text,
                key   : Key( "${ TestKeys.transcriptPlainPrefix }${ _kindSlug( block ) }" ),
                style : const TextStyle(
                  fontFamily : "monospace",
                  fontSize   : 12,
                  height     : 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggle( TranscriptBlock block ) async {
    final opening = !_expanded;
    setState( () => _expanded = opening );

    // Exactly one fetch, and only on the way open. `_fetched` makes it once: a second expand
    // of the same block must not re-ask, and collapsing must not ask at all.
    if ( opening && block.truncated && !_fetched && widget.onFetchFull != null ) {
      _fetched = true;
      await widget.onFetchFull!();
    }
  }

  String _headerLabel( TranscriptBlock block ) => switch ( block.kind ) {
        TranscriptBlockKind.toolCall   => block.name ?? "Tool call",
        TranscriptBlockKind.toolResult => block.name == null
            ? "Tool result"
            : "Result — ${ block.name }",
        TranscriptBlockKind.thinking   => "Thinking…",
        // A kind this build has never heard of. It is named, so the operator can see what the
        // server called it and whoever adds the fifth kind can see it already arriving.
        _ => block.rawKind == null ? "Block" : "Block — ${ block.rawKind }",
      };

  String _kindSlug( TranscriptBlock block ) => switch ( block.kind ) {
        TranscriptBlockKind.toolCall   => "tool_call",
        TranscriptBlockKind.toolResult => "tool_result",
        TranscriptBlockKind.thinking   => "thinking",
        TranscriptBlockKind.text       => "text",
        TranscriptBlockKind.unknown    => "unknown",
      };
}
