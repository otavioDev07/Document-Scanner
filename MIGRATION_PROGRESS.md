# Progresso da migração Flutter

Última atualização: 21 de julho de 2026.

## 1. Baseline estático Android

- Criado `document_scanner_flutter/` com plugin e app consumidor em `example/`.
- Portados detector C++/OpenCV, EXIF, picker, editor Flutter e `warpPerspective`.
- Estabelecido contrato de cantos normalizados TL, TR, BR, BL.

## 2. Câmera Android em tempo real

- `CameraSession.kt` integra CameraX Preview, ImageAnalysis e ImageCapture.
- Preview publicado por `TextureRegistry.SurfaceTextureEntry`.
- `STRATEGY_KEEP_ONLY_LATEST`, executor serial e `ImageProxy.close()` em `finally`.
- YUV/row stride/pixel stride seguem direto para JNI/C++; frames não passam por Dart.
- Overlay Flutter, estabilidade nativa, captura manual/automática, flash, troca de câmera, lifecycle e diagnósticos implementados.

## 3. Aplicativo de documentos

- Biblioteca persistente e multipágina em `example/lib/features/documents/`.
- Criar, adicionar, reordenar, excluir, renomear, girar e reabrir documentos.
- Metadados com escrita `pending`/backup e recuperação após reinício.
- PDF multipágina, compartilhamento e configurações persistentes.
- Galeria e câmera usam o mesmo editor de cantos e recorte nativo.

## 4. iOS nativo

- `CameraSession.swift`: AVFoundation, `FlutterTexture`, descarte de frames atrasados, captura, flash e lente.
- `NativeDocumentProcessor.mm`: detecção em imagem/CVPixelBuffer e perspectiva com o detector C++ compartilhado.
- Framework OpenCV reproduzível por `tool/bootstrap_ios.sh`; binário grande permanece ignorado.
- Pacote Swift nativo compilado para `arm64-apple-ios13.0-simulator` e fontes Swift typechecked.
- Build Flutter iOS bloqueado antes da compilação do app: o Xcode não possui runtime/destino de iOS Simulator elegível.

## 5. Processamento pesado

- Detector e `warpPerspective` permanecem C++/OpenCV.
- Filtros `grayscale`, `highContrast` e `colorBoost` foram movidos de Dart para `applyFilter` nativo em Android/iOS.
- O app mantém apenas coordenação de arquivo, backup do original e metadados do filtro.

## 6. Retirada do legado autorizada

Após autorização explícita do usuário, foram removidos:

- flavor, recursos, IDs e telas CardWallet;
- `app/`, `App_Resources/`, plugins NativeScript locais e configuração do CLI;
- Svelte, TypeScript, Webpack, Yarn/NPM e arquivos de ambiente antigos;
- C++ duplicado, ZXing, web PDF viewer, Fastlane e workflows legados;
- assets e diretórios órfãos não usados pelo Flutter.

O detector necessário foi preservado em `document_scanner_flutter/native/`. A busca residual encontra termos antigos apenas em documentos históricos de auditoria, nunca em fonte ou configuração executável.

## 7. Validação atual

- `flutter analyze` plugin: sem issues.
- `flutter test` plugin: 15 aprovados.
- `flutter analyze` app: sem issues.
- `flutter test` app: 4 aprovados.
- Gradle `:document_scanner_flutter:testDebugUnitTest`: 3 aprovados.
- `flutter build apk --debug`: aprovado.
- APK: 275 MiB; SHA-256 `e4a6943592ff662dc6a7825a950cd66ba03f16ebd3b635293e39ee58fd0f4abf`.
- Pacote Objective-C++ iOS: compilado.
- Kotlin/Swift: compilados/typechecked.
- `flutter build ios --simulator --debug --no-pub`: bloqueado por runtime de simulador ausente.

## Pendências reais

- Executar câmera, overlay, flash, troca de lente, auto-captura e share sheet em Android/iOS reais.
- Executar integration tests instrumentados e stress de lifecycle/memória.
- Comparar o detector OpenCV 4.12 com o legado 4.8 num corpus.
- Portar OCR, sincronização, pastas/favoritos/lixeira, segurança/backup e traduções, ou aprovar explicitamente a retirada dessas funcionalidades.
