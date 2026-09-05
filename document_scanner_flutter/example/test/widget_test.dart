import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oss_document_scanner_flutter/core/files/document_repository.dart';
import 'package:oss_document_scanner_flutter/features/documents/application/document_library_controller.dart';
import 'package:oss_document_scanner_flutter/features/documents/domain/scanned_document.dart';
import 'package:oss_document_scanner_flutter/features/documents/presentation/document_detail_page.dart';
import 'package:oss_document_scanner_flutter/features/documents/presentation/document_library_page.dart';
import 'package:oss_document_scanner_flutter/features/settings/application/scanner_settings_controller.dart';
import 'package:oss_document_scanner_flutter/features/settings/presentation/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders an empty document library', (WidgetTester tester) async {
    final DocumentLibraryController documents = DocumentLibraryController(
      repository: DocumentRepository(
        rootDirectory: () async => Directory('/tmp/unused_scanner_library'),
      ),
    );
    final ScannerSettingsController settings = ScannerSettingsController(
      store: MemoryScannerSettingsStore(),
    );
    addTearDown(documents.dispose);
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DocumentLibraryPage(controller: documents, settings: settings),
      ),
    );
    await tester.pump();

    expect(find.text('Meus documentos'), findsOneWidget);
    expect(find.text('Sua biblioteca está vazia'), findsOneWidget);
    expect(find.text('Digitalizar'), findsOneWidget);

    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('Pastas'), findsNothing);
    expect(find.byTooltip('Nova pasta'), findsNothing);
    await tester.tapAt(const Offset(790, 300));
    await tester.pumpAndSettle();
  });

  testWidgets('settings updates keep the inherited widget tree consistent', (
    WidgetTester tester,
  ) async {
    final ScannerSettingsController settings = ScannerSettingsController(
      store: MemoryScannerSettingsStore(),
    );
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(controller: settings)),
    );
    await tester.pump();
    expect(find.text('Criar e compartilhar backup'), findsNothing);
    expect(find.text('Restaurar ou mesclar backup'), findsNothing);
    expect(find.textContaining('WebDAV'), findsNothing);
    expect(find.text('Sincronização'), findsNothing);
    expect(find.text('Segurança'), findsNothing);
    expect(find.text('Ativar bloqueio'), findsNothing);
    expect(find.textContaining('biométric'), findsNothing);

    await tester.tap(find.text('Captura automática'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('العربية').last);
    await tester.pump(const Duration(seconds: 1));

    expect(settings.localeId, 'ar');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('cloud image destination reveals and persists its endpoint', (
    WidgetTester tester,
  ) async {
    final MemoryScannerSettingsStore store = MemoryScannerSettingsStore();
    final ScannerSettingsController settings = ScannerSettingsController(
      store: store,
    );
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(controller: settings)),
    );
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(RadioListTile<ImageDestination>, 'NUVEM'),
    );
    await tester.pumpAndSettle();

    expect(settings.imageDestination, ImageDestination.cloud);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      ' https://example.test/upload ',
    );
    await tester.pump();
    expect(settings.cloudDestination, 'https://example.test/upload');

    final ScannerSettingsController restored = ScannerSettingsController(
      store: store,
    );
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.imageDestination, ImageDestination.cloud);
    expect(restored.cloudDestination, 'https://example.test/upload');
  });

  testWidgets('page preview opens full screen and refreshes after filtering', (
    WidgetTester tester,
  ) async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'oss_scanner_detail_',
    );
    final DocumentRepository repository = DocumentRepository(
      rootDirectory: () async => Directory('${sandbox.path}/library'),
      nativeFilter: (String imagePath, String outputPath, String filter) async {
        await File(imagePath).copy(outputPath);
        return CropResult(path: outputPath, width: 1200, height: 1600);
      },
    );
    final DocumentLibraryController documents = DocumentLibraryController(
      repository: repository,
    );
    final ScannerSettingsController settings = ScannerSettingsController(
      store: MemoryScannerSettingsStore(),
    );
    final ScannedDocument document = (await tester.runAsync(
      () => documents.create(
        CropResult(
          path: File('assets/test-document.png').absolute.path,
          width: 1200,
          height: 1600,
        ),
      ),
    ))!;
    addTearDown(documents.dispose);
    addTearDown(settings.dispose);
    addTearDown(() async => sandbox.delete(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        home: DocumentDetailPage(
          controller: documents,
          settings: settings,
          documentId: document.id,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mover para pastas'), findsNothing);
    await tester.tapAt(const Offset(8, 500));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    await tester.tap(find.byIcon(Icons.fullscreen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byTooltip('Fechar tela cheia'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => documents.applyFilter(
        document.id,
        document.pages.single.id,
        'grayscale',
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(documents.document(document.id)!.pages.single.filter, 'grayscale');
    expect(
      find.byKey(ValueKey<String>('${document.pages.single.id}:grayscale')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rename save closes the dialog without tree errors', (
    WidgetTester tester,
  ) async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'oss_scanner_rename_',
    );
    final DocumentRepository repository = DocumentRepository(
      rootDirectory: () async => Directory('${sandbox.path}/library'),
    );
    final DocumentLibraryController documents = DocumentLibraryController(
      repository: repository,
    );
    final ScannerSettingsController settings = ScannerSettingsController(
      store: MemoryScannerSettingsStore(),
    );
    final ScannedDocument document = (await tester.runAsync(
      () => documents.create(
        CropResult(
          path: File('assets/test-document.png').absolute.path,
          width: 1200,
          height: 1600,
        ),
      ),
    ))!;
    addTearDown(documents.dispose);
    addTearDown(settings.dispose);
    addTearDown(() async => sandbox.delete(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        home: DocumentDetailPage(
          controller: documents,
          settings: settings,
          documentId: document.id,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Renomear'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsNothing);

    expect(documents.busy, isFalse);
    expect(documents.document(document.id)!.name, document.name);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores a trashed document without reorder assertions', (
    WidgetTester tester,
  ) async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'oss_scanner_restore_',
    );
    final DocumentRepository repository = DocumentRepository(
      rootDirectory: () async => Directory('${sandbox.path}/library'),
    );
    final DocumentLibraryController documents = DocumentLibraryController(
      repository: repository,
    );
    final ScannerSettingsController settings = ScannerSettingsController(
      store: MemoryScannerSettingsStore(),
    );
    final ScannedDocument document = (await tester.runAsync(
      () => documents.create(
        CropResult(
          path: File('assets/test-document.png').absolute.path,
          width: 1200,
          height: 1600,
        ),
      ),
    ))!;
    await tester.runAsync(() => documents.moveToTrash(document.id));
    addTearDown(documents.dispose);
    addTearDown(settings.dispose);
    addTearDown(() async => sandbox.delete(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        home: DocumentDetailPage(
          controller: documents,
          settings: settings,
          documentId: document.id,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => documents.restoreFromTrash(document.id));
    await tester.pump();

    expect(documents.document(document.id)!.isTrashed, isFalse);
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
