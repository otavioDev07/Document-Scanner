import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oss_document_scanner_flutter/core/files/document_repository.dart';
import 'package:oss_document_scanner_flutter/features/documents/application/document_library_controller.dart';
import 'package:oss_document_scanner_flutter/features/documents/presentation/document_library_page.dart';
import 'package:oss_document_scanner_flutter/features/settings/application/scanner_settings_controller.dart';

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
  });
}
