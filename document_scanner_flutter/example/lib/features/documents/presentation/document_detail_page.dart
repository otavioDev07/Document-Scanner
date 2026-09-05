import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/localization/legacy_localizations.dart';
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
        builder: (BuildContext context) =>
            AutomaticScannerPage(settings: settings),
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
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _RenameDocumentDialog(initialName: document.name),
    );
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

  Future<void> _deleteDocument(
    BuildContext context, {
    required bool permanently,
  }) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(
              permanently
                  ? 'Excluir permanentemente?'
                  : 'Mover para a lixeira?',
            ),
            content: Text(
              permanently
                  ? 'Todas as páginas e exportações associadas serão removidas do armazenamento local. Esta ação não pode ser desfeita.'
                  : 'O documento poderá ser restaurado pela lixeira.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.text('cancel', fallback: 'Cancelar')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  permanently
                      ? context.l10n.text('delete', fallback: 'Excluir')
                      : context.l10n.text('move_to_trash', fallback: 'Mover'),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      if (permanently) {
        await controller.deleteDocument(documentId);
      } else {
        await controller.moveToTrash(documentId);
      }
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _restoreDocument(BuildContext context) async {
    try {
      await controller.restoreFromTrash(documentId);
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _recognizePage(BuildContext context, ScannedPage page) async {
    try {
      final OcrResult result = await controller.recognizePage(
        documentId,
        page.id,
        languages: <String>[Localizations.localeOf(context).toLanguageTag()],
      );
      if (context.mounted) _showRecognizedText(context, result.text);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _recognizeDocument(BuildContext context) async {
    try {
      await controller.recognizeDocument(
        documentId,
        languages: <String>[Localizations.localeOf(context).toLanguageTag()],
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Texto reconhecido em todas as páginas.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _applyFilter(
    BuildContext context,
    ScannedPage page,
    String filter,
  ) async {
    try {
      await controller.applyFilter(documentId, page.id, filter);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _showRecognizedText(BuildContext context, String text) =>
      showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(context.l10n.text('ocr', fallback: 'Texto reconhecido')),
          content: SizedBox(
            width: double.maxFinite,
            child: text.trim().isEmpty
                ? Text(
                    context.l10n.text(
                      'no_text_found_in_page',
                      fallback: 'Nenhum texto foi encontrado nesta página.',
                    ),
                  )
                : SingleChildScrollView(child: SelectableText(text)),
          ),
          actions: <Widget>[
            if (text.trim().isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.copy),
                label: Text(
                  context.l10n.text('ocr_copy_text', fallback: 'Copiar'),
                ),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.text('close', fallback: 'Fechar')),
            ),
          ],
        ),
      );

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
            if (!document.isTrashed)
              IconButton(
                tooltip: document.favorite
                    ? 'Remover dos favoritos'
                    : 'Adicionar aos favoritos',
                onPressed: controller.busy
                    ? null
                    : () => controller.setFavorite(
                        documentId,
                        !document.favorite,
                      ),
                icon: Icon(document.favorite ? Icons.star : Icons.star_outline),
              ),
            IconButton(
              tooltip: context.l10n.text('rename', fallback: 'Renomear'),
              onPressed: controller.busy || document.isTrashed
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
                  case 'ocr':
                    _recognizeDocument(context);
                  case 'restore':
                    _restoreDocument(context);
                  case 'delete':
                    _deleteDocument(context, permanently: document.isTrashed);
                }
              },
              itemBuilder: (BuildContext context) => document.isTrashed
                  ? const <PopupMenuEntry<String>>[
                      PopupMenuItem(
                        value: 'restore',
                        child: Text('Restaurar documento'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Excluir permanentemente'),
                      ),
                    ]
                  : const <PopupMenuEntry<String>>[
                      PopupMenuItem(
                        value: 'ocr',
                        child: Text('Reconhecer texto de todas as páginas'),
                      ),
                      PopupMenuItem(
                        value: 'export',
                        child: Text('Exportar PDF'),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: Text('Compartilhar PDF'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Mover para a lixeira'),
                      ),
                    ],
            ),
          ],
        ),
        body: Stack(
          children: <Widget>[
            document.isTrashed
                ? ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: document.pages.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _buildPage(context, document, index),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: document.pages.length,
                    onReorderItem: (int oldIndex, int newIndex) =>
                        controller.reorder(documentId, oldIndex, newIndex),
                    itemBuilder: (BuildContext context, int index) =>
                        _buildPage(context, document, index),
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
        floatingActionButton: document.isTrashed
            ? null
            : FloatingActionButton.extended(
                onPressed: controller.busy ? null : () => _addPage(context),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Adicionar página'),
              ),
      );
    },
  );

  Widget _buildPage(BuildContext context, ScannedDocument document, int index) {
    final ScannedPage page = document.pages[index];
    return _PageTile(
      key: ValueKey<String>(page.id),
      index: index,
      controller: controller,
      document: document,
      page: page,
      readOnly: document.isTrashed,
      onRotate: () => controller.rotatePage(documentId, page.id),
      onFilter: (String filter) => _applyFilter(context, page, filter),
      onOcr: () => page.ocrText.isEmpty
          ? _recognizePage(context, page)
          : _showRecognizedText(context, page.ocrText),
      onDelete: () async {
        await controller.deletePage(documentId, page.id);
        if (context.mounted && controller.document(documentId) == null) {
          Navigator.pop(context);
        }
      },
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.index,
    required this.controller,
    required this.document,
    required this.page,
    required this.readOnly,
    required this.onRotate,
    required this.onFilter,
    required this.onOcr,
    required this.onDelete,
  });

  final int index;
  final DocumentLibraryController controller;
  final ScannedDocument document;
  final ScannedPage page;
  final bool readOnly;
  final VoidCallback onRotate;
  final ValueChanged<String> onFilter;
  final VoidCallback onOcr;
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
                child: InkWell(
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => _FullscreenPage(
                        file: snapshot.data!,
                        title:
                            '${context.l10n.text('page', fallback: 'Página')} ${index + 1}',
                        rotationQuarterTurns: page.rotationQuarterTurns,
                        imageVersion: page.filter,
                      ),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      RotatedBox(
                        quarterTurns: page.rotationQuarterTurns,
                        child: Image.file(
                          snapshot.data!,
                          key: ValueKey<String>('${page.id}:${page.filter}'),
                          fit: BoxFit.contain,
                        ),
                      ),
                      const Positioned(
                        top: 8,
                        right: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0x99000000),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(7),
                            child: Icon(
                              Icons.fullscreen,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        ListTile(
          leading: readOnly
              ? null
              : ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle),
                ),
          title: Text(
            '${context.l10n.text('page', fallback: 'Página')} ${index + 1}',
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${page.width} × ${page.height} px'),
              TextButton.icon(
                onPressed: onOcr,
                icon: Icon(
                  page.ocrText.isEmpty
                      ? Icons.document_scanner_outlined
                      : Icons.text_snippet_outlined,
                  size: 18,
                ),
                label: Text(
                  page.ocrText.isEmpty
                      ? context.l10n.text(
                          'ocr_document',
                          fallback: 'Reconhecer texto',
                        )
                      : 'Ver texto reconhecido',
                ),
              ),
            ],
          ),
          trailing: readOnly
              ? null
              : Row(
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
                            PopupMenuItem(
                              value: 'original',
                              child: Text('Original'),
                            ),
                            PopupMenuItem(
                              value: 'grayscale',
                              child: Text('Cinza'),
                            ),
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
                      tooltip: context.l10n.text(
                        'delete_page',
                        fallback: 'Excluir página',
                      ),
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

class _FullscreenPage extends StatelessWidget {
  const _FullscreenPage({
    required this.file,
    required this.title,
    required this.rotationQuarterTurns,
    required this.imageVersion,
  });

  final File file;
  final String title;
  final int rotationQuarterTurns;
  final String imageVersion;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          InteractiveViewer(
            minScale: 0.8,
            maxScale: 6,
            child: Center(
              child: RotatedBox(
                quarterTurns: rotationQuarterTurns,
                child: Image.file(
                  file,
                  key: ValueKey<String>('fullscreen:$imageVersion'),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: IconButton.filled(
              tooltip: 'Fechar tela cheia',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0x99000000),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          Positioned(
            top: 15,
            left: 64,
            right: 64,
            child: IgnorePointer(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 6)],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RenameDocumentDialog extends StatefulWidget {
  const _RenameDocumentDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDocumentDialog> createState() => _RenameDocumentDialogState();
}

class _RenameDocumentDialogState extends State<_RenameDocumentDialog> {
  late final TextEditingController _input = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _input.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.text('rename', fallback: 'Renomear documento')),
    content: TextField(
      controller: _input,
      autofocus: true,
      maxLength: 120,
      decoration: const InputDecoration(labelText: 'Nome'),
      onSubmitted: (_) => _submit(),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.text('cancel', fallback: 'Cancelar')),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(context.l10n.text('save', fallback: 'Salvar')),
      ),
    ],
  );
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Não foi possível concluir: $error')));
}
