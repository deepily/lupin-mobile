import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../core/testing/test_keys.dart';
import '../data/transcript_models.dart';

/// One block, rendered according to its `kind`.
///
/// 🔴 PROSE AND TOOL CONTENT DO NOT SHARE A RENDERER, AND THE REASON IS MANGLING RATHER THAN
/// INJECTION. §3 states the rule once for both clients: `kind: text` renders as **markdown**;
/// `tool_call` and `tool_result` render as **plain text**. A markdown renderer turns a raw
/// file dump into markup — `#` becomes a heading, `*` a list, indentation a code block — so
/// a diff or a config file renders WRONG. Plain text is the safe arm because it cannot
/// mangle and cannot execute. (C4 on the phone, B6 on the web: one finding, one rule.)
///
/// 🔴 AND THE `switch` HAS A DEFAULT ARM THAT RENDERS, NOT ONE THAT DROPS. §3: "a kind the
/// client does not recognise renders as plain text, never dropped and never thrown on." The
/// server's mapper is open-ended by design (§2 item 1(a)) and OSQ-7 already added a fourth
/// kind after the first three were written — so a three-literal switch with no fallback
/// would render nothing in the one surface whose whole job is to show everything, and
/// silently. C5.15 is the row that fails if the default arm goes away.
///
/// ⚠️ `flutter_markdown_plus`, NEVER `flutter_markdown` (C10). Google marked the latter
/// DISCONTINUED on 2025-05-30; the `_plus` package is the maintained continuation and is
/// already pinned in `pubspec.yaml` and in use in `doc_viewer_screen.dart`.
class TranscriptBlockView extends StatefulWidget {
  final TranscriptBlock block;

  /// Fetch this block's full text over REST. Called at most once, on the first expand of a
  /// server-truncated block.
  final Future<void> Function()? onFetchFull;

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
    // Ruling Q2's content model: prose renders OPEN; tool calls, tool results and thinking
    // arrive COLLAPSED. C5.18's negative control is a build that renders every block
    // expanded, and this line is what makes that build fail.
    _expanded = !widget.block.kind.startsCollapsed;
  }

  @override
  Widget build( BuildContext context ) {
    final block = widget.block;

    // 🔴 THE ONLY KIND THAT REACHES `Markdown`. Everything else — including a kind invented
    // after this file was written — goes to `SelectableText`.
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

    return _collapsible( context, block );
  }

  /// A one-line header that toggles, over a monospace body.
  ///
  /// The header is the whole hit target and carries its own `Semantics`, because the visible
  /// text is a bare label like "Thinking…" and a screen reader would otherwise announce an
  /// unnamed control.
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
                      // The marker is drawn whether or not the block is expanded: it is a
                      // fact about the CONTENT, and C5.19 asserts it is visible before the
                      // expand that goes and fetches the rest.
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
            // 🔴 MONOSPACE `SelectableText`, WITH NO `Markdown` ANCESTOR. C5.14 asserts
            // exactly that for tool output and C5.22 for `thinking` — "model scratch text",
            // which must not be re-flowed as prose. Selectable and copyable, no input
            // (ruling Q8).
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

    // 🔴 EXACTLY ONE FETCH, AND ONLY ON THE WAY OPEN (C5.19). `_fetched` is what makes it
    // once: a second expand of the same block must not re-ask, and collapsing must not ask
    // at all.
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
        // A kind this build has never heard of. NAMED, so the operator can see what the
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
