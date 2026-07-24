import 'dart:async';
import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oss_document_scanner_flutter/core/backup/backup_service.dart';
import 'package:oss_document_scanner_flutter/core/files/document_repository.dart';
import 'package:oss_document_scanner_flutter/core/sync/webdav_sync_service.dart';
import 'package:path/path.dart' as path;

void main() {
  test('WebDAV sync uploads, detects ETags, downloads and merges', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'oss_webdav_test_',
    );
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    List<int>? remoteBytes;
    int revision = 0;
    String? etag;
    final StreamSubscription<HttpRequest> subscription = server.listen((
      HttpRequest request,
    ) async {
      switch (request.method) {
        case 'MKCOL':
          request.response.statusCode = HttpStatus.created;
        case 'HEAD':
          if (remoteBytes == null) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.set(HttpHeaders.etagHeader, etag!);
          }
        case 'GET':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.etagHeader, etag!);
          request.response.add(remoteBytes!);
        case 'PUT':
          remoteBytes = await request.fold<List<int>>(
            <int>[],
            (List<int> value, List<int> chunk) => value..addAll(chunk),
          );
          revision++;
          etag = '"revision-$revision"';
          request.response.statusCode = HttpStatus.created;
          request.response.headers.set(HttpHeaders.etagHeader, etag!);
      }
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    Future<DocumentRepository> repository(String name, String document) async {
      final Directory root = Directory(path.join(sandbox.path, name));
      final File image = await File(
        'assets/test-document.png',
      ).copy(path.join(sandbox.path, '$name.png'));
      final DocumentRepository value = DocumentRepository(
        rootDirectory: () async => root,
      );
      await value.createFromCrop(
        CropResult(path: image.path, width: 1200, height: 1600),
        name: document,
      );
      return value;
    }

    final DocumentRepository local = await repository('local', 'Local');
    final WebDavSyncService service = WebDavSyncService(BackupService(local));
    final WebDavConfiguration configuration = WebDavConfiguration(
      serverUrl: 'http://127.0.0.1:${server.port}',
      username: 'user',
      remoteDirectory: 'documents',
    );
    final WebDavSyncResult first = await service.synchronize(
      configuration: configuration,
      credential: 'password',
      encryptionPassword: 'encryption-password',
    );
    expect(first.downloadedRemoteBackup, isFalse);
    expect(remoteBytes, isNotEmpty);

    final DocumentRepository remote = await repository('remote', 'Remote');
    final File remoteBackup = await BackupService(
      remote,
    ).createBackup(password: 'encryption-password', outputDirectory: sandbox);
    remoteBytes = await remoteBackup.readAsBytes();
    revision++;
    etag = '"revision-$revision"';

    final WebDavSyncResult second = await service.synchronize(
      configuration: configuration,
      credential: 'password',
      encryptionPassword: 'encryption-password',
      lastEtag: first.etag,
    );
    expect(second.downloadedRemoteBackup, isTrue);
    expect(second.restoreResult?.importedDocuments, 1);
    expect(
      (await local.loadDocuments()).map((document) => document.name),
      containsAll(<String>['Local', 'Remote']),
    );
  });
}
