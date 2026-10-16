-- O RLS foi desligado à mão nas tabelas (fora das migrations), o que deixou a chave pública
-- ler e alterar pedidos, clientes e membros da loja. Religa tudo como a 001 definiu.
-- As políticas continuam as mesmas: o cardápio lê lojas/categorias/produtos/adicionais e cria pedido
-- pelo criar_pedido (security definer); painel e impressora automática entram com login.
alter table public.lojas enable row level security;
alter table public.loja_membros enable row level security;
alter table public.categorias enable row level security;
alter table public.produtos enable row level security;
alter table public.adicionais enable row level security;
alter table public.clientes enable row level security;
alter table public.pedidos enable row level security;
alter table public.itens_pedido enable row level security;
