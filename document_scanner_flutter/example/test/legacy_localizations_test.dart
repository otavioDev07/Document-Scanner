import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oss_document_scanner_flutter/core/localization/legacy_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads every legacy locale catalog and translates core keys', () async {
    const LegacyLocalizationsDelegate delegate = LegacyLocalizationsDelegate();
    for (final Locale locale in LegacyLocalizations.supportedLocales) {
      final LegacyLocalizations localization = await delegate.load(locale);
      expect(
        localization.text('documents', fallback: 'documents'),
        isNotEmpty,
        reason: 'Locale ${locale.toLanguageTag()}',
      );
      expect(
        localization.text('scan', fallback: 'scan'),
        isNotEmpty,
        reason: 'Locale ${locale.toLanguageTag()}',
      );
    }

    final LegacyLocalizations portuguese = await delegate.load(
      const Locale('pt', 'BR'),
    );
    expect(portuguese.text('documents'), 'documentos');
    expect(portuguese.pages(3), '3 páginas');
  });
}
