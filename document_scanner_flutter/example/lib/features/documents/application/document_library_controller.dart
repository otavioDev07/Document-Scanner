import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../core/export/pdf_export_service.dart';
import '../../../core/files/document_repository.dart';
import '../domain/scanned_document.dart';

final class DocumentLibraryController extends ChangeNotifier {
  DocumentLibraryController({
    required DocumentRepository repository,
    PdfExportService? pdfExportService,
  }) : _repository = repository,
       _pdfExportService = pdfExportService ?? PdfExportService(repository);

  final DocumentRepository _repository;
  final PdfExportService _pdfExportService;

  List<ScannedDocument> _documents = const <ScannedDocument>[];
  bool _busy = false;
  Object? _lastError;

  List<ScannedDocument> get documents => _documents;
  bool get busy => _busy;
  Object? get lastError => _lastError;

  ScannedDocument? document(String id) {
    for (final ScannedDocument document in _documents) {
      if (document.id == id) return document;
    }
    return null;
  }

  Future<void> load() => _run<void>(() async {
    _documents = await _repository.loadDocuments();
  });

  Future<ScannedDocument> create(CropResult crop) =>
      _run<ScannedDocument>(() async {
        final ScannedDocument value = await _repository.createFromCrop(crop);
        _replace(value);
        return value;
      });

  Future<ScannedDocument> addPage(String documentId, CropResult crop) =>
      _run<ScannedDocument>(() async {
        final ScannedDocument current = _require(documentId);
        final ScannedDocument value = await _repository.addPage(current, crop);
        _replace(value);
        return value;
      });

  Future<void> rename(String documentId, String name) => _run<void>(() async {
    _replace(await _repository.rename(_require(documentId), name));
  });

  Future<void> reorder(String documentId, int oldIndex, int newIndex) =>
      _run<void>(() async {
        _replace(
          await _repository.reorderPages(
            _require(documentId),
            oldIndex,
            newIndex,
          ),
        );
      });

  Future<void> rotatePage(String documentId, String pageId) =>
      _run<void>(() async {
        _replace(await _repository.rotatePage(_require(documentId), pageId));
      });

  Future<void> applyFilter(String documentId, String pageId, String filter) =>
      _run<void>(() async {
        final ScannedDocument value = await _repository.applyFilter(
          _require(documentId),
          pageId,
          filter,
        );
        final ScannedPage page = value.pages.firstWhere(
          (ScannedPage item) => item.id == pageId,
        );
        await FileImage(await _repository.pageFile(value, page)).evict();
        _replace(value);
      });

  Future<void> deletePage(String documentId, String pageId) =>
      _run<void>(() async {
        final ScannedDocument current = _require(documentId);
        final ScannedDocument? value = await _repository.deletePage(
          current,
          pageId,
        );
        if (value == null) {
          _documents = _documents
              .where((ScannedDocument item) => item.id != documentId)
              .toList(growable: false);
        } else {
          _replace(value);
        }
      });

  Future<void> deleteDocument(String documentId) => _run<void>(() async {
    await _repository.deleteDocument(_require(documentId));
    _documents = _documents
        .where((ScannedDocument item) => item.id != documentId)
        .toList(growable: false);
  });

  Future<File> pageFile(String documentId, String pageId) async {
    final ScannedDocument current = _require(documentId);
    final ScannedPage page = current.pages.firstWhere(
      (ScannedPage item) => item.id == pageId,
    );
    return _repository.pageFile(current, page);
  }

  Future<File> exportPdf(String documentId) =>
      _run<File>(() => _pdfExportService.export(_require(documentId)));

  Future<T> _run<T>(Future<T> Function() operation) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      return await operation();
    } catch (error) {
      _lastError = error;
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  ScannedDocument _require(String id) {
    final ScannedDocument? value = document(id);
    if (value == null) throw StateError('Documento não encontrado: $id');
    return value;
  }

  void _replace(ScannedDocument value) {
    final List<ScannedDocument> next =
        _documents.where((ScannedDocument item) => item.id != value.id).toList()
          ..add(value)
          ..sort(
            (ScannedDocument first, ScannedDocument second) =>
                second.updatedAt.compareTo(first.updatedAt),
          );
    _documents = List<ScannedDocument>.unmodifiable(next);
  }
}
