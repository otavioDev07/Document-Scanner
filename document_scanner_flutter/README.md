# document_scanner_flutter

Plugin Flutter reutilizável extraído do pipeline nativo do OSS DocumentScanner. A versão 0.1.0 entrega o fluxo vertical de imagem estática no Android: seleção, orientação EXIF, detecção de documento com OpenCV/C++, edição de quatro cantos em Flutter e recorte em perspectiva.

## Estado por plataforma

| Recurso | Android | iOS |
| --- | --- | --- |
| status/initialize | sim | sim, capability-only |
| selecionar imagem | sim | não |
| detectar documento estático | sim | não |
| overlay/editor Flutter | sim | sim |
| perspective crop | sim | não |
| câmera ao vivo/Texture | planejado | planejado |
| flash/auto-capture | planejado | planejado |

O iOS retorna `IOS_PHASE_NOT_IMPLEMENTED` para seleção/detecção/crop. Os métodos de câmera retornam `CAMERA_PHASE_NOT_IMPLEMENTED`. Isso é intencional: a versão não simula recursos ainda não portados.

## Requisitos

- Flutter 3.19 ou superior;
- Dart 3.3 ou superior;
- Android minSdk 24;
- Android compileSdk 36 no build validado;
- Java bytecode 17;
- CMake 3.22.1/NDK instaláveis pelo Android Gradle Plugin.

OpenCV não precisa ser instalado manualmente. O Android consome o [AAR oficial `org.opencv:opencv:4.12.0`](https://repo1.maven.org/maven2/org/opencv/opencv/4.12.0/) com Prefab.

## Instalação local

Esta fase está marcada com `publish_to: none`: o nome já existe no pub.dev e a propriedade não foi confirmada. Para publicação pública, confirme a conta proprietária ou renomeie o package antes de retirar essa proteção.

```yaml
dependencies:
  document_scanner_flutter:
    path: ../OSS-DocumentScanner/document_scanner_flutter
```

Depois:

```bash
flutter pub get
```

## Uso completo da fase estática

```dart
import 'package:document_scanner_flutter/document_scanner_flutter.dart';

final controller = DocumentScannerController(
  options: const ScannerOptions(
    detectionResizeThreshold: 1200,
    areaScaleMinFactor: 0.04,
    maxOutputDimension: 4096,
    jpegQuality: 92,
  ),
);

final status = await controller.initialize();
if (!status.staticImageSupported) {
  throw StateError('Static scanning is unavailable on this platform');
}

final picked = await controller.pickImage();
if (picked == null) return; // picker cancelado

final detection = await controller.detectDocument(picked.path);
if (!detection.documentFound) {
  // Mostre uma mensagem ou ofereça cantos manuais; não há confiança inventada.
  return;
}

final crop = await controller.cropDocument(
  picked.path,
  corners: detection.corners!,
);

print('${crop.path} — ${crop.width}×${crop.height}');
await controller.close();
```

Em um `State`, `controller.dispose()` também é válido e dispara a liberação nativa sem bloquear.

## Editor de cantos

```dart
List<ScannerPoint> edited = detection.corners!;

CropEditor(
  imagePath: picked.path,
  imageSize: Size(
    detection.imageWidth.toDouble(),
    detection.imageHeight.toDouble(),
  ),
  initialCorners: edited,
  onCornersChanged: (value) => edited = value,
)
```

`DocumentOverlay` pode ser usado separadamente sobre qualquer preview. `DocumentScannerPreview` é uma superfície de composição Flutter; nesta versão, o `child` é fornecido pelo consumidor. Ele ainda não cria uma câmera nativa.

## Contrato de coordenadas

- exatamente quatro pontos;
- ordem top-left, top-right, bottom-right, bottom-left;
- `x` e `y` normalizados em `[0, 1]`;
- dimensões, rotação e mirror via `DetectionResult`;
- `ScannerCoordinateMapper` suporta `BoxFit.contain`, `BoxFit.cover`, 0/90/180/270 e mirror.

Não converta diretamente `x * larguraDoWidget` quando a imagem usa contain/cover: letterbox ou crop mudam a transformação. Use o mapper/overlay fornecido.

## API principal

- `DocumentScannerController`
- `DocumentScannerPreview`
- `DocumentOverlay`
- `CropEditor`
- `ScannerOptions`
- `ScannerPoint` / `ScannerCorners`
- `DetectionResult`
- `CaptureResult`
- `CropResult`
- `ScannerCameraState` / `ScannerFlashMode`
- `NativeStatus`
- `ScannerException`

## Erros

Falhas nativas são convertidas em `ScannerException` com código estável. Códigos comuns: `FILE_NOT_FOUND`, `INVALID_ARGUMENT`, `NO_ACTIVITY`, `BUSY`, `NATIVE_PROCESSING_ERROR`, `NO_DOCUMENT`, `DISPOSED` e os códigos explícitos de fase não implementada.

## Arquitetura Android

```text
Dart Controller/UI
        │ MethodChannel (modelos/paths)
        ▼
Kotlin plugin ── picker, EXIF, worker serial, arquivos
        │ JNI (Bitmap + números)
        ▼
C++ detector legado + OpenCV Prefab
```

Frames e `cv::Mat` nunca atravessam para Dart. A futura câmera manterá CameraX/AVFoundation nativos e publicará preview como Texture; somente pontos/metadados irão para Flutter.

## Exemplo e validação

```bash
flutter analyze
flutter test
cd example
flutter build apk --debug
```

O example permite escolher uma foto, ajustar cantos e exibir o crop. Há integration test com fixture em `example/integration_test/plugin_integration_test.dart`; execute-o com device/emulador.

## Limitações conhecidas

- imagem estática Android é o único fluxo nativo completo;
- decodificação atual usa a imagem orientada completa; fotos extremamente grandes precisam de profiling;
- o detector preservado devolve um quadrilátero e não possui confiança calibrada;
- OpenCV 4.12 substitui o artefato 4.8 descrito pelo legado, exigindo corpus de regressão;
- o AAR OpenCV oficial é monolítico e aumenta o tamanho do binário;
- arquivos ficam no cache do app; persista/copie os resultados necessários.

Veja `../MIGRATION_PLAN.md`, `../NATIVE_BRIDGE_SPEC.md`, `../BUILD_FLUTTER.md` e `../TEST_CHECKLIST.md` para o plano completo.

## Licença

MIT, preservando a licença do OSS DocumentScanner. Dependências transitivas mantêm suas respectivas licenças.
