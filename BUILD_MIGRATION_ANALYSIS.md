# Análise do build legado e do build Flutter

## Estado do build legado

O clone não é autossuficiente para build nativo:

- `tools` e `zxingcpp` estão registrados como submódulos;
- bibliotecas OpenCV/Tesseract são ignoradas no Git;
- `scripts/ci.prepare.sh` baixa um zip opaco de release por plataforma;
- paths e flags variam por flavor;
- plugins NativeScript locais/portal participam da compilação;
- Android requer SDK e caminhos que não estavam configurados neste ambiente.

O download de um zip completo reduz transparência de versão, checksum, licença e reprodução. Também dificulta atualizar uma dependência isolada.

## Build Flutter implementado

O plugin é um package independente em `document_scanner_flutter/`:

- Dart/Flutter para API, estado, overlay e editor;
- Kotlin ActivityAware/MethodChannel para Android;
- CMake/JNI para o detector e perspective crop;
- `org.opencv:opencv:4.12.0` do Maven Central com Prefab;
- `androidx.exifinterface:exifinterface:1.4.1` para orientação;
- sem Tesseract, ZXing, PDF, banco ou código CardWallet no core.

O dry-run de publicação revelou que `document_scanner_flutter` já existe no pub.dev (versão mais recente observada: 0.4.0). Como a propriedade não foi confirmada, o package novo usa `publish_to: none`. Antes de publicação pública, confirmar ownership ou adotar outro nome.

O AAR oficial do OpenCV oferece headers e `.so` via Prefab. A configuração força `c++_shared`, como exigido pelo AAR, e exclui a cópia duplicada do runtime no AAR do plugin; a dependência transitiva OpenCV fornece a cópia final.

## Comparação

| Tema | Legado | Plugin fase 1 |
| --- | --- | --- |
| Framework | NativeScript/Svelte | Flutter/Dart |
| Artefatos OpenCV | zip/pastas externas | Maven Central fixado |
| Ponte | plugin NativeScript + JNI | MethodChannel + JNI |
| Coordenadas | pixels implícitos | normalizadas + metadados |
| Produtos | DS/CardWallet condicionais | scanner isolado |
| OCR/QR/PDF | acoplados ao nativo amplo | fora do core |
| Android | câmera + estático | estático |
| iOS | funcional no legado | auditado/stub no plugin |

## Versões validadas

- Flutter 3.44.7;
- Dart 3.12.2;
- Gradle 9.1.0 no example;
- AGP 9.0.1 no plugin/template;
- Java runtime 21, bytecode alvo 17;
- compileSdk 36, minSdk 24;
- NDK 28.2.13676358;
- CMake 3.22.1;
- OpenCV 4.12.0.

O AAR OpenCV declara build com NDK 27 e STL compartilhada; foi consumido com NDK 28 no APK validado. Fixar NDK no CI reduz variação futura.

## Tamanho e modularidade

O APK debug universal gerado contém arm64-v8a, armeabi-v7a e x86_64 e mede 236 MB. Por ABI, `libopencv_java4.so` representa aproximadamente 15–56 MB. AAB/Play Store separa ABI, mas o custo por dispositivo continua relevante.

Alternativas posteriores:

1. aceitar o AAR oficial pela reprodutibilidade;
2. gerar OpenCV customizado apenas com core/imgproc e publicar AAR interno com checksum/SBOM;
3. distribuir builds por ABI para testes fora da loja;
4. medir o ganho antes de assumir manutenção de toolchain própria.

Não trazer Tesseract/ZXing ao plugin base. Publicá-los como módulos/flags opcionais quando houver API e caso de uso aprovados.

## CI recomendado

Matriz mínima:

- `flutter format --set-exit-if-changed`;
- `flutter analyze`;
- `flutter test`;
- Android JVM test;
- `flutter build apk --debug` e `flutter build appbundle --release`;
- integração em emulador/dispositivo com fixture;
- iOS build/test quando a fase 2 for implementada;
- scan de licenças/SBOM e tamanho por ABI.

Caches devem usar chave por Flutter, Gradle, NDK, CMake, `pubspec.lock` e versão OpenCV. Não cachear outputs entre ABIs/NDKs incompatíveis.

## Riscos de CI existentes

`.github/workflows/test.yml` possui um comando que imprime a representação JSON de todos os secrets. Remover esse passo e rotacionar qualquer segredo possivelmente exposto antes de reativar o workflow. Logs de build nunca devem conter `.env` completo, paths de documentos, bytes ou conteúdo OCR.

## Migração de release

1. publicar o plugin como package versionado/tag interna;
2. manter example app como smoke test;
3. produzir artefatos Flutter em pipeline separado do NativeScript;
4. não reutilizar zip `dev_resources` no plugin;
5. registrar checksums/licenças das dependências nativas;
6. somente desativar pipelines antigos após equivalência e rollout bem-sucedido.
