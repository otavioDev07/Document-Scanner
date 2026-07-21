import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oss_document_scanner_flutter/core/export/pdf_export_service.dart';
import 'package:oss_document_scanner_flutter/core/files/document_repository.dart';
import 'package:oss_document_scanner_flutter/features/documents/domain/scanned_document.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory sandbox;
  late Directory root;
  late File fixture;
  late DocumentRepository repository;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('oss_scanner_repository_');
    root = Directory(path.join(sandbox.path, 'library'));
    fixture = await File(
      'assets/test-document.png',
    ).copy(path.join(sandbox.path, 'fixture.png'));
    repository = DocumentRepository(
      rootDirectory: () async => root,
      nativeFilter: (String imagePath, String outputPath, String filter) async {
        final List<int> bytes = await File(imagePath).readAsBytes();
        await File(outputPath).writeAsBytes(<int>[...bytes, filter.length]);
        return CropResult(path: outputPath, width: 1200, height: 1600);
      },
    );
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  CropResult crop() =>
      CropResult(path: fixture.path, width: 1200, height: 1600);

  test('persists and reloads a multipage document', () async {
    ScannedDocument document = await repository.createFromCrop(
      crop(),
      name: 'Contrato',
    );
    final String firstPageId = document.pages.single.id;
    document = await repository.addPage(document, crop());
    final String secondPageId = document.pages.last.id;

    expect(document.pages, hasLength(2));
    expect(
      await (await repository.pageFile(
        document,
        document.pages.first,
      )).exists(),
      isTrue,
    );
    expect(
      await (await repository.pageFile(document, document.pages.last)).exists(),
      isTrue,
    );

    document = await repository.reorderPages(document, 0, 1);
    expect(document.pages.first.id, secondPageId);
    expect(document.pages.last.id, firstPageId);

    document = await repository.rotatePage(document, secondPageId);
    expect(document.pages.first.rotationQuarterTurns, 1);
    final List<int> originalBytes = await (await repository.pageFile(
      document,
      document.pages.first,
    )).readAsBytes();
    document = await repository.applyFilter(
      document,
      secondPageId,
      'grayscale',
    );
    expect(document.pages.first.filter, 'grayscale');
    expect(
      await (await repository.pageFile(
        document,
        document.pages.first,
      )).readAsBytes(),
      isNot(originalBytes),
    );
    document = await repository.applyFilter(document, secondPageId, 'original');
    expect(document.pages.first.filter, 'original');
    expect(
      await (await repository.pageFile(
        document,
        document.pages.first,
      )).readAsBytes(),
      originalBytes,
    );
    document = await repository.rename(document, 'Contrato assinado');

    final List<ScannedDocument> reloaded = await repository.loadDocuments();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.name, 'Contrato assinado');
    expect(reloaded.single.pages.first.id, secondPageId);
    expect(reloaded.single.pages.first.rotationQuarterTurns, 1);

    final File pdf = await PdfExportService(repository).export(reloaded.single);
    expect(await pdf.exists(), isTrue);
    expect(await pdf.length(), greaterThan(100));
    expect(
      await pdf.openRead(0, 4).fold<List<int>>(<int>[], (a, b) => a..addAll(b)),
      <int>[0x25, 0x50, 0x44, 0x46],
    );

    final ScannedDocument? onePage = await repository.deletePage(
      reloaded.single,
      secondPageId,
    );
    expect(onePage, isNotNull);
    expect(onePage!.pages, hasLength(1));
    expect(await repository.deletePage(onePage, firstPageId), isNull);
    expect(await repository.loadDocuments(), isEmpty);
    expect(await pdf.exists(), isFalse);
  });

  test('recovers metadata from the backup file', () async {
    final ScannedDocument document = await repository.createFromCrop(crop());
    final Directory documentDirectory = Directory(
      path.join(root.path, 'doc_${document.id}'),
    );
    final File metadata = File(
      path.join(documentDirectory.path, 'metadata.json'),
    );
    final File backup = File(
      path.join(documentDirectory.path, 'metadata.backup.json'),
    );
    await metadata.copy(backup.path);
    await metadata.delete();

    final List<ScannedDocument> recovered = await repository.loadDocuments();

    expect(recovered.single.id, document.id);
    expect(await metadata.exists(), isTrue);
    expect(await backup.exists(), isFalse);
  });

  test(
    'keeps corrupt document data on disk but excludes it from the library',
    () async {
      final Directory corrupt = Directory(path.join(root.path, 'doc_corrupt'));
      await corrupt.create(recursive: true);
      final File metadata = File(path.join(corrupt.path, 'metadata.json'));
      await metadata.writeAsString('{not-json');

      expect(await repository.loadDocuments(), isEmpty);
      expect(await metadata.exists(), isTrue);
    },
  );
}
