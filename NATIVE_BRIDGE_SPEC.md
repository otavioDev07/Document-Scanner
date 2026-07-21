# Especificação do bridge Flutter ↔ nativo

Versão do contrato: 0.1.0.

## Transporte

- MethodChannel: `document_scanner_flutter`.
- Métodos atuais: `getNativeStatus`, `initialize`, `pickImage`, `detectDocument`, `cropDocument`, `dispose`.
- Métodos de câmera permanecem apenas na API do controller e retornam `CAMERA_PHASE_NOT_IMPLEMENTED` nesta fase.
- Trabalho OpenCV e I/O nunca é executado na main thread Android.
- Resultados do MethodChannel são entregues na main thread.

## Convenções

### Cantos

Lista com exatamente quatro objetos, nesta ordem:

1. top-left;
2. top-right;
3. bottom-right;
4. bottom-left.

Cada objeto possui `x` e `y` `double` no intervalo fechado `[0, 1]`, relativos à imagem orientada indicada por `imageWidth`/`imageHeight`.

O Android atual aplica EXIF ao bitmap antes de detectar. Por isso retorna `rotationDegrees: 0` e `mirrored: false`. O contrato mantém esses campos para câmera/iOS e não permite inferi-los do tamanho.

### Ownership

- Dart possui somente strings de path, números e modelos imutáveis.
- Kotlin possui e recicla `Bitmap` dentro de cada operação.
- C++ cria e libera seus `cv::Mat` dentro da chamada JNI.
- Nenhum ponteiro ou bitmap atravessa chamadas assíncronas.
- Arquivos selecionados/cortados pertencem ao cache do app consumidor; o consumidor deve persistir o que desejar manter.

## Métodos

### `getNativeStatus()` e `initialize()`

Sem argumentos. Retorno:

```json
{
  "platform": "android",
  "pluginVersion": "0.1.0",
  "opencvVersion": "4.12.0",
  "detectorAvailable": true,
  "staticImageSupported": true,
  "cameraPreviewSupported": false
}
```

`initialize` é idempotente. Na fase atual não abre câmera nem cria recursos long-lived.

### `pickImage()`

Requer Activity Android. Abre `ACTION_OPEN_DOCUMENT`, copia o conteúdo para cache e devolve `null` no cancelamento ou:

```json
{
  "path": "/absolute/cache/path.jpg",
  "mimeType": "image/jpeg",
  "displayName": "document.jpg"
}
```

Somente uma solicitação pode estar ativa; a segunda recebe `BUSY`.

### `detectDocument`

Entrada:

```json
{
  "imagePath": "/absolute/path.jpg",
  "options": {
    "detectionResizeThreshold": 1200,
    "areaScaleMinFactor": 0.04,
    "maxOutputDimension": 4096,
    "jpegQuality": 92
  }
}
```

Retorno com documento:

```json
{
  "corners": [
    {"x": 0.1, "y": 0.1},
    {"x": 0.9, "y": 0.1},
    {"x": 0.9, "y": 0.9},
    {"x": 0.1, "y": 0.9}
  ],
  "imageWidth": 3024,
  "imageHeight": 4032,
  "rotationDegrees": 0,
  "mirrored": false,
  "source": "legacy_contour_detector",
  "confidence": null
}
```

Sem documento, `corners` e `confidence` são `null`. Não inventar confiança: o algoritmo legado não a calibra.

### `cropDocument`

Entrada: `imagePath`, `corners` normalizados e `options`. O nativo valida a quantidade/range, calcula o tamanho pelas maiores arestas, limita a maior dimensão e executa `warpPerspective`.

Retorno:

```json
{
  "path": "/absolute/cache/crop_123.jpg",
  "width": 1800,
  "height": 2500
}
```

### `dispose()`

Idempotente. O controller rejeita operações posteriores com `DISPOSED`. Na futura fase câmera, deve cancelar streams/analyzers, devolver Texture e encerrar sessão nativa antes de completar.

## Erros

| Código | Situação |
| --- | --- |
| `INVALID_ARGUMENT` | path/cantos/opções inválidos |
| `FILE_NOT_FOUND` | arquivo ausente ou inacessível |
| `NO_ACTIVITY` | picker sem Activity ou Activity destacada |
| `BUSY` | picker já ativo |
| `ENGINE_DETACHED` | operação cancelada pelo detach da engine |
| `NATIVE_PROCESSING_ERROR` | exceção OpenCV/JNI/encode |
| `INVALID_NATIVE_PAYLOAD` | resposta nativa não atende ao modelo Dart |
| `NO_DOCUMENT` | tentativa de crop sem cantos |
| `INVALID_STATE` | operação fora do estado do controller |
| `DISPOSED` | uso após dispose |
| `CAMERA_PHASE_NOT_IMPLEMENTED` | comando de câmera nesta fase |
| `IOS_PHASE_NOT_IMPLEMENTED` | fluxo estático ainda não portado para iOS |

Mensagens ajudam diagnóstico, mas código é o contrato estável. Não incluir path sensível ou bytes de imagem em logs de produção.

## Estado e concorrência

Estados Dart: `uninitialized → initializing → ready ↔ processing → disposed`.

O Android usa executor serial de um worker. Isso impede duas operações OpenCV simultâneas no mesmo plugin. A API atual não promete paralelismo; consumidores devem aguardar cada Future. Detach da engine remove o handler e encerra o executor.

## Extensão prevista para câmera

Preview deve usar `Texture`:

- `createCamera` retorna `textureId` e tamanho/orientação;
- frames continuam nativos;
- um stream de baixa frequência entrega apenas cantos/estado/timestamps;
- `capture` devolve path de foto e passa ao mesmo `detectDocument`/`cropDocument`;
- `disposeCamera` libera CameraX/AVFoundation e a texture.

Uma `PlatformView` só deve ser considerada se houver requisito nativo que Texture não cubra; ela aumenta complexidade de composição, gestos e lifecycle.
