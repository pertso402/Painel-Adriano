-- ═══════════════════════════════════════════════════════════
--  CARDAPIOS-CLIENTES — schema multi-loja
--  Cada loja tem seu slug; cardápio público lê produtos, cria
--  pedidos só via RPC (preço recalculado no banco); painel lê e
--  atualiza pedidos via usuário autenticado membro da loja.
-- ═══════════════════════════════════════════════════════════

-- ── Tabelas ────────────────────────────────────────────────
create table public.lojas (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,
  nome        text not null,
  -- 'auto' segue config.horario; 'aberta'/'fechada' forçam o estado
  modo        text not null default 'auto' check (modo in ('auto', 'aberta', 'fechada')),
  config      jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.loja_membros (
  loja_id  uuid not null references public.lojas(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  primary key (loja_id, user_id)
);
create index loja_membros_user_idx on public.loja_membros(user_id);

create table public.categorias (
  id         uuid primary key default gen_random_uuid(),
  loja_id    uuid not null references public.lojas(id) on delete cascade,
  slug       text not null,
  nome       text not null,
  ordem      int  not null default 0,
  ativa      boolean not null default true,
  created_at timestamptz not null default now(),
  unique (loja_id, slug)
);

create table public.produtos (
  id            uuid primary key default gen_random_uuid(),
  loja_id       uuid not null references public.lojas(id) on delete cascade,
  categoria_id  uuid references public.categorias(id) on delete set null,
  nome          text not null,
  descricao     text,
  preco         numeric(10,2) not null check (preco >= 0),
  foto_url      text,
  disponivel    boolean not null default true,
  destaque      boolean not null default false,
  ordem         int not null default 0,
  -- produto sugerido como "turbinar" (upgrade) na tela do item
  upgrade_para  uuid references public.produtos(id) on delete set null,
  tags          text[] not null default '{}',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index produtos_loja_idx on public.produtos(loja_id);
create index produtos_categoria_idx on public.produtos(categoria_id);
create index produtos_upgrade_idx on public.produtos(upgrade_para);

create table public.pedidos (
  id               uuid primary key default gen_random_uuid(),
  loja_id          uuid not null references public.lojas(id) on delete cascade,
  numero           int not null,
  token            uuid not null default gen_random_uuid() unique,
  status           text not null default 'novo'
                   check (status in ('novo', 'preparo', 'pronto', 'entrega', 'finalizado', 'cancelado')),
  cliente_nome     text not null,
  cliente_telefone text not null,
  tipo_entrega     text not null check (tipo_entrega in ('delivery', 'retirada')),
  endereco         jsonb,
  forma_pagamento  text not null check (forma_pagamento in ('pix', 'dinheiro', 'cartao')),
  troco_para       numeric(10,2),
  subtotal         numeric(10,2) not null,
  taxa_entrega     numeric(10,2) not null default 0,
  desconto         numeric(10,2) not null default 0,
  total            numeric(10,2) not null,
  observacoes      text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (loja_id, numero)
);
create index pedidos_loja_created_idx on public.pedidos(loja_id, created_at desc);

create table public.itens_pedido (
  id             uuid primary key default gen_random_uuid(),
  pedido_id      uuid not null references public.pedidos(id) on delete cascade,
  loja_id        uuid not null references public.lojas(id) on delete cascade,
  produto_id     uuid references public.produtos(id) on delete set null,
  produto_nome   text not null,
  observacao     text,
  preco_unitario numeric(10,2) not null,
  quantidade     int not null check (quantidade > 0),
  subtotal       numeric(10,2) not null,
  -- de onde veio o item: mede o que os mecanismos de upsell estão vendendo
  origem         text not null default 'cardapio'
                 check (origem in ('cardapio', 'upsell', 'bump', 'upgrade', 'repetir'))
);
create index itens_pedido_pedido_idx on public.itens_pedido(pedido_id);
create index itens_pedido_loja_idx on public.itens_pedido(loja_id);
create index itens_pedido_produto_idx on public.itens_pedido(produto_id);

-- ── updated_at ─────────────────────────────────────────────
create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end $$;

create trigger lojas_touch    before update on public.lojas    for each row execute function public.touch_updated_at();
create trigger produtos_touch before update on public.produtos for each row execute function public.touch_updated_at();
create trigger pedidos_touch  before update on public.pedidos  for each row execute function public.touch_updated_at();

-- ── Helpers ────────────────────────────────────────────────
create or replace function public.is_membro(p_loja uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.loja_membros m where m.loja_id = p_loja and m.user_id = (select auth.uid()));
$$;

-- Aberta agora? Considera modo forçado e horário que atravessa a meia-noite.
create or replace function public.loja_aberta(p_loja public.lojas) returns boolean
language plpgsql stable set search_path = '' as $$
declare
  agora time := (now() at time zone 'America/Sao_Paulo')::time;
  abre  time := coalesce(p_loja.config->'horario'->>'abre',  '00:00')::time;
  fecha time := coalesce(p_loja.config->'horario'->>'fecha', '23:59')::time;
begin
  if p_loja.modo = 'aberta'  then return true;  end if;
  if p_loja.modo = 'fechada' then return false; end if;
  if abre <= fecha then return agora >= abre and agora < fecha; end if;
  return agora >= abre or agora < fecha;
end $$;

-- ── RLS ────────────────────────────────────────────────────
alter table public.lojas        enable row level security;
alter table public.loja_membros enable row level security;
alter table public.categorias   enable row level security;
alter table public.produtos     enable row level security;
alter table public.pedidos      enable row level security;
alter table public.itens_pedido enable row level security;

create policy lojas_select  on public.lojas for select to anon, authenticated using (true);
create policy lojas_update  on public.lojas for update to authenticated using (public.is_membro(id)) with check (public.is_membro(id));

create policy membros_select on public.loja_membros for select to authenticated using (user_id = (select auth.uid()));

create policy categorias_select on public.categorias for select to anon, authenticated using (true);
create policy categorias_insert on public.categorias for insert to authenticated with check (public.is_membro(loja_id));
create policy categorias_update on public.categorias for update to authenticated using (public.is_membro(loja_id)) with check (public.is_membro(loja_id));
create policy categorias_delete on public.categorias for delete to authenticated using (public.is_membro(loja_id));

create policy produtos_select on public.produtos for select to anon, authenticated using (true);
create policy produtos_insert on public.produtos for insert to authenticated with check (public.is_membro(loja_id));
create policy produtos_update on public.produtos for update to authenticated using (public.is_membro(loja_id)) with check (public.is_membro(loja_id));
create policy produtos_delete on public.produtos for delete to authenticated using (public.is_membro(loja_id));

-- Pedidos: só membros leem/alteram. Cliente cria via RPC criar_pedido.
create policy pedidos_select on public.pedidos for select to authenticated using (public.is_membro(loja_id));
create policy pedidos_update on public.pedidos for update to authenticated using (public.is_membro(loja_id)) with check (public.is_membro(loja_id));
create policy itens_select   on public.itens_pedido for select to authenticated using (public.is_membro(loja_id));

-- ── RPC: criar pedido (preços sempre do banco) ─────────────
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
  v_tipo      text := p_pedido->>'tipo_entrega';
  v_pag       text := p_pedido->>'forma_pagamento';
  v_nome      text := nullif(trim(p_pedido->>'cliente_nome'), '');
  v_tel       text := nullif(trim(p_pedido->>'cliente_telefone'), '');
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

  -- numeração sequencial por loja sem corrida
  perform pg_advisory_xact_lock(hashtext(v_loja.id::text));
  select coalesce(max(numero), 0) + 1 into v_numero from public.pedidos where loja_id = v_loja.id;

  insert into public.pedidos (
    loja_id, numero, cliente_nome, cliente_telefone, tipo_entrega, endereco,
    forma_pagamento, troco_para, subtotal, taxa_entrega, total, observacoes)
  values (
    v_loja.id, v_numero, left(v_nome, 80), left(v_tel, 30), v_tipo,
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

-- ── RPC: cliente acompanha o pedido pelo token ─────────────
create or replace function public.status_pedido(p_token uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'numero', p.numero, 'status', p.status, 'tipo_entrega', p.tipo_entrega,
    'total', p.total, 'created_at', p.created_at, 'updated_at', p.updated_at,
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('nome', i.produto_nome, 'qtd', i.quantidade)), '[]'::jsonb)
              from public.itens_pedido i where i.pedido_id = p.id))
  from public.pedidos p where p.token = p_token;
$$;

-- ── RPC: prova social real (sem expor dados de clientes) ───
create or replace function public.vitrine_social(p_loja_slug text) returns jsonb
language sql stable security definer set search_path = '' as $$
  with l as (select id from public.lojas where slug = p_loja_slug)
  select jsonb_build_object(
    'pedidos_hoje', (select count(*) from public.pedidos p, l
                      where p.loja_id = l.id and p.status <> 'cancelado'
                        and (p.created_at at time zone 'America/Sao_Paulo')::date = (now() at time zone 'America/Sao_Paulo')::date),
    'top', (select coalesce(jsonb_agg(t.produto_id), '[]'::jsonb) from (
              select i.produto_id from public.itens_pedido i join public.pedidos p on p.id = i.pedido_id, l
              where i.loja_id = l.id and p.status <> 'cancelado' and i.produto_id is not null
                and p.created_at > now() - interval '7 days'
              group by i.produto_id order by sum(i.quantidade) desc limit 5) t));
$$;

revoke all on function public.criar_pedido(text, jsonb, jsonb) from public;
revoke all on function public.status_pedido(uuid) from public;
revoke all on function public.vitrine_social(text) from public;
grant execute on function public.criar_pedido(text, jsonb, jsonb) to anon, authenticated;
grant execute on function public.status_pedido(uuid) to anon, authenticated;
grant execute on function public.vitrine_social(text) to anon, authenticated;
revoke execute on function public.is_membro(uuid) from public, anon;
grant execute on function public.is_membro(uuid) to authenticated;

-- ── Realtime ───────────────────────────────────────────────
alter publication supabase_realtime add table public.lojas, public.categorias, public.produtos, public.pedidos, public.itens_pedido;

-- ── Storage: fotos dos produtos (pasta = slug da loja) ─────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('produto-fotos', 'produto-fotos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy produto_fotos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'produto-fotos' and exists (
    select 1 from public.lojas l join public.loja_membros m on m.loja_id = l.id
    where l.slug = (storage.foldername(name))[1] and m.user_id = (select auth.uid())));
create policy produto_fotos_update on storage.objects for update to authenticated
  using (bucket_id = 'produto-fotos' and exists (
    select 1 from public.lojas l join public.loja_membros m on m.loja_id = l.id
    where l.slug = (storage.foldername(name))[1] and m.user_id = (select auth.uid())));
create policy produto_fotos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'produto-fotos' and exists (
    select 1 from public.lojas l join public.loja_membros m on m.loja_id = l.id
    where l.slug = (storage.foldername(name))[1] and m.user_id = (select auth.uid())));
