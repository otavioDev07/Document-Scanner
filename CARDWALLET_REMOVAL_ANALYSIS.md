# Análise para remoção futura do CardWallet

## Decisão

CardWallet não foi removido nesta entrega. A análise mostra que uma exclusão imediata por diretório seria insegura porque o produto é selecionado por ambiente e compartilha módulos com Document Scanner.

## Inventário exclusivo de CardWallet

Revalidar nomes com `rg` antes de apagar, pois a árvore pode evoluir.

### UI e navegação

- raiz/lista de cartões (`CardsList`);
- visualização e edição (`CardView`, `PKPassView`, criação de cartão);
- componentes específicos de campos, código de barras/QR, paletas e passes;
- branch CardWallet em `app.ts` e constantes condicionais do Webpack.

### Domínio e persistência

- classe/modelo `PKPass`;
- tabela/migrações `PKPass`;
- campos/relacionamentos `pkpass_id`;
- importadores PKPass/ESPass e parsing específico;
- tipos MIME, UTI e intent filters de passes.

### Nativo

- flag `WITH_QRCODE`;
- integração ZXing e submódulo `zxingcpp`, se nenhuma outra feature usar QR;
- métodos QR no `plugin-nativeprocessor`;
- variantes/AARs com sufixo de CardWallet.

### Produto e distribuição

- `.env.ci.cardwallet`;
- `App_Resources/cardwallet/`;
- fastlane, screenshots, ícones, gráficos e metadata CardWallet;
- workflows/matrizes de publicação do flavor CardWallet;
- IDs `com.akylas.cardwallet` e App Store ID correspondente;
- documentação/site e traduções exclusivamente CardWallet.

## O que deve permanecer

- câmera, detector OpenCV, recorte e editor de cantos;
- OCR de documentos e Tesseract enquanto usados pelo scanner;
- banco/armazenamento de documentos;
- sincronização, arquivos, PDF e exportação usados pelo Document Scanner;
- componentes visuais compartilhados;
- scripts de build genéricos;
- `plugin-nativeprocessor` até todas as chamadas do scanner serem substituídas.

## Dependências transitivas a confirmar

Antes de cada remoção:

```bash
rg -n "CardWallet|PKPass|ESPass|WITH_QRCODE|ZXing|pkpass_id" \
  app plugin-nativeprocessor App_Resources scripts .github fastlane docs-site
```

Também verificar imports dinâmicos, tabelas criadas por string, MIME/UTI e nomes interpolados pelo Webpack.

## Ordem segura

1. Criar branch isolada depois que o plugin Flutter substituir o fluxo necessário.
2. Remover a entrada CardWallet das matrizes CI/release para impedir publicação acidental.
3. Remover `app.ts`/Webpack flavor branch e variáveis CardWallet.
4. Remover telas/componentes exclusivos e corrigir imports.
5. Criar migração de banco explícita; nunca apenas apagar a classe `PKPass`.
6. Remover MIME/UTI/intent filters e recursos CardWallet.
7. Remover QR/ZXing somente se uma busca e testes confirmarem zero uso pelo scanner.
8. Remover assets, Fastlane e documentação do produto.
9. Rodar build/test Android e iOS Document Scanner em clone limpo.
10. Validar upgrade sobre um banco real que já contenha dados CardWallet/Document Scanner.

## Checklist de aceitação

- [ ] Document Scanner inicia sem qualquer variável CardWallet.
- [ ] Importação, câmera, detecção, crop, OCR, PDF, sync e banco continuam funcionais.
- [ ] Não há referência a `PKPass`, `WITH_QRCODE` ou IDs CardWallet no artefato final.
- [ ] Migrações de banco foram testadas em install novo e upgrade.
- [ ] Manifest/Info.plist não anunciam MIME/UTI removidos.
- [ ] APK/AAB e IPA não carregam ZXing/QR sem necessidade.
- [ ] Matriz de CI publica apenas o produto pretendido.
- [ ] Fastlane e credenciais antigas foram rotacionados/arquivados fora do repositório.

## Rollback

Não misturar a remoção CardWallet com a migração do detector. Faça um commit/PR dedicado e preserve uma tag da última versão dual-flavor. Se uma dependência compartilhada for descoberta, reverta apenas a etapa afetada, extraia uma interface comum e repita.
