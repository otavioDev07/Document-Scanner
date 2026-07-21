import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/material.dart';

import '../../../core/share/document_share_service.dart';
import '../../settings/application/scanner_settings_controller.dart';
import '../application/document_library_controller.dart';
import '../domain/scanned_document.dart';
import 'scanner_page.dart';

class DocumentDetailPage extends StatelessWidget {
  const DocumentDetailPage({
    super.key,
    required this.controller,
    required this.settings,
    required this.documentId,
  });

  final DocumentLibraryController controller;
  final ScannerSettingsController settings;
  final String documentId;

  Future<void> _addPage(BuildContext context) async {
    final CropResult? crop = await Navigator.of(context).push<CropResult>(
      MaterialPageRoute<CropResult>(
        builder: (BuildContext context) => ScannerPage(settings: settings),
      ),
    );
    if (crop == null) return;
    try {
      await controller.addPage(documentId, crop);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _rename(BuildContext context, ScannedDocument document) async {
    final TextEditingController input = TextEditingController(
      text: document.name,
    );
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Renomear documento'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Nome'),
          onSubmitted: (String value) => Navigator.pop(context, value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      await controller.rename(documentId, name);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _export(BuildContext context, bool share) async {
    try {
      final ScannedDocument? document = controller.document(documentId);
      if (document == null) return;
      final RenderBox? box = share
          ? context.findRenderObject() as RenderBox?
          : null;
      final Rect? origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      final File pdf = await controller.exportPdf(documentId);
      if (share) {
        await const DocumentShareService().sharePdf(
          pdf,
          document.name,
          sharePositionOrigin: origin,
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF salvo em ${pdf.path}')));
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _deleteDocument(BuildContext context) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Excluir documento?'),
            content: const Text(
              'Todas as páginas e exportações associadas serão removidas do armazenamento local.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await controller.deleteDocument(documentId);
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (BuildContext context, Widget? child) {
      final ScannedDocument? document = controller.document(documentId);
      if (document == null) {
        return const Scaffold(
          body: Center(child: Text('Este documento não existe mais.')),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(document.name),
          actions: <Widget>[
            IconButton(
              tooltip: 'Renomear',
              onPressed: controller.busy
                  ? null
                  : () => _rename(context, document),
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              enabled: !controller.busy,
              onSelected: (String value) {
                switch (value) {
                  case 'export':
                    _export(context, false);
                  case 'share':
                    _export(context, true);
                  case 'delete':
                    _deleteDocument(context);
                }
              },
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<String>>[
                    PopupMenuItem(value: 'export', child: Text('Exportar PDF')),
                    PopupMenuItem(
                      value: 'share',
                      child: Text('Compartilhar PDF'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Excluir documento'),
                    ),
                  ],
            ),
          ],
        ),
        body: Stack(
          children: <Widget>[
            ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: document.pages.length,
              onReorderItem: (int oldIndex, int newIndex) =>
                  controller.reorder(documentId, oldIndex, newIndex),
              itemBuilder: (BuildContext context, int index) {
                final ScannedPage page = document.pages[index];
                return _PageTile(
                  key: ValueKey<String>(page.id),
                  index: index,
                  controller: controller,
                  document: document,
                  page: page,
                  onRotate: () => controller.rotatePage(documentId, page.id),
                  onFilter: (String filter) =>
                      controller.applyFilter(documentId, page.id, filter),
                  onDelete: () async {
                    await controller.deletePage(documentId, page.id);
                    if (context.mounted &&
                        controller.document(documentId) == null) {
                      Navigator.pop(context);
                    }
                  },
                );
              },
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
          onPressed: controller.busy ? null : () => _addPage(context),
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Adicionar página'),
        ),
      );
    },
  );
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.index,
    required this.controller,
    required this.document,
    required this.page,
    required this.onRotate,
    required this.onFilter,
    required this.onDelete,
  });

  final int index;
  final DocumentLibraryController controller;
  final ScannedDocument document;
  final ScannedPage page;
  final VoidCallback onRotate;
  final ValueChanged<String> onFilter;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Column(
      children: <Widget>[
        AspectRatio(
          aspectRatio: 4 / 3,
          child: FutureBuilder<File>(
            future: controller.pageFile(document.id, page.id),
            builder: (BuildContext context, AsyncSnapshot<File> snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ColoredBox(
                color: Colors.black,
                child: RotatedBox(
                  quarterTurns: page.rotationQuarterTurns,
                  child: Image.file(snapshot.data!, fit: BoxFit.contain),
                ),
              );
            },
          ),
        ),
        ListTile(
          leading: ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_handle),
          ),
          title: Text('Página ${index + 1}'),
          subtitle: Text('${page.width} × ${page.height} px'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Girar 90°',
                onPressed: onRotate,
                icon: const Icon(Icons.rotate_right),
              ),
              PopupMenuButton<String>(
                tooltip: 'Filtro',
                initialValue: page.filter,
                onSelected: onFilter,
                icon: const Icon(Icons.auto_fix_high_outlined),
                itemBuilder: (BuildContext context) =>
                    const <PopupMenuEntry<String>>[
                      PopupMenuItem(value: 'original', child: Text('Original')),
                      PopupMenuItem(value: 'grayscale', child: Text('Cinza')),
                      PopupMenuItem(
                        value: 'highContrast',
                        child: Text('Documento'),
                      ),
                      PopupMenuItem(
                        value: 'colorBoost',
                        child: Text('Cor realçada'),
                      ),
                    ],
              ),
              IconButton(
                tooltip: 'Excluir página',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Não foi possível concluir: $error')));
}
