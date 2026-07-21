# Plano de migração — estado atual

Última atualização: 21 de julho de 2026.

## Princípios preservados

- UI, navegação e estado compartilhável em Flutter.
- CameraX/AVFoundation, buffers, OpenCV e processamento pesado no nativo.
- Texture para preview; EventChannel somente para pontos/estado/métricas.
- Cantos normalizados em ordem TL, TR, BR, BL.
- Backpressure latest-only e no máximo uma análise ativa.
- Nenhum build de loja ou assinatura de produção.

## Fases

| Fase | Estado | Critério/evidência |
| --- | --- | --- |
| Auditoria e contrato | TESTED | documentos baseline e modelos testados |
| Imagem estática Android | IMPLEMENTED | JNI/OpenCV no APK debug |
| Câmera Android/Texture | IMPLEMENTED | CameraX/C++ compila; hardware pendente |
| Aplicativo local completo | TESTED | biblioteca multipágina, PDF, filtros, prefs e recovery em testes |
| Imagem/câmera iOS | IMPLEMENTED | Objective-C++ compila e Swift typechecks; simulator runtime bloqueia app build |
| Filtros nativos | IMPLEMENTED | `applyFilter` OpenCV compila nas duas plataformas |
| Retirada CardWallet | TESTED | arquivos/configuração removidos e APK recompilado |
| Retirada NativeScript/Svelte/Webpack | TESTED | pipeline antigo removido, Flutter analyze/build aprovados |
| Validação em hardware | BLOCKED | nenhum device/emulador disponível |
| Corpus de regressão | NOT_STARTED | requer acervo/ground truth |
| OCR/sync/organização avançada | NOT_STARTED | recursos do legado ainda sem equivalente Flutter |

## Próxima sequência técnica

1. Instalar um runtime do iOS Simulator e executar o build Flutter completo.
2. Rodar o integration test em Android e iOS com câmera/galeria reais.
3. Medir alinhamento, rotação, mirror, memória e stress de lifecycle.
4. Portar OCR e as demais lacunas registradas em `FEATURE_PARITY.md`, sem reintroduzir o pipeline legado.
5. Criar corpus e aprovar equivalência do detector antes de ajustar parâmetros.

O repositório permanece compilável no Android. A migração do núcleo do scanner está implementada; o plano só pode ser encerrado como paridade integral após as lacunas funcionais e os testes físicos acima.
