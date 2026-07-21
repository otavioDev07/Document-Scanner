# Checklist de testes

## Resultado automatizado desta entrega

- [x] `flutter analyze` — sem issues.
- [x] `flutter test` — 13 testes aprovados.
- [x] modelos e parsing de payload.
- [x] ordenação/validação TL, TR, BR, BL.
- [x] round-trip de coordenadas em 0/90/180/270.
- [x] mirror e BoxFit contain/cover.
- [x] arraste de handle no overlay.
- [x] estado, dispose e erros do controller.
- [x] MethodChannel com documento ausente, payload inválido e erro nativo.
- [x] teste JVM Kotlin de capabilities.
- [x] `flutter build apk --debug`.
- [x] inspeção do APK: plugin/OpenCV/STL presentes em arm64-v8a, armeabi-v7a e x86_64.
- [ ] integration test em dispositivo/emulador — não havia device no ambiente.
- [ ] teste funcional iOS — fase não implementada.

## Matriz manual Android — imagem estática

- [ ] JPEG portrait com EXIF 90.
- [ ] JPEG landscape com EXIF 180/270.
- [ ] PNG sem EXIF.
- [ ] documento claro em fundo escuro.
- [ ] documento escuro em fundo claro.
- [ ] baixa luz, sombra, reflexo e blur.
- [ ] documento parcialmente fora da imagem.
- [ ] nenhuma forma quadrilateral: resposta sem documento, sem crash.
- [ ] foto 12 MP, 24 MP e 48 MP com monitoramento de memória.
- [ ] picker cancelado e Activity recriada durante picker.
- [ ] arquivo removido entre seleção e detecção.
- [ ] 50 ciclos selecionar → detectar → editar → crop.
- [ ] crop com cantos próximos mas convexos.
- [ ] cantos inválidos/autointersectados rejeitados no Dart.
- [ ] app em background/foreground durante processamento.

## Alinhamento visual

Para cada caso, testar `BoxFit.contain` e `BoxFit.cover`:

- [ ] 0°, sem mirror;
- [ ] 90°, sem mirror;
- [ ] 180°, sem mirror;
- [ ] 270°, sem mirror;
- [ ] todos os anteriores com mirror;
- [ ] viewport portrait, landscape, square e split-screen;
- [ ] handle preso à borda correta após resize/rotação da tela.

Tolerância recomendada: erro de overlay menor que 2 px em fixture sintética e menor que 0,5% da menor dimensão em fotos reais.

## Regressão legado × Flutter

Criar corpus versionado sem dados pessoais, com pelo menos 100 imagens e ground truth manual.

- [ ] executar detector legado e plugin com opções equivalentes;
- [ ] comparar IoU dos quadriláteros;
- [ ] registrar falso positivo/falso negativo;
- [ ] comparar dimensões e PSNR/SSIM do crop;
- [ ] separar mudança de OpenCV 4.8 → 4.12 de mudança de bridge;
- [ ] aprovar thresholds antes de alterar algoritmo.

## Performance e memória

- [ ] tempo p50/p95 de decode, detect, crop e encode por classe de device;
- [ ] pico de RSS/heap Java/native;
- [ ] ausência de bitmap/Mat retido após 50 operações;
- [ ] nenhuma operação pesada na main thread;
- [ ] cancelamento/detach não entrega resultado duas vezes;
- [ ] arquivo temporário e política de limpeza documentados.

## Futura câmera

- [ ] permissões negada, temporária e permanentemente;
- [ ] CameraX/AVFoundation abre/fecha sem vazamento;
- [ ] backpressure keep-only-latest;
- [ ] frame sempre fechado/liberado em erro;
- [ ] Texture liberada no dispose;
- [ ] rotação durante preview;
- [ ] flash off/auto/on/torch;
- [ ] alternância câmera frontal/traseira e mirror;
- [ ] auto-capture: estabilidade, cooldown, cancelamento e apenas uma captura;
- [ ] 60 minutos de stress sem ANR/crash.

## Release

- [ ] AAB release e split por ABI.
- [ ] tamanho por ABI registrado.
- [ ] símbolos nativos preservados/upload para crash reporting.
- [ ] SBOM e notices OpenCV/Flutter.
- [ ] workflow não imprime secrets.
- [ ] install novo e upgrade do consumidor.
