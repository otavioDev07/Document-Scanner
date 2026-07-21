import 'package:flutter/services.dart';

final class ScannerException implements Exception {
  const ScannerException(this.code, this.message, [this.details]);

  final String code;
  final String message;
  final Object? details;

  factory ScannerException.fromPlatform(PlatformException error) =>
      ScannerException(
        error.code,
        error.message ?? 'Native scanner operation failed',
        error.details,
      );

  @override
  String toString() => 'ScannerException($code): $message';
}
