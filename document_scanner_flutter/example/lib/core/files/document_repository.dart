import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:document_scanner_flutter/document_scanner_flutter_platform_interface.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../features/documents/domain/scanned_document.dart';
import '../../features/documents/domain/document_folder.dart';

typedef NativeFilterOperation =
    Future<CropResult> Function(
      String imagePath,
      String outputPath,
      String filter,
    );

final class DocumentRepository {
  DocumentRepository({
    Future<Directory> Function()? rootDirectory,
    NativeFilterOperation? nativeFilter,
  }) : _rootDirectory = rootDirectory ?? _defaultRootDirectory,
       _nativeFilter = nativeFilter ?? _defaultNativeFilter;

  final Future<Directory> Function() _rootDirectory;
  final NativeFilterOperation _nativeFilter;
  final Random _random = Random.secure();

  Future<Directory> get rootDirectory => _ensureRoot();

  Future<List<ScannedDocument>> loadDocuments() async {
    final Directory root = await _ensureRoot();
    final List<ScannedDocument> documents = <ScannedDocument>[];
    await for (final FileSystemEntity entity in root.list()) {
      if (entity is! Directory ||
          !path.basename(entity.path).startsWith('doc_')) {
        continue;
      }
      final File metadata = File(path.join(entity.path, 'metadata.json'));
      final File backup = File(path.join(entity.path, 'metadata.backup.json'));
      if (!await metadata.exists() && await backup.exists()) {
        await backup.rename(metadata.path);
      }
      if (!await metadata.exists()) continue;
      try {
        final ScannedDocument document = ScannedDocument.fromJson(
          jsonDecode(await metadata.readAsString()),
        );
        final bool allPagesExist = await Future.wait(
          document.pages.map(
            (ScannedPage page) =>
                File(path.join(entity.path, page.fileName)).exists(),
          ),
        ).then((List<bool> values) => values.every((bool value) => value));
        if (allPagesExist) documents.add(document);
      } on FormatException {
        // Corrupt metadata stays on disk for recovery; it is never deleted here.
      }
    }
    documents.sort(
      (ScannedDocument first, ScannedDocument second) =>
          second.updatedAt.compareTo(first.updatedAt),
    );
    return documents;
  }

  Future<List<DocumentFolder>> loadFolders() async {
    final Directory root = await _ensureRoot();
    final File metadata = File(path.join(root.path, 'folders.json'));
    final File backup = File(path.join(root.path, 'folders.backup.json'));
    if (!await metadata.exists() && await backup.exists()) {
      await backup.rename(metadata.path);
    }
    if (!await metadata.exists()) return const <DocumentFolder>[];
    try {
      final Object? decoded = jsonDecode(await metadata.readAsString());
      if (decoded is! Map || decoded['folders'] is! List) {
        throw const FormatException('Folder metadata is invalid');
      }
      final List<DocumentFolder> folders =
          (decoded['folders'] as List)
              .map(DocumentFolder.fromJson)
              .toList(growable: false)
            ..sort(
              (DocumentFolder first, DocumentFolder second) =>
                  first.name.toLowerCase().compareTo(second.name.toLowerCase()),
            );
      return folders;
    } on FormatException {
      return const <DocumentFolder>[];
    }
  }

  Future<DocumentFolder> createFolder(String name, {int? colorValue}) async {
    final List<DocumentFolder> folders = await loadFolders();
    final String validated = _validatedName(name);
    if (folders.any(
      (DocumentFolder folder) =>
          folder.name.toLowerCase() == validated.toLowerCase(),
    )) {
      throw ArgumentError.value(name, 'name', 'Folder already exists');
    }
    final DateTime now = DateTime.now();
    final DocumentFolder folder = DocumentFolder(
      id: _id(now),
      name: validated,
      colorValue: colorValue ?? 0xFF1565C0,
      createdAt: now,
      updatedAt: now,
    );
    await _writeFolders(<DocumentFolder>[...folders, folder]);
    return folder;
  }

  Future<DocumentFolder> renameFolder(
    DocumentFolder folder,
    String name,
  ) async {
    final List<DocumentFolder> folders = await loadFolders();
    final String validated = _validatedName(name);
    if (folders.any(
      (DocumentFolder item) =>
          item.id != folder.id &&
          item.name.toLowerCase() == validated.toLowerCase(),
    )) {
      throw ArgumentError.value(name, 'name', 'Folder already exists');
    }
    final DocumentFolder updated = folder.copyWith(
      name: validated,
      updatedAt: DateTime.now(),
    );
    await _writeFolders(
      folders
          .map((DocumentFolder item) => item.id == folder.id ? updated : item)
          .toList(growable: false),
    );
    return updated;
  }

