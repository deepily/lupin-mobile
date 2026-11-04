import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/doc_upload.dart';

/// The phone's file chooser for Upload: Android's own document browser, via `file_picker`.
///
/// Setting this to null hides Upload everywhere, which is the one-line retreat if the
/// plugin has to be removed.
DocFilePicker? platformDocFilePicker = pickDocFileWithPlugin;

/// Picks one file of any type and reads it into memory.
///
/// Ensures:
///   - null when the user backs out, or the platform returned no bytes
///   - the file's own name, so the server can check its extension
Future<PickedDocFile?> pickDocFileWithPlugin() async {
  final result = await FilePicker.pickFiles( withData: true );
  final file   = result?.files.firstOrNull;
  final bytes  = file?.bytes;
  if ( file == null || bytes == null ) return null;
  return PickedDocFile( name: file.name, bytes: bytes );
}

/// Asks what to do about a taken name, after the server's 409.
///
/// Ensures:
///   - Replace → [DocUploadConflictMode.replace]
///   - "Rename to <suggested>" → [DocUploadConflictMode.rename]; offered only
///     when the server suggested a name, and the server re-picks one anyway
///   - Cancel or dismissal → null
Future<DocUploadConflictMode?> showDocUploadConflictSheet(
  BuildContext context,
  DocUploadConflict clash,
  String requestedName,
) {
  return showModalBottomSheet<DocUploadConflictMode>(
    context: context,
    builder: ( sheetContext ) => SafeArea(
      child: Column(
        key         : const Key( TestKeys.docUploadConflictSheet ),
        mainAxisSize: MainAxisSize.min,
        children    : [
          ListTile( title: Text( clash.message ) ),
          ListTile(
            key     : const Key( TestKeys.docUploadReplace ),
            leading : const Icon( Icons.swap_horiz ),
            title   : Text( "Replace $requestedName" ),
            onTap   : () => Navigator.of( sheetContext ).pop( DocUploadConflictMode.replace ),
          ),
          if ( clash.suggestedName != null )
            ListTile(
              key     : const Key( TestKeys.docUploadRename ),
              leading : const Icon( Icons.drive_file_rename_outline ),
              title   : Text( "Rename to ${clash.suggestedName}" ),
              onTap   : () => Navigator.of( sheetContext ).pop( DocUploadConflictMode.rename ),
            ),
          ListTile(
            key     : const Key( TestKeys.docUploadCancel ),
            leading : const Icon( Icons.close ),
            title   : const Text( "Cancel" ),
            onTap   : () => Navigator.of( sheetContext ).pop(),
          ),
        ],
      ),
    ),
  );
}
