# Registro da remoção do produto CardWallet

Executado em 21 de julho de 2026 após migração do núcleo compartilhado e autorização explícita do usuário.

## Preservado antes da exclusão

- detector de documentos e parâmetros C++;
- perspectiva e processamento OpenCV;
- câmera CameraX/AVFoundation e adaptação de buffers;
- assets de ícone do Document Scanner;
- PDF, persistência e compartilhamento, reimplementados no app Flutter.

O código preservado foi centralizado em `document_scanner_flutter/`, especialmente `native/`, `android/`, `ios/` e `example/lib/`.

## Removido

- flavor, IDs, manifests, recursos e metadados CardWallet;
- telas/modelos de cartões, passes e QR;
- variáveis `.env` e scripts de seleção de produto;
- `App_Resources/`, app NativeScript/Svelte e plugins locais;
- Webpack, package manager JavaScript, TypeScript e configurações associadas;
- Fastlane/workflows de publicação e diretórios órfãos.

## Verificação

- busca residual em fonte/configuração executável: nenhuma ocorrência;
- `flutter analyze` plugin e app: aprovado;
- testes Flutter: 15 + 4 aprovados;
- testes JVM: 3 aprovados;
- APK Android debug reconstruído com sucesso;
- pacote nativo iOS compilado e Swift typechecked.

Termos do produto removido permanecem somente neste registro e nos documentos históricos de auditoria, para rastreabilidade da decisão.

## Risco de upgrade

O novo app usa biblioteca de arquivos/JSON e não implementa importação automática do banco SQLite da instalação NativeScript. Portanto, upgrade sobre uma instalação antiga com dados existentes exige uma migração de dados dedicada antes de distribuição aos usuários. Isso não afeta uma instalação limpa nem a recuperação interna da nova biblioteca.

O application ID e o bundle ID do Document Scanner foram preservados como `com.akylas.documentscanner`.
