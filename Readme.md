# OSS Document Scanner — Flutter

Aplicativo Flutter para digitalizar, recortar, organizar, exportar e compartilhar documentos. A interface e a lógica de produto estão em Flutter; câmera, detecção contínua e processamento OpenCV permanecem nativos.

## Estrutura

- `document_scanner_flutter/`: plugin Flutter e núcleo compartilhado C++/OpenCV.
- `document_scanner_flutter/example/`: aplicativo completo e executável do OSS Document Scanner.
- `document_scanner_flutter/native/`: detector compartilhado, integração Objective-C++ e pacote Swift nativo.
- `MIGRATION_PROGRESS.md`: estado verificável da migração.
- `FEATURE_PARITY.md`: matriz de paridade e testes.

O diretório `example/` segue a convenção de plugins Flutter, mas é o aplicativo distribuível completo: biblioteca de documentos, câmera, importação, editor de recorte, filtros nativos, páginas, PDF, compartilhamento e configurações.

## Executar

Requer Flutter 3.44.7 ou compatível, Android SDK/NDK e, para iOS, macOS com Xcode e um runtime de simulador instalado.

```bash
cd document_scanner_flutter
flutter pub get

cd example
flutter pub get
flutter run
```

Para selecionar um destino explicitamente:

```bash
flutter devices
flutter run -d <device-id>
```

## Validar

```bash
cd document_scanner_flutter
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test

cd example
flutter analyze
flutter test
flutter build apk --debug
```

### iOS

O framework OpenCV para iOS não é versionado por causa do tamanho. Prepare-o uma vez:

```bash
cd document_scanner_flutter
./tool/bootstrap_ios.sh

cd example
flutter build ios --simulator --debug
```

Nenhuma assinatura ou configuração de publicação é necessária para os builds de desenvolvimento.

## Arquitetura do scanner

```text
CameraX / AVFoundation
  -> frame nativo com backpressure latest-only
  -> OpenCV/C++ (contornos, quadrilátero e estabilidade)
  -> EventChannel com pontos normalizados e métricas
  -> Texture para o preview
  -> CustomPainter Flutter para o overlay
```

Frames de câmera não atravessam os canais Flutter. O recorte em perspectiva e os filtros de página são executados nativamente; Dart recebe apenas metadados e caminhos de arquivos.

## Licença

Veja [LICENSE](LICENSE).
