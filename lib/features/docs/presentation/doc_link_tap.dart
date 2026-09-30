import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/doc_link.dart';
import '../data/doc_repository.dart';
import 'doc_panel.dart';
import 'doc_split_host.dart';

/// What a tap on a link inside rendered markdown does — one rule for every
/// place that renders markdown (the document viewer, and before 2026-09-18
/// the inline abstract card).
///
/// Requires:
///   - [context] is mounted
///
/// Ensures:
///   - a fetchable doc link opens in the surrounding [DocSplitHost] when there
///     is one (the conversation re-lays out into its half), else in the
///     half-screen panel (which needs a [repository]; without one the tap
///     does nothing)
///   - an external URL asks before leaving the app
///   - an unknown link does nothing
Future<void> openMarkdownHref( {
  required BuildContext  context,
  required String        href,
  required DocRepository? repository,
} ) async {
  final link = classifyDocHref( href );

  if ( link.isFetchable ) {
    final host = DocSplitHost.maybeOf( context );
    if ( host != null ) {
      host.open( link );
      return;
    }
    // No split to open into and nothing to fetch with: a viewer showing
    // in-hand text with no repository has nowhere to send the link.
    if ( repository == null ) return;
    await showDocPanel( context: context, link: link, repository: repository );
    return;
  }

  if ( link.kind == DocLinkKind.external ) await _confirmAndLaunch( context, link );
}

/// Leaving the app should be deliberate, so an external URL asks first.
Future<void> _confirmAndLaunch( BuildContext context, DocLink link ) async {
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
