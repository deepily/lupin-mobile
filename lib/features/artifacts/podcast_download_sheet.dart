import 'package:flutter/material.dart';

import '../../core/testing/test_keys.dart';

/// Asks "Download over mobile data?" in a bottom sheet inside the app, never a system dialog.
///
/// Requires:
///   - [context] is mounted
///
/// Ensures:
///   - true only when the listener taps Download
///   - false for Cancel and for a dismissed sheet
Future<bool> showPodcastDataSheet( BuildContext context, String title ) async {
  final yes = await showModalBottomSheet<bool>(
    context: context,
    builder: ( sheetContext ) => SafeArea(
      child: Column(
        key         : const Key( TestKeys.podcastDataSheet ),
        mainAxisSize: MainAxisSize.min,
        children    : [
          ListTile(
            leading : const Icon( Icons.signal_cellular_alt ),
            title   : const Text( "Download over mobile data?" ),
            subtitle: Text( "$title is not on this phone yet. Wi-Fi would download it for free." ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB( 16, 0, 16, 12 ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key      : const Key( TestKeys.podcastDataNo ),
                  onPressed: () => Navigator.of( sheetContext ).pop( false ),
                  child    : const Text( "Cancel" ),
                ),
                const SizedBox( width: 8 ),
                FilledButton(
                  key      : const Key( TestKeys.podcastDataYes ),
                  onPressed: () => Navigator.of( sheetContext ).pop( true ),
                  child    : const Text( "Download" ),
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
