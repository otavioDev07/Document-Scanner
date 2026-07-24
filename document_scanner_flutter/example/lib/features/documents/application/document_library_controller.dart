import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:document_scanner_flutter/document_scanner_flutter_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../core/export/pdf_export_service.dart';
import '../../../core/files/document_repository.dart';
import '../domain/scanned_document.dart';

final class DocumentLibraryController extends ChangeNotifier {
  DocumentLibraryController({
    required DocumentRepository repository,
    PdfExportService? pdfExportService,
    Future<OcrResult> Function(String imagePath, List<String> languages)?
    recognizeText,
  }) : _repository = repository,
       _pdfExportService = pdfExportService ?? PdfExportService(repository),
       _recognizeText = recognizeText ?? _defaultRecognizeText;

  final DocumentRepository _repository;
  final PdfExportService _pdfExportService;
  final Future<OcrResult> Function(String imagePath, List<String> languages)
  _recognizeText;

  List<ScannedDocument> _documents = const <ScannedDocument>[];
  bool _busy = false;
  Object? _lastError;

  List<ScannedDocument> get documents => _documents;
  List<ScannedDocument> get activeDocuments => _documents
      .where((ScannedDocument document) => !document.isTrashed)
      .toList(growable: false);
  List<ScannedDocument> get favoriteDocuments => _documents
      .where(
        (ScannedDocument document) => !document.isTrashed && document.favorite,
      )
      .toList(growable: false);
  List<ScannedDocument> get trashedDocuments => _documents
      .where((ScannedDocument document) => document.isTrashed)
      .toList(growable: false);
  bool get busy => _busy;
  Object? get lastError => _lastError;
  DocumentRepository get repository => _repository;

  ScannedDocument? document(String id) {
    for (final ScannedDocument document in _documents) {
      if (document.id == id) return document;
    }
    return null;
  }

  Future<void> load() => _run<void>(() async {
    _documents = await _repository.loadDocuments();
  });

  List<ScannedDocument> search(
    String query, {
    bool favoritesOnly = false,
    bool trashOnly = false,
  }) {
    final String normalized = query.trim().toLowerCase();
    return _documents
        .where((ScannedDocument document) {
          if (trashOnly != document.isTrashed) return false;
          if (favoritesOnly && !document.favorite) return false;
          return normalized.isEmpty ||
              document.searchableText.contains(normalized);
        })
        .toList(growable: false);
  }

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

  Future<void> setFavorite(String documentId, bool favorite) =>
      _run<void>(() async {
        _replace(await _repository.setFavorite(_require(documentId), favorite));
      });

  Future<void> moveToTrash(String documentId) => _run<void>(() async {
    _replace(await _repository.moveToTrash(_require(documentId)));
  });

  Future<void> restoreFromTrash(String documentId) => _run<void>(() async {
    _replace(await _repository.restoreFromTrash(_require(documentId)));
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

  Future<void> emptyTrash() => _run<void>(() async {
    await _repository.emptyTrash();
    _documents = _documents
        .where((ScannedDocument document) => !document.isTrashed)
        .toList(growable: false);
  });

  Future<void> saveOcr(
    String documentId,
    String pageId,
    String text, {
    String? language,
  }) => _run<void>(() async {
    _replace(
      await _repository.saveOcr(
        _require(documentId),
        pageId,
        text,
        language: language,
      ),
    );
  });

  Future<OcrResult> recognizePage(
    String documentId,
    String pageId, {
    List<String> languages = const <String>[],
  }) => _run<OcrResult>(() async {
    final File file = await pageFile(documentId, pageId);
    final OcrResult result = await _recognizeText(file.path, languages);
    _replace(
      await _repository.saveOcr(
        _require(documentId),
        pageId,
        result.text,
        language: result.languages.isEmpty ? null : result.languages.first,
      ),
    );
    return result;
  });

  Future<void> recognizeDocument(
    String documentId, {
    List<String> languages = const <String>[],
  }) => _run<void>(() async {
    ScannedDocument current = _require(documentId);
    for (final ScannedPage page in current.pages) {
      final File file = await _repository.pageFile(current, page);
      final OcrResult result = await _recognizeText(file.path, languages);
      current = await _repository.saveOcr(
        current,
        page.id,
        result.text,
        language: result.languages.isEmpty ? null : result.languages.first,
      );
      _replace(current);
    }
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

  static Future<OcrResult> _defaultRecognizeText(
    String imagePath,
    List<String> languages,
  ) => DocumentScannerFlutterPlatform.instance.recognizeText(
    imagePath,
    languages: languages,
  );
}
