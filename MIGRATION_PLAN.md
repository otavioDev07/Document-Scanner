# Plano incremental de migração

## Princípios

- Manter o aplicativo legado operacional durante toda a extração.
- Migrar um fluxo vertical verificável por vez.
- Estabilizar o contrato Dart antes de trocar implementações internas.
- Nunca compartilhar `cv::Mat`, ponteiros de frame ou objetos de câmera com Dart.
- Representar cantos fora do nativo como coordenadas normalizadas em ordem TL, TR, BR, BL.
- Não declarar suporte antes de haver build e teste naquela plataforma.

## Fase 0 — auditoria e contratos

Status: concluída.

Entregas:

- inventário NativeScript/Svelte/Android/iOS/C++;
- separação Document Scanner/CardWallet;
- especificação do bridge;
- estratégia de build e teste;
- plugin e example app isolados.

Critério: nenhuma remoção do legado e documentação dos riscos de build, coordenadas, memória e CI.

## Fase 1 — imagem estática Android

Status: implementada e compilada.

Escopo:

- `getNativeStatus` e `initialize` via MethodChannel;
- seletor de imagem Android com cópia para cache e path real;
- orientação EXIF aplicada antes da detecção;
- detector legado C++ compilado no plugin;
- pontos normalizados e metadados explícitos;
- overlay/editor de cantos Flutter;
- recorte em perspectiva nativo e arquivo JPEG de saída;
- controller com estados e dispose idempotente;
- testes Dart/widget/JVM e example app.

Critério de saída atingido: análise limpa, 13 testes Dart aprovados, teste Kotlin aprovado e APK debug gerado.

Pendências antes de chamar a fase de equivalência:

- executar `integration_test` num dispositivo/emulador Android;
- comparar detector/crop legado e Flutter num corpus representativo;
- medir memória com fotos de 12–48 MP;
- decidir política de downsampling e preservação de resolução;
- avaliar OpenCV customizado para reduzir binário.

## Fase 2 — imagem estática iOS

Status: planejada; o stub atual reporta `IOS_PHASE_NOT_IMPLEMENTED`.

Ordem proposta:

1. empacotar o C++ compartilhado como fonte/pod interno do plugin;
2. escolher OpenCV iOS reproduzível e fixado;
3. portar decodificação/orientação de `UIImage` sem alterar a convenção normalizada;
4. encapsular detecção/crop do `OpencvDocumentProcessDelegate.mm` em serviço sem dependência NativeScript;
5. devolver callbacks sempre na main queue e cancelar trabalho no detach;
6. criar testes Swift/Objective-C++ e integration test em simulator/device.

Critério: mesmo fixture/corners/crop dentro das tolerâncias definidas para Android, sem vazamentos no Instruments.

## Fase 3 — câmera Android com Texture

Status: planejada; não implementada nesta entrega.

Arquitetura:

- CameraX pertence integralmente ao Android;
- o preview é publicado como Flutter `Texture`, não como plataforma view;
- `ImageAnalysis` usa estratégia keep-only-latest;
- somente pontos normalizados/estado atravessam EventChannel ou stream controlado;
- overlay permanece Flutter;
- captura de alta resolução entra novamente no pipeline estático;
- flash, rotação e lifecycle são comandos do controller.

Critérios:

- 30/60 minutos de abre-fecha/rotação sem travar;
- backpressure comprovado e `ImageProxy.close()` em todos os caminhos;
- no máximo um processamento concorrente;
- overlay alinhado em 0/90/180/270, front/back e contain/cover;
- auto-capture com estabilidade, cooldown e cancelamento.

## Fase 4 — câmera iOS com Texture

Status: planejada.

- `AVCaptureSession` e buffers ficam no iOS;
- `FlutterTexture` publica pixel buffers;
- processamento ocorre em serial queue dedicada;
- orientação e mirror são metadados explícitos;
- captura final usa foto de alta resolução e pipeline estático.

## Fase 5 — recursos opcionais

Itens independentes, cada um atrás de capability:

- filtros de aprimoramento;
- OCR/Tesseract;
- QR/ZXing somente se necessário;
- multipágina/PDF;
- auto-capture configurável;
- telemetria de performance sem conteúdo de imagem.

Não adicionar Tesseract, ZXing ou PDF ao core antes de modularizar dependências: isso recriaria o acoplamento e o tamanho do legado.

## Fase 6 — adoção e retirada do legado

1. integrar plugin num consumidor Flutter real;
2. executar piloto lado a lado com o aplicativo atual;
3. congelar corpus e thresholds de regressão;
4. migrar funcionalidades de domínio apenas se o produto Flutter precisar delas;
5. remover CardWallet seguindo checklist dedicado;
6. só então apagar bridges NativeScript substituídos e artefatos antigos.

Rollback de cada fase: manter o app legado e o plugin versionados separadamente; uma falha no plugin não exige reverter o produto publicado.
