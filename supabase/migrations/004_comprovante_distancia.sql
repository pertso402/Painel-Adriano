-- ═══════════════════════════════════════════════════════════
--  004 — Comprovante PIX anexado no cardápio + taxa por distância
-- ═══════════════════════════════════════════════════════════

alter table public.pedidos
  add column comprovante_path text,          -- arquivo no bucket comprovantes
  add column comprovante_em   timestamptz,
  add column distancia_km     numeric(6,2);  -- loja → cliente, em linha reta

-- ── Bucket privado dos comprovantes (pasta = slug/token) ───
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('comprovantes', 'comprovantes', false, 6291456,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf'])
on conflict (id) do nothing;

-- cliente só envia para o próprio pedido PIX, ainda não pago, das últimas 24h
create or replace function public.pode_enviar_comprovante(p_slug text, p_token text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.pedidos p join public.lojas l on l.id = p.loja_id
    where l.slug = p_slug and p.token::text = p_token and p.forma_pagamento = 'pix'
      and not p.pago and p.status not in ('cancelado', 'finalizado')
      and p.created_at > now() - interval '1 day');
$$;
revoke all on function public.pode_enviar_comprovante(text, text) from public;
grant execute on function public.pode_enviar_comprovante(text, text) to anon, authenticated;

create policy comprovantes_insert on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'comprovantes'
    and public.pode_enviar_comprovante((storage.foldername(name))[1], (storage.foldername(name))[2]));
create policy comprovantes_select on storage.objects for select to authenticated
  using (bucket_id = 'comprovantes' and exists (
    select 1 from public.lojas l join public.loja_membros m on m.loja_id = l.id
    where l.slug = (storage.foldername(name))[1] and m.user_id = (select auth.uid())));

-- grava no pedido o comprovante que acabou de subir
create or replace function public.registrar_comprovante(p_token uuid, p_path text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_ped public.pedidos; v_slug text;
begin
  select * into v_ped from public.pedidos where token = p_token;
  if not found then return false; end if;
  select slug into v_slug from public.lojas where id = v_ped.loja_id;
  if p_path not like v_slug || '/' || p_token::text || '/%' then raise exception 'Arquivo inválido'; end if;
  if not exists (select 1 from storage.objects where bucket_id = 'comprovantes' and name = p_path) then
    raise exception 'Comprovante não encontrado';
  end if;
  update public.pedidos
     set comprovante_path = p_path, comprovante_em = now(), pix_informado_em = coalesce(pix_informado_em, now())
   where id = v_ped.id and forma_pagamento = 'pix' and not pago;
  return true;
end $$;
revoke all on function public.registrar_comprovante(uuid, text) from public;
grant execute on function public.registrar_comprovante(uuid, text) to anon, authenticated;

-- status_pedido avisa se o comprovante já chegou
create or replace function public.status_pedido(p_token uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'numero', p.numero, 'status', p.status, 'tipo_entrega', p.tipo_entrega,
    'forma_pagamento', p.forma_pagamento, 'pago', p.pago, 'pix_informado', p.pix_informado_em is not null,
    'comprovante', p.comprovante_path is not null,
    'total', p.total, 'created_at', p.created_at, 'updated_at', p.updated_at,
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('nome', i.produto_nome, 'qtd', i.quantidade)), '[]'::jsonb)
              from public.itens_pedido i where i.pedido_id = p.id))
  from public.pedidos p where p.token = p_token;
$$;

-- ── Distância em linha reta (km) ───────────────────────────
create or replace function public.distancia_km(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric) returns numeric
language sql immutable set search_path = '' as $$
  select round((2 * 6371 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))))::numeric, 2);
$$;

