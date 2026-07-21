import 'package:flutter/material.dart';

import '../application/scanner_settings_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final ScannerSettingsController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (BuildContext context, Widget? child) => Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        children: <Widget>[
          SwitchListTile.adaptive(
            title: const Text('Captura automática'),
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
            title: const Text('Qualidade JPEG'),
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
          const AboutListTile(
            applicationName: 'OSS Document Scanner',
            applicationVersion: '0.2.0',
            applicationLegalese: 'Software livre',
          ),
        ],
      ),
    ),
  );
}
