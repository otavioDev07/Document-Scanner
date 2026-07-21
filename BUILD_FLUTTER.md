# Build do plugin Flutter

## Pré-requisitos

- Flutter estável compatível com Dart `>=3.3.0 <4.0.0` (validado com Flutter 3.44.7/Dart 3.12.2);
- Java 17 ou superior, gerando bytecode 17;
- Android SDK API 36;
- Android build-tools 36.0.0;
- NDK 28.2.13676358;
- CMake 3.22.1;
- acesso a Google Maven e Maven Central.

O plugin declara minSdk 24. Não requer OpenCV local: Gradle baixa `org.opencv:opencv:4.12.0`.

## Dependências Dart

```bash
cd document_scanner_flutter
flutter pub get
```

## Qualidade e testes

```bash
dart format --set-exit-if-changed lib test example/lib example/test example/integration_test
flutter analyze
flutter test
```

Teste Kotlin pelo projeto consumidor:

```bash
cd example/android
./gradlew :document_scanner_flutter:testDebugUnitTest
```

## Build Android debug

```bash
cd document_scanner_flutter/example
flutter build apk --debug
```

Saída:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Se o SDK não estiver na localização padrão:

```bash
ANDROID_HOME=/caminho/android-sdk \
ANDROID_SDK_ROOT=/caminho/android-sdk \
flutter build apk --debug
```

## Integration test Android

Com emulador/dispositivo disponível:

```bash
cd document_scanner_flutter/example
flutter test integration_test/plugin_integration_test.dart -d <device-id>
```

O teste copia `assets/test-document.png`, chama a implementação nativa e, se detectar o quadrilátero, valida o arquivo recortado.

## Consumo em outro aplicativo

Durante desenvolvimento:

```yaml
dependencies:
  document_scanner_flutter:
    path: ../OSS-DocumentScanner/document_scanner_flutter
```

Não é necessária configuração CMake no aplicativo consumidor. A dependência Android é transitiva. O consumidor precisa de minSdk 24 ou superior.

## iOS

O package possui registro Swift e capability status, mas detecção/crop iOS ainda não estão implementados. O build iOS não comprova funcionalidade e os métodos retornam `IOS_PHASE_NOT_IMPLEMENTED`.

Na fase 2 serão necessários CocoaPods (ou estratégia SwiftPM equivalente), OpenCV iOS fixado e compilação Objective-C++. Não adicionar permissão de câmera antes da fase de câmera.

## Problemas conhecidos

### `User is using a static STL but library requires a shared STL`

O plugin já passa `-DANDROID_STL=c++_shared`. Não remova: o Prefab OpenCV exige essa STL.

### `2 files found ... libc++_shared.so`

O bloco `packaging.jniLibs.excludes` do plugin elimina sua cópia redundante; OpenCV fornece o runtime transitivamente. Não use `pickFirst` arbitrário no app sem verificar a origem/versão.

### `No Android SDK found`

Defina `ANDROID_HOME` e `ANDROID_SDK_ROOT`, ou configure o SDK pelo Android Studio/Flutter.

### APK debug muito grande

O debug universal carrega múltiplas ABIs e OpenCV monolítico. Avalie tamanho em AAB/release/split por ABI. Uma build OpenCV enxuta é uma decisão posterior com custo de manutenção.

### Build legado continua falhando

Este documento cobre `document_scanner_flutter`. O app NativeScript ainda depende de submódulos e artefatos externos descritos em `BUILD_MIGRATION_ANALYSIS.md`.