  Future<void> deleteFolder(String folderId) async {
    final List<DocumentFolder> folders = await loadFolders();
    await _writeFolders(
      folders
          .where((DocumentFolder folder) => folder.id != folderId)
          .toList(growable: false),
    );
    for (final ScannedDocument document in await loadDocuments()) {
      if (!document.folderIds.contains(folderId)) continue;
      await _saveDocument(
        document.copyWith(
          folderIds: document.folderIds
              .where((String id) => id != folderId)
              .toList(growable: false),
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> mergeFolders(Iterable<DocumentFolder> incoming) async {
    final Map<String, DocumentFolder> merged = <String, DocumentFolder>{
      for (final DocumentFolder folder in await loadFolders())
        folder.id: folder,
    };
    for (final DocumentFolder folder in incoming) {
      final DocumentFolder? current = merged[folder.id];
      if (current == null || folder.updatedAt.isAfter(current.updatedAt)) {
        merged[folder.id] = folder;
      }
    }
    await _writeFolders(merged.values.toList(growable: false));
  }

  Future<ScannedDocument> createFromCrop(
    CropResult crop, {
    String? name,
  }) async {
    final DateTime now = DateTime.now();
    final String id = _id(now);
    final Directory directory = await _documentDirectory(id);
    await directory.create(recursive: true);
    final ScannedPage page = await _persistPage(directory, crop, now);
    final ScannedDocument document = ScannedDocument(
      id: id,
      name: _validatedName(name ?? _defaultName(now)),
      createdAt: now,
      updatedAt: now,
      pages: <ScannedPage>[page],
    );
    await _writeMetadata(directory, document);
    return document;
  }

  Future<ScannedDocument> addPage(
    ScannedDocument document,
    CropResult crop,
  ) async {
    final Directory directory = await _documentDirectory(document.id);
    if (!await directory.exists()) {
      throw FileSystemException(
        'Document directory no longer exists',
        directory.path,
      );
    }
    final DateTime now = DateTime.now();
    final ScannedPage page = await _persistPage(directory, crop, now);
    final ScannedDocument updated = document.copyWith(
      pages: <ScannedPage>[...document.pages, page],
      updatedAt: now,
    );
    await _writeMetadata(directory, updated);
    return updated;
  }

  Future<ScannedDocument> rename(ScannedDocument document, String name) async {
    final ScannedDocument updated = document.copyWith(
      name: _validatedName(name),
      updatedAt: DateTime.now(),
    );
    await _writeMetadata(await _documentDirectory(document.id), updated);
    return updated;
  }

  Future<ScannedDocument> setFavorite(
    ScannedDocument document,
    bool favorite,
  ) => _updateDocument(document, document.copyWith(favorite: favorite));

  Future<ScannedDocument> setFolders(
    ScannedDocument document,
    Iterable<String> folderIds,
  ) async {
    final Set<String> existing = (await loadFolders())
        .map((DocumentFolder folder) => folder.id)
        .toSet();
    final List<String> valid = folderIds
        .where(existing.contains)
        .toSet()
        .toList(growable: false);
    return _updateDocument(document, document.copyWith(folderIds: valid));
  }

  Future<ScannedDocument> moveToTrash(ScannedDocument document) =>
      _updateDocument(
        document,
        document.copyWith(trashedAt: DateTime.now(), favorite: false),
      );

  Future<ScannedDocument> restoreFromTrash(ScannedDocument document) =>
      _updateDocument(document, document.copyWith(trashedAt: null));

  Future<ScannedDocument> saveOcr(
    ScannedDocument document,
    String pageId,
    String text, {
    String? language,
  }) async {
    if (!document.pages.any((ScannedPage page) => page.id == pageId)) {
      throw ArgumentError.value(pageId, 'pageId');
    }
    final DateTime now = DateTime.now();
    return _updateDocument(
      document,
      document.copyWith(
        pages: document.pages
            .map(
              (ScannedPage page) => page.id == pageId
                  ? page.copyWith(
                      ocrText: text.trim(),
                      ocrLanguage: language,
                      ocrUpdatedAt: now,
                    )
                  : page,
            )
            .toList(growable: false),
        updatedAt: now,
      ),
      touch: false,
    );
  }

  Future<ScannedDocument> reorderPages(
    ScannedDocument document,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < 0 || oldIndex >= document.pages.length) {
      throw RangeError.index(oldIndex, document.pages, 'oldIndex');
    }
    final List<ScannedPage> pages = List<ScannedPage>.of(document.pages);
    if (newIndex < 0 || newIndex >= pages.length) {
      throw RangeError.index(newIndex, pages, 'newIndex');
    }
    final ScannedPage page = pages.removeAt(oldIndex);
    pages.insert(newIndex, page);
    final ScannedDocument updated = document.copyWith(
      pages: pages,
      updatedAt: DateTime.now(),
    );
    await _writeMetadata(await _documentDirectory(document.id), updated);
    return updated;
  }

  Future<ScannedDocument> rotatePage(
    ScannedDocument document,
    String pageId,
  ) async {
    final List<ScannedPage> pages = document.pages
        .map(
          (ScannedPage page) => page.id == pageId
              ? page.copyWith(
                  rotationQuarterTurns: (page.rotationQuarterTurns + 1) % 4,
                )
              : page,
        )
        .toList(growable: false);
    if (!pages.any((ScannedPage page) => page.id == pageId)) {
      throw ArgumentError.value(pageId, 'pageId');
    }
    final ScannedDocument updated = document.copyWith(
      pages: pages,
      updatedAt: DateTime.now(),
    );
    await _writeMetadata(await _documentDirectory(document.id), updated);
    return updated;
  }

  Future<ScannedDocument> applyFilter(
    ScannedDocument document,
    String pageId,
    String filter,
  ) async {
    const Set<String> supported = <String>{
      'original',
      'grayscale',
      'highContrast',
      'colorBoost',
    };
    if (!supported.contains(filter)) {
      throw ArgumentError.value(filter, 'filter', 'Unsupported page filter');
    }
    final ScannedPage page = document.pages.firstWhere(
      (ScannedPage item) => item.id == pageId,
      orElse: () => throw ArgumentError.value(pageId, 'pageId'),
    );
    if (page.filter == filter) return document;

    final Directory directory = await _documentDirectory(document.id);
    final File destination = File(path.join(directory.path, page.fileName));
    final File original = File(
      path.join(directory.path, 'original_${page.fileName}'),
    );
    if (!await original.exists()) await destination.copy(original.path);
    final File pending = File('${destination.path}.filter.pending');
    if (await pending.exists()) await pending.delete();
    if (filter == 'original') {
      await original.copy(pending.path);
    } else {
      await _nativeFilter(original.path, pending.path, filter);
    }
    await pending.rename(destination.path);

    final List<ScannedPage> pages = document.pages
        .map(
          (ScannedPage item) =>
              item.id == pageId ? item.copyWith(filter: filter) : item,
        )
        .toList(growable: false);
    final ScannedDocument updated = document.copyWith(
      pages: pages,
      updatedAt: DateTime.now(),
    );
    await _writeMetadata(directory, updated);
    return updated;
  }

  Future<ScannedDocument?> deletePage(
    ScannedDocument document,
    String pageId,
  ) async {
    final ScannedPage page = document.pages.firstWhere(
      (ScannedPage item) => item.id == pageId,
      orElse: () => throw ArgumentError.value(pageId, 'pageId'),
    );
    if (document.pages.length == 1) {
      await deleteDocument(document);
      return null;
    }
    final List<ScannedPage> pages = document.pages
        .where((ScannedPage item) => item.id != pageId)
        .toList(growable: false);
    final Directory directory = await _documentDirectory(document.id);
    final ScannedDocument updated = document.copyWith(
      pages: pages,
      updatedAt: DateTime.now(),
    );
    await _writeMetadata(directory, updated);
    final File pageFile = File(path.join(directory.path, page.fileName));
    if (await pageFile.exists()) await pageFile.delete();
    final File originalFile = File(
      path.join(directory.path, 'original_${page.fileName}'),
    );
    if (await originalFile.exists()) await originalFile.delete();
    return updated;
  }

  Future<void> deleteDocument(ScannedDocument document) async {
    final Directory directory = await _documentDirectory(document.id);
    if (await directory.exists()) await directory.delete(recursive: true);
    final Directory exports = await exportsDirectory();
    await for (final FileSystemEntity entity in exports.list()) {
      if (entity is File &&
          path.basename(entity.path).endsWith('_${document.id}.pdf')) {
        await entity.delete();
      }
    }
  }

  Future<void> emptyTrash() async {
    for (final ScannedDocument document in await loadDocuments()) {
      if (document.isTrashed) await deleteDocument(document);
    }
  }

  Future<File> pageFile(ScannedDocument document, ScannedPage page) async {
    final Directory directory = await _documentDirectory(document.id);
    return File(path.join(directory.path, page.fileName));
  }

  Future<Directory> exportsDirectory() async {
    final Directory root = await _ensureRoot();
    final Directory directory = Directory(path.join(root.path, 'exports'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<ScannedDocument> _updateDocument(
    ScannedDocument current,
    ScannedDocument updated, {
    bool touch = true,
  }) async {
    final ScannedDocument value = touch
        ? updated.copyWith(updatedAt: DateTime.now())
        : updated;
    await _saveDocument(value);
    return value;
  }

  Future<void> _saveDocument(ScannedDocument document) async {
    await _writeMetadata(await _documentDirectory(document.id), document);
  }

  Future<void> _writeFolders(List<DocumentFolder> folders) async {
    final Directory root = await _ensureRoot();
    final File metadata = File(path.join(root.path, 'folders.json'));
    final File pending = File(path.join(root.path, 'folders.pending.json'));
    final File backup = File(path.join(root.path, 'folders.backup.json'));
    final List<DocumentFolder> sorted = List<DocumentFolder>.of(folders)
      ..sort(
        (DocumentFolder first, DocumentFolder second) =>
            first.name.toLowerCase().compareTo(second.name.toLowerCase()),
      );
    await pending.writeAsString(
      jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'folders': sorted
            .map((DocumentFolder folder) => folder.toJson())
            .toList(growable: false),
      }),
      flush: true,
    );
    if (await backup.exists()) await backup.delete();
    if (await metadata.exists()) await metadata.rename(backup.path);
    try {
      await pending.rename(metadata.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await metadata.exists() && await backup.exists()) {
        await backup.rename(metadata.path);
      }
      rethrow;
    }
  }

  Future<ScannedPage> _persistPage(
    Directory directory,
    CropResult crop,
    DateTime createdAt,
  ) async {
    final File source = File(crop.path);
    if (!await source.exists()) {
      throw FileSystemException('Cropped image no longer exists', crop.path);
    }
    final String id = _id(createdAt);
    final String extension = path.extension(source.path).toLowerCase();
    final String safeExtension = extension == '.png' ? '.png' : '.jpg';
    final String fileName = 'page_$id$safeExtension';
    final File pending = File(path.join(directory.path, '$fileName.pending'));
    final File destination = File(path.join(directory.path, fileName));
    await source.openRead().pipe(pending.openWrite());
    await pending.rename(destination.path);
    return ScannedPage(
      id: id,
      fileName: fileName,
      width: crop.width,
      height: crop.height,
      createdAt: createdAt,
    );
  }

  Future<void> _writeMetadata(
    Directory directory,
    ScannedDocument document,
  ) async {
    await directory.create(recursive: true);
    final File metadata = File(path.join(directory.path, 'metadata.json'));
    final File pending = File(
      path.join(directory.path, 'metadata.pending.json'),
    );
    final File backup = File(path.join(directory.path, 'metadata.backup.json'));
    await pending.writeAsString(jsonEncode(document.toJson()), flush: true);
    if (await backup.exists()) await backup.delete();
    if (await metadata.exists()) await metadata.rename(backup.path);
    try {
      await pending.rename(metadata.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await metadata.exists() && await backup.exists()) {
        await backup.rename(metadata.path);
      }
      rethrow;
    }
  }

  Future<Directory> _documentDirectory(String id) async {
    final Directory root = await _ensureRoot();
    return Directory(path.join(root.path, 'doc_$id'));
  }

  Future<Directory> _ensureRoot() async {
    final Directory root = await _rootDirectory();
    await root.create(recursive: true);
    return root;
  }

  String _id(DateTime now) =>
      '${now.microsecondsSinceEpoch}_${_random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  String _validatedName(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 120) {
      throw ArgumentError.value(
        value,
        'name',
        'Use between 1 and 120 characters',
      );
    }
    return trimmed;
  }

  String _defaultName(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Documento ${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}-${two(date.minute)}';
  }

  static Future<Directory> _defaultRootDirectory() async {
    final Directory base = await getApplicationDocumentsDirectory();
    return Directory(path.join(base.path, 'OSSDocumentScanner'));
  }

  static Future<CropResult> _defaultNativeFilter(
    String imagePath,
    String outputPath,
    String filter,
  ) => DocumentScannerFlutterPlatform.instance.applyFilter(
    imagePath,
    outputPath,
    filter,
  );
}
