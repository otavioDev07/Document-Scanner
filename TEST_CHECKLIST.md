# Checklist de validação

Última execução: 21 de julho de 2026.

## Automatizado nesta máquina

- [x] plugin `flutter analyze`: sem issues.
- [x] plugin `flutter test`: 15 testes.
- [x] app `flutter analyze`: sem issues.
- [x] app `flutter test`: 4 testes.
- [x] Kotlin `testDebugUnitTest`: 3 testes.
- [x] ordem/validação TL, TR, BR, BL.
- [x] normalização, rotação, mirror, contain e cover.
- [x] overlay/editor e estados visuais.
- [x] controller, erros, eventos inválidos e dispose.
- [x] persistência multipágina, reordenação, rotação, filtro/original e recuperação.
- [x] geração de PDF.
- [x] JNI/C++ e filtros compilados no APK.
- [x] APK debug reconstruído após remoção do legado.
- [x] APK contém plugin/OpenCV/STL nas três ABIs.
- [x] pacote Objective-C++ iOS compilado.
- [x] fontes Swift do plugin typechecked.
- [ ] build Flutter iOS: bloqueado por runtime de simulator ausente.
- [ ] integration test: nenhum device/emulador disponível.

APK: 275 MiB, SHA-256 `e4a6943592ff662dc6a7825a950cd66ba03f16ebd3b635293e39ee58fd0f4abf`.

## Câmera e lifecycle em hardware

- [ ] negar/aceitar permissão e retornar de Settings.
- [ ] preview alinhado em portrait/landscape, contain/cover e split-screen.
- [ ] rotação 0/90/180/270 e câmera frontal/mirror.
- [ ] flash off/auto/on/torch e autofoco.
- [ ] captura manual e auto-captura sem duplicidade.
- [ ] background/foreground, navegação repetida e troca de câmera.
- [ ] 60 minutos de stress sem ANR, crash, buffer ou Texture retidos.
- [ ] FPS/tempo/drops coerentes com diagnósticos ligados e zero overhead relevante desligados.

## Imagem, crop e filtros

- [ ] JPEG com EXIF 90/180/270 e PNG.
- [ ] baixa luz, sombra, reflexo, blur e nenhum documento.
- [ ] fotos 12/24/48 MP com memória monitorada.
- [ ] ajuste de cantos próximo das bordas e quadrilátero inválido.
- [ ] crop/filtros Android e iOS comparados visualmente.
- [ ] 50 ciclos importar/detectar/editar/filtrar/salvar.

## Produto

- [ ] reabrir biblioteca após kill durante metadata/página pendente.
- [ ] documento grande multipágina, reordenação e exclusão.
- [ ] PDF com todas as rotações/filtros.
- [ ] share sheet em Android e iOS, incluindo iPad.
- [ ] limpeza/pressão de armazenamento e mensagens de erro.

## Regressão do detector

- [ ] corpus sem dados pessoais com pelo menos 100 imagens.
- [ ] comparar OpenCV legado 4.8 e atual 4.12 por IoU/falso positivo/falso negativo.
- [ ] comparar dimensões e PSNR/SSIM do crop.
- [ ] aprovar thresholds antes de qualquer mudança de algoritmo.

## Lacunas funcionais

- [ ] OCR/Tesseract.
- [ ] sincronização cloud/WebDAV.
- [ ] pastas, favoritos e lixeira.
- [ ] segurança/backup legado.
- [ ] traduções.