-- ── criar_pedido: taxa conforme o raio (config: entrega_raio_km, taxa_entrega_longe, loja_lat, loja_lng)
create or replace function public.criar_pedido(p_loja_slug text, p_pedido jsonb, p_itens jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_loja      public.lojas;
  v_item      jsonb;
  v_prod      public.produtos;
  v_aceita    boolean;
  v_qtd       int;
  v_unit      numeric(10,2);
  v_adds      jsonb;
  v_add_total numeric(10,2);
  v_add_n     int;
  v_add_req   int;
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
  v_lat       numeric;
  v_lng       numeric;
  v_km        numeric;
  v_raio      numeric;
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

    v_adds := '[]'::jsonb; v_add_total := 0;
    v_add_req := case when jsonb_typeof(v_item->'adicionais') = 'array' then jsonb_array_length(v_item->'adicionais') else 0 end;
    if v_add_req > 0 then
      if v_add_req > 12 then raise exception 'Adicionais demais em um item'; end if;
      select aceita_adicionais into v_aceita from public.categorias where id = v_prod.categoria_id;
      if not coalesce(v_aceita, false) then raise exception 'Esse item não aceita adicionais'; end if;
      select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'nome', a.nome, 'preco', a.preco) order by a.ordem), '[]'::jsonb),
             coalesce(sum(a.preco), 0), count(a.id)
        into v_adds, v_add_total, v_add_n
        from jsonb_array_elements_text(v_item->'adicionais') x(id)
        join public.adicionais a on a.id = x.id::uuid and a.loja_id = v_loja.id and a.disponivel;
      if v_add_n <> v_add_req then raise exception 'Um adicional não está mais disponível'; end if;
    end if;

    v_unit := v_prod.preco + v_add_total;
    v_subtotal := v_subtotal + v_unit * v_qtd;
    v_linhas := v_linhas || jsonb_build_object(
      'produto_id', v_prod.id, 'nome', v_prod.nome, 'preco', v_unit, 'adicionais', v_adds,
      'qtd', v_qtd, 'obs', v_obs_item, 'origem', v_origem);
  end loop;

  if v_subtotal < coalesce(nullif(v_loja.config->>'pedido_minimo', '')::numeric, 0) then
    raise exception 'Pedido abaixo do mínimo';
  end if;

  if v_tipo = 'delivery' then
    v_taxa := coalesce(nullif(v_loja.config->>'taxa_entrega', '')::numeric, 0);
    -- distância só conta com coordenada válida do cliente e da loja
    begin
      v_lat := (v_end->>'lat')::numeric; v_lng := (v_end->>'lng')::numeric;
    exception when others then v_lat := null; v_lng := null;
    end;
    v_raio := nullif(v_loja.config->>'entrega_raio_km', '')::numeric;
    if v_lat between -90 and 90 and v_lng between -180 and 180
       and nullif(v_loja.config->>'loja_lat', '') is not null and nullif(v_loja.config->>'loja_lng', '') is not null then
      v_km := public.distancia_km((v_loja.config->>'loja_lat')::numeric, (v_loja.config->>'loja_lng')::numeric, v_lat, v_lng);
      if v_raio is not null and v_km > v_raio then
        v_taxa := coalesce(nullif(v_loja.config->>'taxa_entrega_longe', '')::numeric, v_taxa);
      end if;
    end if;
    v_gratis := nullif(v_loja.config->>'frete_gratis_acima', '')::numeric;
    if v_gratis is not null and v_subtotal >= v_gratis then v_taxa := 0; end if;
  end if;
  v_total := v_subtotal + v_taxa;

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
    loja_id, numero, cliente_id, cliente_nome, cliente_telefone, tipo_entrega, endereco, distancia_km,
    forma_pagamento, troco_para, subtotal, taxa_entrega, total, observacoes)
  values (
    v_loja.id, v_numero, v_cliente, left(v_nome, 80), left(v_tel, 30), v_tipo,
    case when v_tipo = 'delivery' then v_end else null end, v_km,
    v_pag,
    case when v_pag = 'dinheiro' then nullif(p_pedido->>'troco_para', '')::numeric else null end,
    v_subtotal, v_taxa, v_total, left(nullif(trim(p_pedido->>'observacoes'), ''), 500))
  returning * into v_pedido;

  insert into public.itens_pedido (pedido_id, loja_id, produto_id, produto_nome, observacao, preco_unitario, quantidade, subtotal, origem, adicionais)
  select v_pedido.id, v_loja.id, (l->>'produto_id')::uuid, l->>'nome', l->>'obs',
         (l->>'preco')::numeric, (l->>'qtd')::int, (l->>'preco')::numeric * (l->>'qtd')::int, l->>'origem', l->'adicionais'
  from jsonb_array_elements(v_linhas) l;

  return jsonb_build_object('id', v_pedido.id, 'numero', v_pedido.numero, 'token', v_pedido.token,
                            'subtotal', v_subtotal, 'taxa_entrega', v_taxa, 'total', v_total, 'distancia_km', v_km);
end $$;

-- configuração da Adriano Lanches: até 4 km R$ 8, acima R$ 12
update public.lojas set config = config || jsonb_build_object(
  'taxa_entrega', 8, 'taxa_entrega_longe', 12, 'entrega_raio_km', 4,
  'loja_lat', -23.7591136, 'loja_lng', -53.2968658)
where slug = 'adriano-lanches';
