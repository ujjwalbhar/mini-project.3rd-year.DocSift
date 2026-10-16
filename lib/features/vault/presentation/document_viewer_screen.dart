import 'package:flutter/material.dart';

class DocumentViewerScreen extends StatelessWidget {
  const DocumentViewerScreen({super.key, required this.fileId});
  final String fileId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Viewing: $fileId')),
      body: const Center(child: Text('Viewer — Phase 2')),
    );
  }
}
