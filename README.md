# Painel Adriano Lanches

Painel do restaurante: recebe os pedidos do [Cardápio Adriano](https://github.com/pertso402/Card-pio-Adriano) em tempo real e administra produtos e configurações da loja.

HTML, CSS e JavaScript puros, sem build. O backend é o Supabase (projeto CARDAPIOS-CLIENTES). O SQL do banco está na pasta `supabase/`.

## Arquivos

| Arquivo | O que faz |
|---|---|
| `index.html` | Login por PIN, quadro de pedidos, abas Cardápio e Loja |
| `style.css` | Visual do painel e cupom de impressão 80mm |
| `painel.js` | Login, pedidos em tempo real, som, status, impressão, resumo do dia |
| `admin.js` | Produtos (preço, esgotado, destaque, foto, turbinar) e configurações da loja |
| `clientes.js` | Base de clientes (criada a cada pedido), busca e exportação para planilha |
| `config.js` | URL e chave pública do Supabase, slug da loja, e-mail do usuário do painel |
| `supabase/migrations/001_initial.sql` | Tabelas, RLS, funções `criar_pedido`, `status_pedido`, `vitrine_social`, Realtime e Storage |
| `supabase/migrations/002_clientes_pix.sql` | Tabela `clientes`, view `clientes_resumo`, campos de pagamento PIX e função `informar_pix` |
| `supabase/migrations/003_adicionais_cardapio_oficial.sql` | Tabela `adicionais`, adicionais no `criar_pedido` e o cardápio oficial (preços, vegetarianos, molho, cervejas) |
| `supabase/migrations/004_comprovante_distancia.sql` | Comprovante PIX anexado (bucket privado `comprovantes`), taxa por raio e `distancia_km` |
| `supabase/migrations/005_distancia_caminho_carro.sql` | `calcular_entrega`: taxa pelo caminho de carro (rota OSRM) com checagem no banco |
| `supabase/migrations/006_impresso_em.sql` | `pedidos.impresso_em`: a impressora automática marca o que já imprimiu |
| `impressora/` | Programa de impressão automática para o notebook do balcão (veja o README dela) |
| `supabase/seed.sql` | Carga inicial (antiga, da planilha). O cardápio atual vem da migration 003 |

## Acesso

- O dono digita só o PIN. O login real no Supabase usa o usuário `PAINEL_EMAIL`, com senha `PIN_PREFIX + PIN`.
- O usuário precisa estar em `loja_membros` para ler pedidos e editar a loja (regras RLS).
- Nunca coloque a `service_role` key no código: o painel roda no navegador.

## Adicionais

Ovo, salsicha, queijo, batata palha, cebola e presunto (R$ 5); hambúrguer, catupiry, cheddar, frango desfiado, bacon e calabresa (R$ 7). Aparecem na tela dos lanches das categorias com `aceita_adicionais`. O preço é sempre recalculado no banco. Na aba Cardápio do painel dá pra mudar preço, pausar, criar e excluir adicionais.

## Clientes

Todo pedido cria ou atualiza o cliente pelo telefone (só dígitos) dentro da loja. A aba **Clientes** mostra pedidos, total gasto, ticket médio e último pedido, marca quem é **Fiel** (3+ pedidos) ou **Sumido** (30+ dias) e exporta tudo em CSV.

## PIX

Sem gateway e sem taxa. O cliente paga pelo QR (valor exato), anexa o print do comprovante no próprio cardápio (ou manda no WhatsApp, como alternativa) e o pedido fica na coluna **Aguardando PIX**, com a foto do comprovante no ticket. O dono confere no banco e toca em **PIX conferido**: o pedido vai para **Novos**. Som: um toque suave quando entra pedido PIX e um lembrete por minuto enquanto houver comprovante para conferir.

## Taxa por distância

Até `entrega_raio_km` (4 km) cobra `taxa_entrega` (R$ 8); acima, `taxa_entrega_longe` (R$ 12). A distância é o **caminho de carro** (rota do OSRM, gratuito, da loja até o cliente), a partir do GPS do cliente ou do endereço digitado. O banco (`calcular_entrega`) só aceita uma rota coerente com a linha reta; sem rota, estima linha reta × 1,5 e marca "estimado". O ticket mostra a distância e o link do mapa; sem posição, cobra a taxa base e avisa "distância não conferida".

## Impressão automática

A pasta `impressora/` roda no notebook com a térmica: entra como a loja, acompanha os pedidos em tempo real e imprime **cada via (Cozinha e Entrega) como um trabalho separado, cortado no seu papel**. Marca `impresso_em` para não repetir; PIX só sai depois do **PIX conferido**. Instalação em `impressora/README.md`. O `config.json` dela tem a senha da loja e nunca vai para o Git.

## Banco multi-loja

O mesmo projeto Supabase atende vários clientes. Para uma loja nova:

1. Insira uma linha em `lojas` com um `slug` novo.
2. Crie um usuário no Supabase Auth e ligue-o à loja em `loja_membros`.
3. Cadastre categorias e produtos.
4. Troque o `LOJA_SLUG` nos dois `config.js`.

## Rodar localmente

```bash
npx serve .
```

## Publicar

Projeto na Vercel sem framework e sem build command, com a raiz deste repositório como diretório.
