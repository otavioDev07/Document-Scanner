import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/files/document_repository.dart';
import '../core/localization/legacy_localizations.dart';
import '../features/documents/application/document_library_controller.dart';
import '../features/documents/presentation/document_library_page.dart';
import '../features/settings/application/scanner_settings_controller.dart';

class OssDocumentScannerApp extends StatefulWidget {
  const OssDocumentScannerApp({
    super.key,
    this.documentController,
    this.settingsController,
  });

  final DocumentLibraryController? documentController;
  final ScannerSettingsController? settingsController;

  @override
  State<OssDocumentScannerApp> createState() => _OssDocumentScannerAppState();
}

class _OssDocumentScannerAppState extends State<OssDocumentScannerApp> {
  late final DocumentLibraryController _documents =
      widget.documentController ??
      DocumentLibraryController(repository: DocumentRepository());
  late final ScannerSettingsController _settings =
      widget.settingsController ?? ScannerSettingsController();
  late Future<void> _initialization;
  String? _localeId;
  bool _localeUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _localeId = _settings.localeId;
    _settings.addListener(_handleSettingsChanged);
    _initialization = _initialize();
  }

  void _handleSettingsChanged() {
    if (_localeId == _settings.localeId || _localeUpdateScheduled) return;
    _localeUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _localeUpdateScheduled = false;
      if (!mounted || _localeId == _settings.localeId) return;
      setState(() => _localeId = _settings.localeId);
    });
  }

  Future<void> _initialize() async {
    await Future.wait<void>(<Future<void>>[
      _documents.load(),
      _settings.load(),
    ]);
  }

  void _retry() => setState(() => _initialization = _initialize());

  @override
  void dispose() {
    _settings.removeListener(_handleSettingsChanged);
    if (widget.documentController == null) _documents.dispose();
    if (widget.settingsController == null) _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'OSS Document Scanner',
    locale: _localeId == null
        ? null
        : LegacyLocalizations.localeFromId(_localeId!),
    supportedLocales: LegacyLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      LegacyLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF006C51),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      cardTheme: const CardThemeData(clipBehavior: Clip.antiAlias),
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF43D6A2),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      cardTheme: const CardThemeData(clipBehavior: Clip.antiAlias),
    ),
    home: FutureBuilder<void>(
      future: _initialization,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AppLoadingPage();
        }
        if (snapshot.hasError) {
          return _AppInitializationError(
            error: snapshot.error!,
            onRetry: _retry,
          );
        }
        return DocumentLibraryPage(controller: _documents, settings: _settings);
      },
    ),
  );
}

class _AppLoadingPage extends StatelessWidget {
  const _AppLoadingPage();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _AppInitializationError extends StatelessWidget {
  const _AppInitializationError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              context.l10n.text(
                'startup_error',
                fallback: 'Não foi possível abrir a biblioteca de documentos.',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text(
                context.l10n.text('retry', fallback: 'Tentar de novo'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
