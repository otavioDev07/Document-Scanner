import 'package:flutter/material.dart';

import '../../../core/localization/legacy_localizations.dart';
import '../application/scanner_settings_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final ScannerSettingsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final LegacyLocalizations l10n = context.l10n;
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.text('settings.title', fallback: 'Configurações')),
          ),
          body: ListView(
            children: <Widget>[
              _SectionTitle(l10n.text('scan_settings', fallback: 'Scanner')),
              SwitchListTile.adaptive(
                title: Text(
                  l10n.text('autoscan', fallback: 'Captura automática'),
                ),
                subtitle: const Text(
                  'Fotografa quando o documento permanece estável e enquadrado.',
                ),
                value: controller.autoCapture,
                onChanged: controller.setAutoCapture,
              ),
              SwitchListTile.adaptive(
                title: const Text('Diagnóstico de desempenho'),
                subtitle: const Text(
                  'Coleta FPS, tempo de detecção e descarte de quadros.',
                ),
                value: controller.diagnosticsEnabled,
                onChanged: controller.setDiagnosticsEnabled,
              ),
              ListTile(
                title: Text(
                  l10n.text('jpeg_quality', fallback: 'Qualidade JPEG'),
                ),
                subtitle: Slider(
                  min: 60,
                  max: 100,
                  divisions: 8,
                  label: '${controller.jpegQuality}',
                  value: controller.jpegQuality.toDouble(),
                  onChanged: (double value) =>
                      controller.setJpegQuality(value.round()),
                ),
                trailing: Text('${controller.jpegQuality}%'),
              ),
              const Divider(),
              _SectionTitle(l10n.text('language', fallback: 'Idioma')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: DropdownButtonFormField<String>(
                  initialValue: controller.localeId ?? '',
                  decoration: InputDecoration(
                    labelText: l10n.text(
                      'select_language',
                      fallback: 'Idioma da interface',
                    ),
                  ),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('Sistema'),
                    ),
                    ...LegacyLocalizations.localeIds.map(
                      (String id) => DropdownMenuItem<String>(
                        value: id,
                        child: Text(LegacyLocalizations.displayName(id)),
                      ),
                    ),
                  ],
                  onChanged: (String? value) {
                    // Let the dropdown route finish dismissing before the
                    // root Localizations tree changes locale.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      controller.setLocaleId(
                        value == null || value.isEmpty ? null : value,
                      );
                    });
                  },
                ),
              ),
              const Divider(),
              const AboutListTile(
                applicationName: 'Document Scanner',
                applicationVersion: '0.2.0',
                applicationLegalese: 'Software livre',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
