-- ═══════════════════════════════════════════════════════════
--  002 — Banco de clientes + pagamento PIX
--  Cliente é identificado pelo telefone (só dígitos) dentro da loja
--  e é criado/atualizado a cada pedido pela RPC criar_pedido.
-- ═══════════════════════════════════════════════════════════

create table public.clientes (
  id               uuid primary key default gen_random_uuid(),
  loja_id          uuid not null references public.lojas(id) on delete cascade,
  telefone         text not null,              -- só dígitos, com DDD
  nome             text not null,
  endereco         jsonb,                      -- último endereço de entrega usado
  primeiro_pedido_em timestamptz not null default now(),
  ultimo_pedido_em   timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  unique (loja_id, telefone)
);
create index clientes_loja_ultimo_idx on public.clientes(loja_id, ultimo_pedido_em desc);

alter table public.clientes enable row level security;
create policy clientes_select on public.clientes for select to authenticated using (public.is_membro(loja_id));
create policy clientes_update on public.clientes for update to authenticated using (public.is_membro(loja_id)) with check (public.is_membro(loja_id));

alter table public.pedidos
  add column cliente_id       uuid references public.clientes(id) on delete set null,
  add column pago             boolean not null default false,
  add column pago_em          timestamptz,
  add column pix_informado_em timestamptz;   -- cliente tocou em "Já paguei"
create index pedidos_cliente_idx on public.pedidos(cliente_id);

-- Resumo calculado dos pedidos (cancelados não contam); respeita a RLS de quem consulta
create view public.clientes_resumo with (security_invoker = true) as
select c.*,
       count(p.id) filter (where p.status <> 'cancelado')                         as total_pedidos,
       coalesce(sum(p.total) filter (where p.status <> 'cancelado'), 0)::numeric(10,2) as total_gasto
from public.clientes c
left join public.pedidos p on p.cliente_id = c.id
group by c.id;

