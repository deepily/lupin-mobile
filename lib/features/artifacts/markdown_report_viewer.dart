import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../services/artifacts/io_file_service.dart';

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
      final svc  = IoFileService();
      final file = await svc.downloadToCache( markdownText, '$jobId-report.md' );
      await svc.shareToExternalApp( file );
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
