# Document Scanner

Aplicativo Flutter para digitalizar, recortar, organizar e compartilhar documentos no Android e iOS. A interface é compartilhada em Flutter, enquanto câmera, detecção de quadriláteros, recorte em perspectiva e filtros usam implementações nativas com OpenCV.

## Origem e créditos

Este projeto é uma reimplementação em Flutter do projeto comunitário e open source [OSS Document Scanner](https://github.com/ossappscollective/OSS-DocumentScanner). A aplicação foi remodelada para oferecer uma base multiplataforma, preservando componentes do projeto original, incluindo partes do pipeline de processamento e detecção de documentos.

O projeto original e os componentes derivados são utilizados conforme os termos da licença MIT. Os créditos à comunidade do OSS Document Scanner e o aviso de copyright original foram preservados.

## Recursos

- Captura automática com detecção e estabilização do documento.
- Captura manual e importação da galeria.
- Documentos com múltiplas páginas, favoritos e lixeira.
- Filtros de imagem, rotação e visualização em tela cheia.
- OCR local com ML Kit no Android e Vision no iOS.
- Pesquisa no texto reconhecido, exportação em PDF e compartilhamento.
- Interface disponível nos 38 idiomas preservados do projeto original.

## Estrutura

- `document_scanner_flutter/`: plugin Flutter e API pública do scanner.
- `document_scanner_flutter/native/`: detector compartilhado em C++/OpenCV.
- `document_scanner_flutter/example/`: aplicativo completo que deve ser executado e distribuído.

## Requisitos

- Flutter 3.44.7 ou compatível e Dart 3.12 ou superior.
- Java 17, Android SDK e NDK para Android.
- macOS com Xcode para compilar ou instalar no iOS.

## Executar o projeto

```bash
git clone https://github.com/otavioDev07/Document-Scanner.git
cd Document-Scanner/document_scanner_flutter
flutter pub get

cd example
flutter pub get
flutter devices
flutter run -d <device-id>
```

No Android, ative **Opções do desenvolvedor > Depuração USB** e autorize o computador. No iOS, prepare primeiro o OpenCV:

```bash
cd document_scanner_flutter
./tool/bootstrap_ios.sh

cd example
open ios/Runner.xcworkspace
```

No Xcode, selecione o target `Runner`, escolha o Apple Developer Team, defina um Bundle Identifier pertencente à equipe e execute no iPhone. Depois da primeira configuração de assinatura, também é possível usar `flutter run`.

## Gerar e instalar o APK debug

```bash
cd document_scanner_flutter/example
flutter build apk --debug
```

O APK será criado em:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Ele pode ser enviado diretamente para o time. No Android, abra o arquivo e autorize a instalação por essa fonte quando solicitado. Com o aparelho conectado por USB, também é possível instalar pelo terminal:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

O APK debug usa uma assinatura de desenvolvimento e serve apenas para testes internos. Uma publicação na Play Store exige uma chave de release e um App Bundle assinado.

## Testes

```bash
cd document_scanner_flutter
flutter analyze
flutter test

cd example
flutter analyze
flutter test
```

## Licença

Distribuído sob a licença MIT descrita em [LICENSE](LICENSE). O aviso de copyright do projeto original permanece preservado nesse arquivo.