-- ── criar_pedido: agora grava/atualiza o cliente ───────────
create or replace function public.criar_pedido(p_loja_slug text, p_pedido jsonb, p_itens jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_loja      public.lojas;
  v_item      jsonb;
  v_prod      public.produtos;
  v_qtd       int;
  v_subtotal  numeric(10,2) := 0;
  v_taxa      numeric(10,2) := 0;
  v_total     numeric(10,2);
  v_numero    int;
  v_pedido    public.pedidos;
  v_cliente   uuid;
  v_tipo      text := p_pedido->>'tipo_entrega';
  v_pag       text := p_pedido->>'forma_pagamento';
  v_nome      text := nullif(trim(p_pedido->>'cliente_nome'), '');
  v_tel       text := nullif(trim(p_pedido->>'cliente_telefone'), '');
  v_tel_dig   text := regexp_replace(coalesce(p_pedido->>'cliente_telefone', ''), '\D', '', 'g');
  v_end       jsonb := p_pedido->'endereco';
  v_gratis    numeric;
  v_obs_item  text;
  v_origem    text;
  v_linhas    jsonb := '[]'::jsonb;
begin
  select * into v_loja from public.lojas where slug = p_loja_slug;
  if not found then raise exception 'Loja não encontrada'; end if;
  if not public.loja_aberta(v_loja) then raise exception 'A loja está fechada agora'; end if;

  if v_nome is null or v_tel is null then raise exception 'Informe nome e telefone'; end if;
  if length(v_tel_dig) < 10 then raise exception 'Telefone com DDD, por favor'; end if;
  if v_tipo is null or v_tipo not in ('delivery', 'retirada') then raise exception 'Tipo de entrega inválido'; end if;
  if v_pag is null or v_pag not in ('pix', 'dinheiro', 'cartao') then raise exception 'Forma de pagamento inválida'; end if;
  if v_tipo = 'delivery' and (
       nullif(trim(v_end->>'rua'), '') is null or
       nullif(trim(v_end->>'numero'), '') is null or
       nullif(trim(v_end->>'bairro'), '') is null) then
    raise exception 'Endereço incompleto';
  end if;
  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Carrinho vazio';
  end if;
  if jsonb_array_length(p_itens) > 60 then raise exception 'Pedido grande demais'; end if;

  for v_item in select * from jsonb_array_elements(p_itens) loop
    select * into v_prod from public.produtos
      where id = (v_item->>'produto_id')::uuid and loja_id = v_loja.id and disponivel;
    if not found then raise exception 'Um item do carrinho não está mais disponível'; end if;
    v_qtd := greatest(1, least(50, coalesce((v_item->>'quantidade')::int, 1)));
    v_obs_item := left(nullif(trim(v_item->>'observacao'), ''), 200);
    v_origem := coalesce(v_item->>'origem', 'cardapio');
    if v_origem not in ('cardapio', 'upsell', 'bump', 'upgrade', 'repetir') then v_origem := 'cardapio'; end if;
    v_subtotal := v_subtotal + v_prod.preco * v_qtd;
    v_linhas := v_linhas || jsonb_build_object(
      'produto_id', v_prod.id, 'nome', v_prod.nome, 'preco', v_prod.preco,
      'qtd', v_qtd, 'obs', v_obs_item, 'origem', v_origem);
  end loop;

  if v_subtotal < coalesce(nullif(v_loja.config->>'pedido_minimo', '')::numeric, 0) then
    raise exception 'Pedido abaixo do mínimo';
  end if;

  v_gratis := nullif(v_loja.config->>'frete_gratis_acima', '')::numeric;
  if v_tipo = 'delivery' then
    v_taxa := coalesce(nullif(v_loja.config->>'taxa_entrega', '')::numeric, 0);
    if v_gratis is not null and v_subtotal >= v_gratis then v_taxa := 0; end if;
  end if;
  v_total := v_subtotal + v_taxa;

  -- cliente: cria ou atualiza pelo telefone
  insert into public.clientes as c (loja_id, telefone, nome, endereco)
  values (v_loja.id, v_tel_dig, left(v_nome, 80), case when v_tipo = 'delivery' then v_end else null end)
  on conflict (loja_id, telefone) do update
    set nome = excluded.nome,
        endereco = coalesce(excluded.endereco, c.endereco),
        ultimo_pedido_em = now()
  returning id into v_cliente;

  perform pg_advisory_xact_lock(hashtext(v_loja.id::text));
  select coalesce(max(numero), 0) + 1 into v_numero from public.pedidos where loja_id = v_loja.id;

  insert into public.pedidos (
    loja_id, numero, cliente_id, cliente_nome, cliente_telefone, tipo_entrega, endereco,
    forma_pagamento, troco_para, subtotal, taxa_entrega, total, observacoes)
  values (
    v_loja.id, v_numero, v_cliente, left(v_nome, 80), left(v_tel, 30), v_tipo,
    case when v_tipo = 'delivery' then v_end else null end,
    v_pag,
    case when v_pag = 'dinheiro' then nullif(p_pedido->>'troco_para', '')::numeric else null end,
    v_subtotal, v_taxa, v_total, left(nullif(trim(p_pedido->>'observacoes'), ''), 500))
  returning * into v_pedido;

  insert into public.itens_pedido (pedido_id, loja_id, produto_id, produto_nome, observacao, preco_unitario, quantidade, subtotal, origem)
  select v_pedido.id, v_loja.id, (l->>'produto_id')::uuid, l->>'nome', l->>'obs',
         (l->>'preco')::numeric, (l->>'qtd')::int, (l->>'preco')::numeric * (l->>'qtd')::int, l->>'origem'
  from jsonb_array_elements(v_linhas) l;

  return jsonb_build_object('id', v_pedido.id, 'numero', v_pedido.numero, 'token', v_pedido.token,
                            'subtotal', v_subtotal, 'taxa_entrega', v_taxa, 'total', v_total);
end $$;

-- ── status_pedido: inclui pagamento ─────────────────────────
create or replace function public.status_pedido(p_token uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'numero', p.numero, 'status', p.status, 'tipo_entrega', p.tipo_entrega,
    'forma_pagamento', p.forma_pagamento, 'pago', p.pago, 'pix_informado', p.pix_informado_em is not null,
    'total', p.total, 'created_at', p.created_at, 'updated_at', p.updated_at,
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('nome', i.produto_nome, 'qtd', i.quantidade)), '[]'::jsonb)
              from public.itens_pedido i where i.pedido_id = p.id))
  from public.pedidos p where p.token = p_token;
$$;

-- ── cliente avisa que pagou o PIX (a loja confere e confirma no painel) ──
create or replace function public.informar_pix(p_token uuid) returns boolean
language sql security definer set search_path = '' as $$
  update public.pedidos set pix_informado_em = coalesce(pix_informado_em, now())
  where token = p_token and forma_pagamento = 'pix' and status <> 'cancelado'
  returning true;
$$;

revoke all on function public.informar_pix(uuid) from public;
grant execute on function public.informar_pix(uuid) to anon, authenticated;

alter publication supabase_realtime add table public.clientes;
