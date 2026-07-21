# Auditoria técnica da migração para Flutter

Data da auditoria: 20 de julho de 2026.

## Resumo executivo

O repositório atual é um monorepo NativeScript/Svelte/TypeScript que produz dois aplicativos por seleção de ambiente: Document Scanner e CardWallet. Os dois compartilham a maior parte da infraestrutura, inclusive captura, detecção OpenCV, editor de cantos, recorte em perspectiva, OCR, banco, sincronização e exportação. CardWallet acrescenta modelos e telas de cartões, importação de passes e leitura QR.

A extração segura não é uma conversão integral do aplicativo. O limite correto é um plugin Flutter independente, com API Dart estável e implementações nativas progressivas. A primeira entrega implementada neste repositório cobre imagem estática no Android: seleção de foto, decodificação EXIF, detector legado C++, pontos normalizados, editor Flutter e recorte em perspectiva. A câmera ao vivo e a implementação nativa iOS ficaram explicitamente fora desta fase.

Nenhum arquivo funcional do aplicativo legado foi removido ou substituído. O novo trabalho está isolado em `document_scanner_flutter/`, além destes documentos de migração.

## Arquitetura encontrada

### Aplicação e seleção de produto

- `app.ts` escolhe a raiz de navegação Document Scanner ou CardWallet por constante de compilação.
- `nativescript.config.js` lê `APP_ID`, `APP_RESOURCES` e caminhos de build.
- `app.webpack.config.js` injeta constantes de produto, IDs e opções nativas.
- `.env.ci.documentscanner` configura `com.akylas.documentscanner` e `App_Resources/documentscanner`.
- `.env.ci.cardwallet` configura `com.akylas.cardwallet` e `App_Resources/cardwallet`.
- `App_Resources/documentscanner/` e `App_Resources/cardwallet/` contêm manifestos, temas, ícones e configurações específicas.

Isso é um sistema de flavors criado antes da compilação, não dois projetos independentes. Alterar indiscriminadamente arquivos compartilhados pode quebrar ambos os produtos.

### Tecnologias

- UI: NativeScript 8.9, Svelte e TypeScript.
- Empacotamento: Webpack customizado e plugins NativeScript locais/portal.
- Android: Kotlin/Java, CameraX por `@nativescript-community/ui-cameraview`, JNI, CMake e C++20.
- iOS: Swift/Objective-C++, `AVFoundation`, views NativeScript e CocoaPods.
- Processamento: OpenCV, Tesseract/Leptonica, código C++ próprio e ZXing opcional.
- Persistência e domínio: SQLite, classes TypeScript, serviços de arquivos/sincronização e exportação PDF.
- Release: GitHub Actions, scripts shell e Fastlane separados por produto/plataforma.

## Fluxo Document Scanner legado

### Imagem estática

1. O TypeScript obtém o arquivo e suas dimensões.
2. `getJSONDocumentCornersFromFile` chama o plugin nativo.
3. O detector C++ reduz a imagem, aplica limiar/morfologia/Canny por canal, encontra contornos, aproxima polígonos e escolhe um quadrilátero.
4. Sem detecção, o aplicativo legado cria um quadrilátero de margem como fallback de UX.
5. O modal `ModalImportImages`/`CropView` permite corrigir os cantos.
6. `cropDocumentFromFile` executa transformação de perspectiva e grava um arquivo temporário.

### Câmera Android

- `Camera.svelte` hospeda o CameraView baseado em CameraX.
- `CustomImageAnalysisCallback.kt` recebe `ImageProxy` em YUV, respeita row/pixel strides, chama JNI e fecha o frame com backpressure explícito.
- Os pontos retornam à `CropView` nativa para desenhar o contorno.
- A captura final ainda entra no fluxo estático de detecção, edição e recorte.

### Câmera iOS

- `NSCameraView`/`AVFoundation` entrega `CMSampleBuffer`.
- `OpencvDocumentProcessDelegate.mm` converte o buffer em `cv::Mat`, chama o detector e atualiza `NSCropView`.
- Operações estáticas usam fila global e devolvem completion na main thread.

## Núcleo C++

`cpp/src/DocumentDetector.cpp` e `cpp/src/include/DocumentDetector.h` implementam o detector. O resultado atual:

- contém no máximo um quadrilátero;
- é ordenado como top-left, top-right, bottom-right, bottom-left;
- usa pixels no contrato legado;
- não produz confiança calibrada;
- depende do tamanho/rotação usados no processamento.

O recorte nativo reordena os pontos para a convenção exigida por `getPerspectiveTransform`, calcula dimensões pelas arestas e aplica `warpPerspective`.

