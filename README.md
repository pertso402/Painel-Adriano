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
| `config.js` | URL e chave pública do Supabase, slug da loja, e-mail do usuário do painel |
| `supabase/migrations/001_initial.sql` | Tabelas, RLS, funções `criar_pedido`, `status_pedido`, `vitrine_social`, Realtime e Storage |
| `supabase/seed.sql` | Loja Adriano Lanches, 3 categorias e 51 produtos |

## Acesso

- O dono digita só o PIN. O login real no Supabase usa o usuário `PAINEL_EMAIL`, com senha `PIN_PREFIX + PIN`.
- O usuário precisa estar em `loja_membros` para ler pedidos e editar a loja (regras RLS).
- Nunca coloque a `service_role` key no código: o painel roda no navegador.

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
