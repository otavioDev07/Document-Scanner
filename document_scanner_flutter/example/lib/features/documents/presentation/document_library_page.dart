import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/legacy_localizations.dart';
import '../../settings/application/scanner_settings_controller.dart';
import '../../settings/presentation/settings_page.dart';
import '../application/document_library_controller.dart';
import '../domain/scanned_document.dart';
import 'document_detail_page.dart';
import 'scanner_page.dart';

enum _LibrarySection { documents, favorites, trash }

class DocumentLibraryPage extends StatefulWidget {
  const DocumentLibraryPage({
    super.key,
    required this.controller,
    required this.settings,
  });

  final DocumentLibraryController controller;
  final ScannerSettingsController settings;

  @override
  State<DocumentLibraryPage> createState() => _DocumentLibraryPageState();
}

class _DocumentLibraryPageState extends State<DocumentLibraryPage> {
  final TextEditingController _search = TextEditingController();
  _LibrarySection _section = _LibrarySection.documents;

  DocumentLibraryController get controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final CropResult? crop = await Navigator.of(context).push<CropResult>(
      MaterialPageRoute<CropResult>(
        builder: (BuildContext context) =>
            ScannerPage(settings: widget.settings),
      ),
    );
    if (crop == null || !mounted) return;
    try {
      final ScannedDocument document = await controller.create(crop);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => DocumentDetailPage(
            controller: controller,
            settings: widget.settings,
            documentId: document.id,
          ),
        ),
      );
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  void _select(_LibrarySection section) {
    Navigator.pop(context);
    setState(() {
      _section = section;
      _search.clear();
    });
  }

  String _title(BuildContext context) {
    final LegacyLocalizations l10n = context.l10n;
    switch (_section) {
      case _LibrarySection.documents:
        return l10n.text('documents', fallback: 'Meus documentos');
      case _LibrarySection.favorites:
        return l10n.text('favorite', fallback: 'Favoritos');
      case _LibrarySection.trash:
        return l10n.text('trash', fallback: 'Lixeira');
    }
  }

  List<ScannedDocument> _visibleDocuments() => controller.search(
    _search.text,
    favoritesOnly: _section == _LibrarySection.favorites,
    trashOnly: _section == _LibrarySection.trash,
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (BuildContext context, Widget? child) {
      final List<ScannedDocument> documents = _visibleDocuments();
      return Scaffold(
        drawer: NavigationDrawer(
          selectedIndex: switch (_section) {
            _LibrarySection.documents => 0,
            _LibrarySection.favorites => 1,
            _LibrarySection.trash => 2,
          },
          onDestinationSelected: (int index) => _select(switch (index) {
            0 => _LibrarySection.documents,
            1 => _LibrarySection.favorites,
            _ => _LibrarySection.trash,
          }),
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 24, 16, 12),
              child: Text('OSS Document Scanner'),
            ),
            NavigationDrawerDestination(
              icon: const Icon(Icons.description_outlined),
              selectedIcon: const Icon(Icons.description),
              label: Text(
                context.l10n.text('documents', fallback: 'Documentos'),
              ),
            ),
            NavigationDrawerDestination(
              icon: const Icon(Icons.star_outline),
              selectedIcon: const Icon(Icons.star),
              label: Text(context.l10n.text('favorite', fallback: 'Favoritos')),
            ),
            NavigationDrawerDestination(
              icon: const Icon(Icons.delete_outline),
              selectedIcon: const Icon(Icons.delete),
              label: Text(context.l10n.text('trash', fallback: 'Lixeira')),
            ),
          ],
        ),
        appBar: AppBar(
          title: Text(_title(context)),
          actions: <Widget>[
            if (_section == _LibrarySection.trash && documents.isNotEmpty)
              IconButton(
                tooltip: 'Esvaziar lixeira',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: controller.busy ? null : controller.emptyTrash,
              ),
            IconButton(
              tooltip: context.l10n.text(
                'settings.title',
                fallback: 'Configurações',
              ),
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      SettingsPage(controller: widget.settings),
                ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SearchBar(
                    controller: _search,
                    hintText: context.l10n.text(
                      'search',
                      fallback: 'Pesquisar nome ou texto reconhecido',
                    ),
                    leading: const Icon(Icons.search),
                    trailing: <Widget>[
                      if (_search.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Limpar',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Expanded(
                  child: documents.isEmpty
                      ? _EmptyLibrary(
                          section: _section,
                          hasQuery: _search.text.isNotEmpty,
                          onScan: _scan,
                        )
                      : RefreshIndicator(
                          onRefresh: controller.load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                            itemCount: documents.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (BuildContext context, int index) {
                              final ScannedDocument document = documents[index];
                              return _DocumentTile(
                                controller: controller,
                                document: document,
                                onFavorite: document.isTrashed
                                    ? null
                                    : () => controller.setFavorite(
                                        document.id,
                                        !document.favorite,
                                      ),
                                onTap: () => Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (BuildContext context) =>
                                        DocumentDetailPage(
                                          controller: controller,
                                          settings: widget.settings,
                                          documentId: document.id,
                                        ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
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
        floatingActionButton: _section == _LibrarySection.trash
            ? null
            : FloatingActionButton.extended(
                onPressed: controller.busy ? null : _scan,
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(context.l10n.text('scan', fallback: 'Digitalizar')),
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
    required this.onFavorite,
  });

  final DocumentLibraryController controller;
  final ScannedDocument document;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;

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
                    Text(context.l10n.pages(document.pages.length)),
                    Text(_shortDate(document.updatedAt)),
                    if (document.isTrashed)
                      const Text(
                        'Na lixeira',
                        style: TextStyle(color: Colors.red),
                      ),
                  ],
                ),
              ),
              if (onFavorite != null)
                IconButton(
                  tooltip: document.favorite
                      ? 'Remover dos favoritos'
                      : 'Adicionar aos favoritos',
                  onPressed: onFavorite,
                  icon: Icon(
                    document.favorite ? Icons.star : Icons.star_outline,
                  ),
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.section,
    required this.hasQuery,
    required this.onScan,
  });

  final _LibrarySection section;
  final bool hasQuery;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    if (hasQuery) {
      return Center(
        child: Text(
          context.l10n.text(
            'no_document_found',
            fallback: 'Nenhum documento encontrado.',
          ),
        ),
      );
    }
    final (IconData icon, String title, String description) = switch (section) {
      _LibrarySection.favorites => (
        Icons.star_outline,
        context.l10n.text('favorite', fallback: 'Nenhum favorito'),
        'Toque na estrela de um documento para encontrá-lo aqui.',
      ),
      _LibrarySection.trash => (
        Icons.delete_outline,
        context.l10n.text(
          'no_trashed_document',
          fallback: 'A lixeira está vazia',
        ),
        'Documentos excluídos podem ser restaurados antes da remoção definitiva.',
      ),
      _LibrarySection.documents => (
        Icons.folder_copy_outlined,
        context.l10n.text('documents', fallback: 'Sua biblioteca está vazia'),
        context.l10n.text(
          'no_document_yet',
          fallback:
              'Digitalize recibos, contratos e anotações. Os arquivos ficam neste aparelho.',
        ),
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
            if (section == _LibrarySection.documents) ...<Widget>[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.document_scanner),
                label: Text(
                  context.l10n.text(
                    'scan',
                    fallback: 'Digitalizar primeiro documento',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
