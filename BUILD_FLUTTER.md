# Build Flutter

Validado em 21 de julho de 2026 com Flutter 3.44.7, Dart 3.12.2, Java 17+, Android API/build-tools 36, NDK 28.2 e CMake 3.22.1. Android minSdk 24.

## Dependências e execução

```bash
cd document_scanner_flutter
flutter pub get

cd example
flutter pub get
flutter run -d <device-id>
```

## Análise e testes

```bash
cd document_scanner_flutter
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test

cd example
flutter analyze
flutter test

cd android
./gradlew :document_scanner_flutter:testDebugUnitTest
```

## Android debug

```bash
cd document_scanner_flutter/example
flutter build apk --debug
```

Saída: `build/app/outputs/flutter-apk/app-debug.apk`.

O plugin baixa OpenCV 4.12.0 e CameraX 1.6.1 por Gradle. O APK debug universal inclui arm64-v8a, armeabi-v7a e x86_64; por isso é grande. Nenhum keystore de produção é necessário.

## iOS debug/simulator

Prepare o OpenCV binário ignorado pelo Git:

```bash
cd document_scanner_flutter
./tool/bootstrap_ios.sh
```

O script verifica SHA-256 antes de extrair `opencv2.xcframework`. Depois:

```bash
cd example
flutter build ios --simulator --debug
```

Validação isolada do núcleo:

```bash
xcrun swift build \
  --package-path document_scanner_flutter/native \
  --triple arm64-apple-ios13.0-simulator \
  --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk
```

Nesta máquina, o núcleo Objective-C++ compila e as fontes Swift passam no typecheck. O build Flutter completo falha porque o Xcode não tem destino/runtime do iOS Simulator instalado. Instale-o em Xcode > Settings > Components e repita o comando.

## Integration test

Com dispositivo ou emulador:

```bash
cd document_scanner_flutter/example
flutter test integration_test/plugin_integration_test.dart -d <device-id>
```

## CI

`.github/workflows/flutter.yml` executa análise/testes/build Android e prepara OpenCV/build iOS em runners oficiais. O pipeline antigo NativeScript/Webpack foi removido.
