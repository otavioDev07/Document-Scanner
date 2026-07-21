# document_scanner_flutter

Plugin interno do OSS Document Scanner para câmera, detecção e processamento OpenCV em Android/iOS. O aplicativo completo está em `example/`.

## Recursos

| Recurso | Android | iOS |
| --- | --- | --- |
| picker e imagem estática | sim | sim |
| detector C++/OpenCV | sim | sim |
| perspectiva nativa | sim | sim |
| filtros OpenCV | sim | sim |
| câmera/Texture | CameraX | AVFoundation |
| análise contínua latest-only | sim | sim |
| estabilidade/auto-captura | sim | sim |
| overlay/editor Flutter | sim | sim |

## Uso

```dart
final controller = DocumentScannerController(
  options: const ScannerOptions(autoCapture: true),
);

await controller.initialize();
await controller.startPreview();

DocumentScannerPreview(controller: controller);
```

Imagem estática e recorte:

```dart
final picked = await controller.pickImage();
if (picked != null) {
  final detection = await controller.detectDocument(picked.path);
  if (detection.documentFound) {
    final crop = await controller.cropDocument(
      picked.path,
      corners: detection.corners!,
    );
    print(crop.path);
  }
}
```

Filtro pesado no OpenCV nativo:

```dart
await controller.applyFilter(
  '/absolute/input.jpg',
  '/absolute/output.jpg',
  'grayscale',
);
```

Filtros: `original`, `grayscale`, `highContrast`, `colorBoost`.

## Contrato

- cantos TL, TR, BR, BL;
- coordenadas normalizadas em `[0, 1]`;
- rotação e mirror explícitos;
- preview em Texture;
- somente pontos/estado/métricas no EventChannel;
- nenhum frame, bitmap ou `cv::Mat` passa para Dart.

O `ScannerCoordinateMapper` e `DocumentOverlay` tratam contain, cover, rotação e espelhamento. Não multiplique coordenadas diretamente pelo tamanho do widget.

## Android

- minSdk 24, Java 17;
- CameraX 1.6.1;
- OpenCV 4.12.0 via Gradle/Prefab;
- NDK 28.2 e CMake 3.22.1 no build validado.

## iOS

Execute `./tool/bootstrap_ios.sh` antes do primeiro build para obter o `opencv2.xcframework` verificado. O pacote `native/Package.swift` compila o detector C++ e o adaptador Objective-C++ compartilhado.

## Qualidade

```bash
flutter pub get
flutter analyze
flutter test

cd example
flutter run
```

Veja `../BUILD_FLUTTER.md`, `../NATIVE_BRIDGE_SPEC.md`, `../FEATURE_PARITY.md` e `../TEST_CHECKLIST.md`.

## Limites de validação

O código Android foi incluído em APK debug. O núcleo iOS compilou e as fontes Swift passaram no typecheck, mas o build Flutter iOS completo requer instalar um runtime do iOS Simulator. Testes físicos de câmera e stress ainda são necessários.

## Licença

MIT. Dependências mantêm suas próprias licenças.
