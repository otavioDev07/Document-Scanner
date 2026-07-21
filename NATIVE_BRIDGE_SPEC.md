# Especificação Flutter ↔ nativo

Contrato: 0.2.0. Implementações: Android e iOS.

## Transporte

- MethodChannel: `document_scanner_flutter`.
- EventChannel: `document_scanner_flutter/events`.
- Preview: Texture Registry; nunca JPEG/bytes por canal.
- OpenCV, I/O e análise de câmera executam fora da main thread.

## Convenção de cantos

Exatamente quatro objetos `{x, y}` normalizados em `[0, 1]`, relativos à imagem orientada:

1. superior esquerdo;
2. superior direito;
3. inferior direito;
4. inferior esquerdo.

`rotationDegrees` e `mirrored` são sempre explícitos. Flutter aplica `ScannerCoordinateMapper` para rotação, mirror e `BoxFit.contain/cover`.

## Comandos

| Método | Entrada principal | Retorno |
| --- | --- | --- |
| `getNativeStatus`, `initialize` | — | plataforma, versões e capabilities |
| `pickImage` | — | path/mime/displayName ou `null` |
| `detectDocument` | imagePath + options | dimensões, cantos ou `null`, orientação |
| `cropDocument` | imagePath + 4 cantos + options | path/width/height |
| `applyFilter` | imagePath, outputPath, filter, format, quality | path/width/height |
| `startPreview` | options | textureId, width, height, rotação, mirror |
| `stopPreview`, `pausePreview` | — | `null` |
| `resumePreview`, `switchCamera` | — | metadados da Texture |
| `setFlash` | `off`, `auto`, `on` ou `torch` | `null` |
| `setAutoCapture` | enabled | `null` |
| `capture` | — | path da captura e metadados |
| `getDiagnostics` | — | contadores/FPS/tempo/backpressure |
| `dispose` | — | `null` |

### Opções

```json
{
  "detectionResizeThreshold": 1200,
  "areaScaleMinFactor": 0.04,
  "maxOutputDimension": 4096,
  "jpegQuality": 92,
  "autoCapture": false,
  "previewResizeThreshold": 200,
  "previewAreaScaleMinFactor": 0.1,
  "autoCaptureDistanceThreshold": 50,
  "autoCaptureDelayMs": 1000,
  "autoCaptureDurationMs": 1000,
  "autoCaptureCooldownMs": 1500,
  "diagnosticsEnabled": false
}
```

Os defaults de detecção/estabilidade foram preservados do baseline; alterações devem passar pelo corpus de regressão.

### Detecção

```json
{
  "corners": [
    {"x": 0.08, "y": 0.10},
    {"x": 0.91, "y": 0.12},
    {"x": 0.89, "y": 0.90},
    {"x": 0.10, "y": 0.88}
  ],
  "imageWidth": 3024,
  "imageHeight": 4032,
  "rotationDegrees": 0,
  "mirrored": false,
  "source": "legacy_contour_detector",
  "confidence": null
}
```

O detector não possui confiança calibrada; `confidence` permanece `null`.

### Filtros nativos

`applyFilter` aceita `original`, `grayscale`, `highContrast` e `colorBoost`. O app normalmente restaura `original` por cópia byte a byte e chama o OpenCV para os outros três. `outputFormat` é `png` ou `jpeg`; o trabalho pesado não ocorre em Dart.

### Preview

```json
{
  "textureId": 4,
  "width": 1280,
  "height": 720,
  "rotationDegrees": 90,
  "mirrored": false
}
```

Android usa CameraX `STRATEGY_KEEP_ONLY_LATEST`. iOS usa `alwaysDiscardsLateVideoFrames = true`. Há no máximo uma análise ativa; buffers/ImageProxy são liberados em todos os caminhos.

## Eventos

Tipos: `cameraState`, `documentDetected`, `documentLost`, `stabilityChanged`, `autoCaptureProgress`, `captureStarted`, `captureCompleted`, `processingStarted`, `processingCompleted`, `diagnostics`, `error`.

Estados: `searching`, `detected`, `stabilizing`, `stable`, `capturing`, `processing`, `lost`, `error`.

```json
{
  "event": "documentDetected",
  "state": "stabilizing",
  "timestampMicros": 123456,
  "corners": [{"x": 0.08, "y": 0.10}],
  "imageWidth": 720,
  "imageHeight": 1280,
  "rotationDegrees": 0,
  "mirrored": false,
  "stability": 0.72,
  "stableFrames": 6,
  "processingTimeMs": 22.4
}
```

O exemplo abreviado de `corners` acima representa a forma do payload; eventos de detecção reais sempre enviam os quatro pontos.

Diagnósticos contêm `framesReceived`, `framesProcessed`, `framesDropped`, `candidatesFound`, `cameraFps`, `analysisFps`, `averageProcessingTimeMs` e `backpressureStrategy`. No Android, drops internos são estimados por timestamps porque CameraX não expõe callback para frames descartados.

## Ownership e lifecycle

- Dart possui apenas valores, modelos e paths.
- Kotlin/Swift possuem câmera, Texture e buffers.
- C++ possui `cv::Mat` apenas durante a operação.
- Saídas temporárias pertencem ao cache; o app copia páginas permanentes para sua biblioteca.
- `dispose` fecha câmera, analyzer/outputs, stream e Texture; chamadas posteriores são rejeitadas.

## Erros estáveis

`INVALID_ARGUMENT`, `IMAGE_NOT_FOUND`, `IMAGE_DECODE_FAILED`, `NO_ACTIVITY`, `NO_VIEW_CONTROLLER`, `BUSY`, `CAMERA_PERMISSION_DENIED`, `INVALID_STATE`, `NO_DOCUMENT`, `WRITE_FAILED`, `NATIVE_PROCESSING_ERROR`, `INVALID_NATIVE_PAYLOAD`, `ENGINE_DETACHED` e `DISPOSED`.
