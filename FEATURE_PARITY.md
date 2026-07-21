# Paridade funcional

Última atualização: 21 de julho de 2026.

Estados: `NOT_STARTED`, `IN_PROGRESS`, `IMPLEMENTED`, `TESTED`, `BLOCKED`, `NOT_APPLICABLE`.

`TESTED` significa que houve teste automatizado ou build verificável nesta máquina. Recursos dependentes de câmera/share sheet continuam com validação física explicitamente pendente.

| Funcionalidade | Implementação antiga | Implementação Flutter | Nativo | Status | Evidência |
| --- | --- | --- | --- | --- | --- |
| Inicialização e lifecycle | bootstrap NativeScript | `DocumentScannerController` | MethodChannel | TESTED | testes Flutter de estado, erro e dispose |
| Tela inicial/biblioteca | Svelte `DocumentsList` | `DocumentLibraryPage` | não | TESTED | widget test |
| Importação da galeria | dialogs NativeScript | `pickImage` | Android/iOS picker | IMPLEMENTED | Android APK + Swift typecheck; device pendente |
| Preview Android | CameraView/CameraX | `Texture` + `DocumentScannerPreview` | CameraX | IMPLEMENTED | APK debug; hardware pendente |
| Preview iOS | AVFoundation/NSCameraView | `FlutterTexture` | AVFoundation | IMPLEMENTED | pacote nativo compila + Swift typecheck; runtime de simulador ausente |
| Detecção estática | plugin nativo + C++ | controller/API Flutter | OpenCV/C++ | IMPLEMENTED | Android APK e pacote iOS compilam |
| Detecção contínua | callbacks de frame nativos | evento normalizado por frame aceito | CameraX/AVFoundation/C++ | IMPLEMENTED | latest-only e liberação inspecionados/compilados; hardware pendente |
| Overlay ao vivo | CropView nativa | `CustomPainter` Flutter | não | TESTED | geometry/widget em contain, cover, rotação e mirror |
| Estabilidade/auto-scan | `AutoScanHandler` | trackers Kotlin/Swift | plataforma | TESTED | testes JVM; captura real pendente |
| Captura manual/automática | CameraView | controller + eventos | ImageCapture/AVCapturePhotoOutput | IMPLEMENTED | Android/iOS compilam; hardware pendente |
| Flash/câmera/foco | CameraView | comandos Flutter | CameraX/AVFoundation, autofoco contínuo | IMPLEMENTED | build; matriz física pendente |
| Editor de cantos | CropView | `CropEditor`/`DocumentOverlay` | não | TESTED | drag, limites e quadrilátero válido |
| Recorte em perspectiva | `warpPerspective` legado | `cropDocument` | OpenCV/C++ | IMPLEMENTED | JNI e Objective-C++ compilam |
| Fallback sem detecção | margem padrão | quadrilátero de margem 5% | não | TESTED | fluxo do app/testes de geometria |
| Múltiplas páginas | banco/telas Svelte | modelo e biblioteca persistente | arquivos | TESTED | teste de reabertura multipágina |
| Ordenação/exclusão | banco/gestos Svelte | controller + UI Flutter | arquivos | TESTED | repository test |
| Renomear/salvar/reabrir | SQLite/serviços | JSON atômico por documento | arquivos | TESTED | persistência e recuperação de backup |
| Rotação | native processor/UI | metadado por página | não | TESTED | repository test e render/export |
| Filtros | native processor | `applyFilter` MethodChannel | OpenCV Android/iOS | IMPLEMENTED | C++/Kotlin/Swift compilam; restauração original testada |
| Miniaturas | imagens/serviços | `FileImage` com cache eviction | não | IMPLEMENTED | análise/widget; profiling pendente |
| PDF | serviço PDF legado | `PdfExportService` | não | TESTED | PDF multipágina válido em teste |
| Compartilhamento | módulos NativeScript | `share_plus` | share sheet | IMPLEMENTED | análise/build; interação física pendente |
| Configurações | ApplicationSettings | `ScannerSettingsController` | prefs | TESTED | persistência + UI no app tests |
| Permissões/erros | plugins NativeScript | erros tipados e fluxos Android/iOS | plataforma | IMPLEMENTED | contratos/build; negação em device pendente |
| Recuperação após reinício | banco/backup | metadata/backup/pending atômicos | arquivos | TESTED | testes de backup e corrupção |
| Temporários | cache legado | cache nativo + cópia atômica para biblioteca | arquivos | IMPLEMENTED | paths/ownership documentados; stress pendente |
| Diagnósticos | logs ad hoc | `ScannerDiagnostics` opcional | plataforma | TESTED | parsing + build |
| OCR | Tesseract | não portado | Tesseract ausente | NOT_STARTED | funcionalidade legada fora do app atual |
| Sincronização cloud/WebDAV | serviços TypeScript | não portado | credenciais/provedores | NOT_STARTED | funcionalidade legada fora do app atual |
| Pastas/favoritos/lixeira | modelos/telas Svelte | não portado | não | NOT_STARTED | funcionalidade legada fora do app atual |
| Bloqueio por senha/backup legado | telas/serviços Svelte | não portado | plataforma | NOT_STARTED | funcionalidade legada fora do app atual |
| Traduções legadas | JSON/i18n | UI atual em português | não | NOT_STARTED | catálogo multilíngue não migrado |
| CardWallet | flavor/telas/PKPass/QR | removido | — | TESTED | busca residual sem código/configuração + APK |
| NativeScript/Svelte/Webpack | app e pipeline antigos | substituídos por Flutter | — | TESTED | dependências/arquivos removidos + análise/build |

## Leitura correta do estado

O núcleo pedido para digitalização e gestão local está implementado. A migração não deve ser chamada de paridade integral do produto legado enquanto OCR, sincronização, organização avançada, segurança e traduções não forem portados ou formalmente retirados do escopo. A validação de câmera em hardware também permanece obrigatória.
