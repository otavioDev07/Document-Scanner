import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../backup/backup_service.dart';

final class WebDavConfiguration {
  const WebDavConfiguration({
    required this.serverUrl,
    required this.username,
    this.remoteDirectory = 'OSS-DocumentScanner',
  });

  final String serverUrl;
  final String username;
  final String remoteDirectory;

  Uri get baseUri {
    final Uri value = Uri.parse(serverUrl.trim());
    if (!value.hasScheme ||
        (value.scheme != 'https' && value.scheme != 'http') ||
        value.host.isEmpty) {
      throw ArgumentError.value(serverUrl, 'serverUrl', 'Invalid WebDAV URL');
    }
    return value;
  }
}

final class WebDavSyncResult {
  const WebDavSyncResult({
    required this.etag,
    required this.downloadedRemoteBackup,
    required this.restoreResult,
  });

  final String? etag;
  final bool downloadedRemoteBackup;
  final BackupRestoreResult? restoreResult;
}

final class WebDavSyncService {
  WebDavSyncService(this._backups, {HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final BackupService _backups;
  final HttpClient Function() _clientFactory;

  Future<WebDavSyncResult> synchronize({
    required WebDavConfiguration configuration,
    required String credential,
    required String encryptionPassword,
    String? lastEtag,
  }) async {
    if (credential.isEmpty) {
      throw const FormatException('WebDAV password is required');
    }
    if (encryptionPassword.trim().length < 8) {
      throw const FormatException(
        'Backup encryption password must have at least 8 characters',
      );
    }
    final HttpClient client = _clientFactory();
    final Directory temporary = await Directory.systemTemp.createTemp(
      'oss_document_webdav_',
    );
    try {
      final String authorization =
          'Basic ${base64Encode(utf8.encode('${configuration.username}:$credential'))}';
      final Uri collection = _collectionUri(configuration);
      await _ensureCollection(client, collection, authorization);
      final Uri remoteFile = _remoteFileUri(configuration);
      final _RemoteMetadata metadata = await _head(
        client,
        remoteFile,
        authorization,
      );

      BackupRestoreResult? restoreResult;
      final bool remoteChanged =
          metadata.exists &&
          (lastEtag == null ||
              metadata.etag == null ||
              metadata.etag != lastEtag);
      if (remoteChanged) {
        final File downloaded = File(path.join(temporary.path, 'remote.zip'));
        await _download(client, remoteFile, authorization, downloaded);
        restoreResult = await _backups.restoreBackup(
          downloaded,
          password: encryptionPassword,
        );
      }

      final File local = await _backups.createBackup(
        password: encryptionPassword,
        outputDirectory: temporary,
      );
      final String? uploadedEtag = await _upload(
        client,
        remoteFile,
        authorization,
        local,
        previous: metadata,
      );
      return WebDavSyncResult(
        etag: uploadedEtag,
        downloadedRemoteBackup: remoteChanged,
        restoreResult: restoreResult,
      );
    } finally {
      client.close(force: true);
      if (await temporary.exists()) await temporary.delete(recursive: true);
    }
  }

  Uri _collectionUri(WebDavConfiguration configuration) {
    final Uri base = configuration.baseUri;
    return base.replace(
      path: path.posix.join(base.path, configuration.remoteDirectory),
      query: null,
      fragment: null,
    );
  }

  Uri _remoteFileUri(WebDavConfiguration configuration) {
    final Uri collection = _collectionUri(configuration);
    return collection.replace(
      path: path.posix.join(collection.path, 'latest.zip'),
    );
  }

  Future<void> _ensureCollection(
    HttpClient client,
    Uri uri,
    String authorization,
  ) async {
    final HttpClientRequest request = await client.openUrl('MKCOL', uri);
    request.headers.set(HttpHeaders.authorizationHeader, authorization);
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    if (response.statusCode != HttpStatus.created &&
        response.statusCode != HttpStatus.methodNotAllowed &&
        response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.noContent) {
      throw HttpException(
        'WebDAV could not create the remote folder (${response.statusCode})',
        uri: uri,
      );
    }
  }

  Future<_RemoteMetadata> _head(
    HttpClient client,
    Uri uri,
    String authorization,
  ) async {
    final HttpClientRequest request = await client.headUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, authorization);
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    if (response.statusCode == HttpStatus.notFound) {
      return const _RemoteMetadata(exists: false);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'WebDAV HEAD failed (${response.statusCode})',
        uri: uri,
      );
    }
    return _RemoteMetadata(
      exists: true,
      etag: response.headers.value(HttpHeaders.etagHeader),
    );
  }

  Future<void> _download(
    HttpClient client,
    Uri uri,
    String authorization,
    File destination,
  ) async {
    final HttpClientRequest request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, authorization);
    final HttpClientResponse response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException(
        'WebDAV download failed (${response.statusCode})',
        uri: uri,
      );
    }
    await response.pipe(destination.openWrite());
  }

  Future<String?> _upload(
    HttpClient client,
    Uri uri,
    String authorization,
    File source, {
    required _RemoteMetadata previous,
  }) async {
    final HttpClientRequest request = await client.putUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, authorization);
    request.headers.contentType = ContentType('application', 'zip');
    request.contentLength = await source.length();
    if (previous.exists && previous.etag != null) {
      request.headers.set(HttpHeaders.ifMatchHeader, previous.etag!);
    } else if (!previous.exists) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, '*');
    }
    await request.addStream(source.openRead());
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    if (response.statusCode == HttpStatus.preconditionFailed) {
      throw const HttpException(
        'The remote backup changed during synchronization; retry safely',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'WebDAV upload failed (${response.statusCode})',
        uri: uri,
      );
    }
    return response.headers.value(HttpHeaders.etagHeader) ??
        (await _head(client, uri, authorization)).etag;
  }
}

final class _RemoteMetadata {
  const _RemoteMetadata({required this.exists, this.etag});

  final bool exists;
  final String? etag;
}
