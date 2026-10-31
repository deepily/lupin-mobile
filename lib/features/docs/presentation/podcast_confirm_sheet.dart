import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';

/// Asks "Podcast <name>?" in a bottom sheet inside the app, never a system dialog.
///
/// The Yes tap is the operator's go-ahead for the podcast, so nothing is sent before it.
///
/// Requires:
///   - [context] is mounted
///
/// Ensures:
///   - true only when the operator taps Yes
///   - false for No and for a dismissed sheet
Future<bool> showPodcastConfirmSheet( BuildContext context, String name ) async {
  final yes = await showModalBottomSheet<bool>(
    context: context,
    builder: ( sheetContext ) => SafeArea(
      child: Column(
        key         : const Key( TestKeys.podcastConfirmSheet ),
        mainAxisSize: MainAxisSize.min,
        children    : [
          ListTile(
            leading: const Icon( Icons.podcasts ),
            title  : Text( "Podcast $name?" ),
            subtitle: const Text( "The whole file is read out to a voice model." ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB( 16, 0, 16, 12 ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key      : const Key( TestKeys.podcastConfirmNo ),
                  onPressed: () => Navigator.of( sheetContext ).pop( false ),
                  child    : const Text( "No" ),
                ),
                const SizedBox( width: 8 ),
                FilledButton(
                  key      : const Key( TestKeys.podcastConfirmYes ),
                  onPressed: () => Navigator.of( sheetContext ).pop( true ),
                  child    : const Text( "Yes" ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return yes == true;
}
