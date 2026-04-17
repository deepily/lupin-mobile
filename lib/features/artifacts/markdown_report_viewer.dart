import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class MarkdownReportViewer extends StatelessWidget {
  final String jobId;
  final String markdownText;

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
