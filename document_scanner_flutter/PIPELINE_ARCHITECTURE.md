# Cascata de detecção no frame (Android)

## Fluxo executado

`CameraX ImageAnalysis` mantém `STRATEGY_KEEP_ONLY_LATEST` e usa uma única thread de
análise. Cada frame segue esta ordem:

1. `NativeDocumentProcessor.nativeDetectYuv`: RDP + Hough probabilístico em C++.
2. Cálculo do score normalizado `área relativa × (1 - maior cosseno)`.
3. `PythonCascadeProcessor`: compacta os três planos `YUV_420_888` em NV21 e
   envia o frame colorido e o candidato C++ ao módulo Chaquopy persistente.
4. `coupon_pipeline.py`:
   - early exit C++ quando `score >= 0.30`;
   - Hough Python e early exit quando `score >= 0.28`;
   - Watershed, rejeitando área `>= 90%`;
   - consenso por IoU `>= 0.80` ou fallback estrito `>= 0.22`;
   - ordenação dos quatro pontos, warp perspective e FFT somente sobre o warp;
   - aprovação final somente com `FFT > 0.222`.
5. Apenas os pontos aprovados chegam ao `StabilityTracker`, ao overlay e à
   captura automática.

Não há subprocesso Bash, inicialização de Python por frame, JSON temporário ou
JPEG temporário durante o preview. O JSON existe apenas como contrato em memória
na ponte Kotlin/Python.

## Destino da imagem

- `INTERNO`: o `CropResult` volta para a biblioteca local existente.
- `NUVEM`: o arquivo é copiado para uma fila privada e um `CloudUploadWorker` é
  agendado com restrição de rede, backoff exponencial e chave de idempotência. O
  POST usa `multipart/form-data` com o campo `file`.

O destino precisa ser um endpoint HTTP(S) que aceite multipart. Um ID ou link de
pasta do Google Drive, sozinho, não autoriza uploads: ele deve ser usado por um
webhook/backend autenticado (por exemplo, Apps Script) ou a aplicação precisa de
um fluxo OAuth do Google, que requer client ID, escopos e política de conta.

## Perfil de tamanho

O runtime Python é propositalmente parte deste build de validação. O APK release
deve ser gerado para arm64:

```sh
flutter build apk --release --target-platform android-arm64
```

Na medição de 2026-09-02, o APK resultante ficou em 94,7 MB (94.745.884 bytes),
contra 255,8 MB no APK universal com arm64 + x86_64. Para produção, publique AAB
ou mantenha um flavor separado sem Chaquopy depois de portar e validar os motores
Python em C++.
