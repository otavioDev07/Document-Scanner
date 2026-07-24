import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

import '../../features/documents/domain/document_folder.dart';
import '../../features/documents/domain/scanned_document.dart';
import '../files/document_repository.dart';

final class BackupRestoreResult {
  const BackupRestoreResult({
    required this.importedDocuments,
    required this.updatedDocuments,
    required this.skippedDocuments,
  });

  final int importedDocuments;
  final int updatedDocuments;
  final int skippedDocuments;

  int get changedDocuments => importedDocuments + updatedDocuments;
}

final class BackupService {
  BackupService(this._repository);

  static const String product = 'oss-document-scanner-flutter';
  static const int schemaVersion = 1;

  final DocumentRepository _repository;

  Future<File> createBackup({
    String? password,
    Directory? outputDirectory,
  }) async {
    final Directory root = await _repository.rootDirectory;
    final Directory temporary = await Directory.systemTemp.createTemp(
      'oss_document_backup_',
    );
    final File archive = File(path.join(temporary.path, 'backup.zip'));
    final ZipFileEncoder encoder = ZipFileEncoder(
      password: _cleanPassword(password),
    );
    try {
      encoder.create(archive.path);
      encoder.addArchiveFile(
        ArchiveFile.string(
          'backup_manifest.json',
          jsonEncode(<String, Object>{
            'product': product,
            'schemaVersion': schemaVersion,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      );
      await encoder.addDirectory(
        root,
        includeDirName: false,
        followLinks: false,
        filter: (FileSystemEntity entity, double progress) {
          final String relative = path.relative(entity.path, from: root.path);
          final String first = path.split(relative).first;
          final String name = path.basename(relative);
          final bool documentData = first.startsWith('doc_');
          final bool folderData = relative == 'folders.json';
          final bool transient =
              name.contains('.pending') || name.contains('.backup');
          return (documentData || folderData) && !transient
              ? ZipFileOperation.include
              : ZipFileOperation.skip;
        },
      );
      await encoder.close();

      final Directory destination =
          outputDirectory ?? await _repository.exportsDirectory();
      await destination.create(recursive: true);
      final String stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final File output = File(
        path.join(destination.path, 'oss-document-scanner-$stamp.zip'),
      );
      return archive.copy(output.path);
    } finally {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    }
  }

  Future<BackupRestoreResult> restoreBackup(
    File archive, {
    String? password,
  }) async {
    if (!await archive.exists()) {
      throw FileSystemException('Backup file does not exist', archive.path);
    }
    final Directory extracted = await Directory.systemTemp.createTemp(
      'oss_document_restore_',
    );
    try {
      await extractFileToDisk(
        archive.path,
        extracted.path,
        password: _cleanPassword(password),
      );
      await _validateManifest(extracted);
      final Directory root = await _repository.rootDirectory;
      int imported = 0;
      int updated = 0;
      int skipped = 0;

      await for (final FileSystemEntity entity in extracted.list()) {
        if (entity is! Directory ||
            !path.basename(entity.path).startsWith('doc_')) {
          continue;
        }
        final ScannedDocument incoming = await _readDocument(entity);
        if (path.basename(entity.path) != 'doc_${incoming.id}') {
          throw const FormatException(
            'Backup contains a mismatched document identifier',
          );
        }
        final Directory destination = Directory(
          path.join(root.path, 'doc_${incoming.id}'),
        );
        if (!await destination.exists()) {
          await _replaceDirectory(entity, destination);
          imported++;
          continue;
        }
        final ScannedDocument current = await _readDocument(destination);
        if (incoming.updatedAt.isAfter(current.updatedAt)) {
          await _replaceDirectory(entity, destination);
          updated++;
        } else {
          skipped++;
        }
      }

      final File folderFile = File(path.join(extracted.path, 'folders.json'));
      if (await folderFile.exists()) {
        final Object? decoded = jsonDecode(await folderFile.readAsString());
        if (decoded is Map && decoded['folders'] is List) {
          await _repository.mergeFolders(
            (decoded['folders'] as List).map(DocumentFolder.fromJson),
          );
        }
      }
      return BackupRestoreResult(
        importedDocuments: imported,
        updatedDocuments: updated,
        skippedDocuments: skipped,
      );
    } finally {
      if (await extracted.exists()) await extracted.delete(recursive: true);
    }
  }

  Future<void> _validateManifest(Directory extracted) async {
    final File manifest = File(
      path.join(extracted.path, 'backup_manifest.json'),
    );
    if (!await manifest.exists()) {
      throw const FormatException('This is not an OSS Document Scanner backup');
    }
    final Object? decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map ||
        decoded['product'] != product ||
        decoded['schemaVersion'] is! num ||
        (decoded['schemaVersion'] as num).toInt() > schemaVersion) {
      throw const FormatException('Backup format is unsupported');
    }
  }

  Future<ScannedDocument> _readDocument(Directory directory) async {
    final File metadata = File(path.join(directory.path, 'metadata.json'));
    if (!await metadata.exists()) {
      throw const FormatException('Backup document metadata is missing');
    }
    final ScannedDocument document = ScannedDocument.fromJson(
      jsonDecode(await metadata.readAsString()),
    );
    for (final ScannedPage page in document.pages) {
      if (!await File(path.join(directory.path, page.fileName)).exists()) {
        throw const FormatException('Backup document page is missing');
      }
    }
    return document;
  }

  Future<void> _replaceDirectory(
    Directory source,
    Directory destination,
  ) async {
    final Directory pending = Directory('${destination.path}.restore_pending');
    final Directory backup = Directory('${destination.path}.restore_backup');
    if (await pending.exists()) await pending.delete(recursive: true);
    if (await backup.exists()) await backup.delete(recursive: true);
    await _copyDirectory(source, pending);
    if (await destination.exists()) await destination.rename(backup.path);
    try {
      await pending.rename(destination.path);
      if (await backup.exists()) await backup.delete(recursive: true);
    } catch (_) {
      if (!await destination.exists() && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final FileSystemEntity entity in source.list()) {
      final String target = path.join(
        destination.path,
        path.basename(entity.path),
      );
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.openRead().pipe(File(target).openWrite());
      }
    }
  }

  String? _cleanPassword(String? value) {
    final String cleaned = value?.trim() ?? '';
    return cleaned.isEmpty ? null : cleaned;
  }
}