Na extração Flutter, o algoritmo de detecção foi copiado. Foram removidos da cópia apenas os métodos de filtros, OCR e serialização JSON que não participam da primeira fase. Parâmetros e sequência de detecção foram preservados. O contrato externo passou para pontos normalizados.

## Separação Document Scanner × CardWallet

### Exclusivo de CardWallet

- `CardsList`, `CardView`, `PKPassView`, criação/edição de cartões e componentes associados.
- modelo/tabela `PKPass` e relacionamento `pkpass_id`;
- importação e MIME/UTI de PKPass/ESPass;
- lógica, paletas e build flag `WITH_QRCODE`/ZXing;
- recursos visuais, metadados de loja, Fastlane e IDs CardWallet.

### Compartilhado ou útil ao scanner

- câmera e adaptação de frames;
- detector de documentos e recorte em perspectiva;
- editor de cantos;
- OCR de documentos, arquivos, banco e sincronização;
- PDF/exportação e infraestrutura de UI;
- `plugin-nativeprocessor` e grande parte do C++.

CardWallet não pode ser apagado por pasta ou por busca textual simples: há condicionais de compilação e modelos compartilhados. A sequência segura está em `CARDWALLET_REMOVAL_ANALYSIS.md`.

## Dependências e build encontrados

- `tools` e `zxingcpp` são submódulos registrados, mas estavam não inicializados nesta cópia.
- binários OpenCV/Tesseract não estão versionados; `.gitignore` os exclui.
- `scripts/ci.prepare.sh` baixa pacotes `dev_resources/<platform>.zip` de um release GitHub.
- o README legado descreve OpenCV 4.8 aproximadamente, mas o diretório Android esperado não está presente.
- os Podfiles de produto diferem principalmente por SSZipArchive e ZXing.
- Android legado usa Java 17/minSdk 24 e CMake; iOS do aplicativo usa deployment target 14.

## Riscos e acoplamentos

1. **Contrato implícito de coordenadas.** Pixel/orientação/espelhamento não formavam um modelo explícito. Isso é a principal fonte de overlays deslocados.
2. **Estado global e callbacks.** Filas, delegates e completion handlers precisam de cancelamento e ownership claros ao migrar.
3. **Memória.** Decodificar bitmaps grandes e manter cópias em Dart/Kotlin/OpenCV pode causar OOM. A fase atual processa fora da main thread, mas ainda decodifica a resolução orientada completa para preservar o crop.
4. **Dependências nativas externas.** O build legado não é reprodutível a partir do clone sem os artefatos baixados.
5. **Mudança OpenCV.** O plugin usa o AAR oficial 4.12.0, enquanto o legado documentava 4.8. A API compila, mas deve haver regressão visual com um corpus antes de equivalência formal.
6. **Tamanho.** O AAR oficial é monolítico. O APK debug universal validado ficou com 236 MB; builds de loja separam ABI, mas uma distribuição enxuta pode exigir OpenCV customizado numa fase posterior.
7. **iOS.** A ponte Objective-C++ foi auditada, mas ainda não foi encapsulada no plugin; o stub retorna erro tipado e não simula suporte.
8. **CI.** `.github/workflows/test.yml` contém um passo que imprime `toJSON(secrets)`. Ele deve ser removido antes de executar esse workflow com segredos, mas não foi alterado por não fazer parte da extração solicitada.
9. **Licenças/proveniência.** O plugin preserva a licença MIT do repositório. Artefatos OpenCV continuam sob suas licenças transitivas e devem constar do inventário de release.
10. **Nome público.** `document_scanner_flutter` já existe no pub.dev. A extração está protegida com `publish_to: none` até confirmar propriedade ou renomear.

## Baseline observado

Antes das alterações:

- `svelte-check` não estava instalado;
- `ns` não estava no PATH;
- Gradle legado baixou sua distribuição, mas parou por ausência de Android SDK;
- não havia Flutter, Dart, Android SDK, CMake, Ninja nem CocoaPods disponíveis no ambiente;
- Java 21, Node 24, Xcode 26.6 e Ruby 2.6 estavam presentes.

Depois da primeira fase, usando ferramentas temporárias:

- Flutter 3.44.7/Dart 3.12.2;
- Android API 36, CMake 3.22.1 e NDK 28.2;
- `flutter analyze`: sem problemas;
- `flutter test`: 13 testes aprovados;
- teste JVM Kotlin: aprovado;
- `flutter build apk --debug`: aprovado.

Isso valida o plugin novo; não transforma as falhas de baseline do aplicativo NativeScript em sucesso.
