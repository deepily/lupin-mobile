import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Shows a markdown report with a share action.
class MarkdownReportViewer extends StatelessWidget {
  /// The id of the job that produced the report.
  final String jobId;
  /// The markdown source to render.
  final String markdownText;

  /// Creates the viewer; the job id and markdown text are required.
  const MarkdownReportViewer( {
    super.key,
    required this.jobId,
    required this.markdownText,
  } );

  Future<void> _share( BuildContext context ) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final file     = File( '${cacheDir.path}/$jobId-report.md' );
      await file.writeAsString( markdownText );
      await Share.shareXFiles( [ XFile( file.path ) ] );
    } catch ( e ) {
      if ( context.mounted ) {
        ScaffoldMessenger.of( context ).showSnackBar(
          SnackBar( content: Text( 'Share failed: $e' ), backgroundColor: Colors.red ),
        );
      }
    }
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar(
        title  : Text( 'Report — $jobId' ),
        actions: [
          IconButton(
            icon     : const Icon( Icons.share_outlined ),
            tooltip  : 'Share',
            onPressed: () => _share( context ),
          ),
        ],
      ),
      body: Markdown(
        data      : markdownText,
        selectable: true,
        padding   : const EdgeInsets.all( 16 ),
      ),
    );
  }
}
