import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/material.dart';

import '../../settings/application/scanner_settings_controller.dart';
import '../../settings/presentation/settings_page.dart';
import '../application/document_library_controller.dart';
import '../domain/scanned_document.dart';
import 'document_detail_page.dart';
import 'scanner_page.dart';

class DocumentLibraryPage extends StatelessWidget {
  const DocumentLibraryPage({
    super.key,
    required this.controller,
    required this.settings,
  });

  final DocumentLibraryController controller;
  final ScannerSettingsController settings;

  Future<void> _scan(BuildContext context) async {
    final CropResult? crop = await Navigator.of(context).push<CropResult>(
      MaterialPageRoute<CropResult>(
        builder: (BuildContext context) => ScannerPage(settings: settings),
      ),
    );
    if (crop == null || !context.mounted) return;
    try {
      final ScannedDocument document = await controller.create(crop);
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => DocumentDetailPage(
            controller: controller,
            settings: settings,
            documentId: document.id,
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (BuildContext context, Widget? child) {
      final List<ScannedDocument> documents = controller.documents;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Meus documentos'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Configurações',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      SettingsPage(controller: settings),
                ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: <Widget>[
            if (documents.isEmpty)
              _EmptyLibrary(onScan: () => _scan(context))
            else
              RefreshIndicator(
                onRefresh: controller.load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: documents.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final ScannedDocument document = documents[index];
                    return _DocumentTile(
                      controller: controller,
                      document: document,
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) => DocumentDetailPage(
                            controller: controller,
                            settings: settings,
                            documentId: document.id,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (controller.busy)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(),
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: controller.busy ? null : () => _scan(context),
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Digitalizar'),
        ),
      );
    },
  );
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.controller,
    required this.document,
    required this.onTap,
  });

  final DocumentLibraryController controller;
  final ScannedDocument document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ScannedPage firstPage = document.pages.first;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              SizedBox.square(
                dimension: 76,
                child: FutureBuilder<File>(
                  future: controller.pageFile(document.id, firstPage.id),
                  builder:
                      (BuildContext context, AsyncSnapshot<File> snapshot) {
                        if (!snapshot.hasData) {
                          return const ColoredBox(
                            color: Colors.black12,
                            child: Icon(Icons.description_outlined),
                          );
                        }
                        return RotatedBox(
                          quarterTurns: firstPage.rotationQuarterTurns,
                          child: Image.file(snapshot.data!, fit: BoxFit.cover),
                        );
                      },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      document.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${document.pages.length} ${document.pages.length == 1 ? 'página' : 'páginas'}',
                    ),
                    Text(_shortDate(document.updatedAt)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.folder_copy_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            'Sua biblioteca está vazia',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Digitalize recibos, contratos e anotações. As páginas ficam armazenadas somente neste aparelho.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.document_scanner),
            label: const Text('Digitalizar primeiro documento'),
          ),
        ],
      ),
    ),
  );
}

String _shortDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} '
      '${two(value.hour)}:${two(value.minute)}';
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Não foi possível concluir: $error')));
}
