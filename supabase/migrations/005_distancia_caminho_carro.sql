-- ═══════════════════════════════════════════════════════════
--  005 — Taxa pelo caminho de carro (rota OSRM calculada no cardápio)
--  O cardápio manda rota_km; o banco aceita se for coerente com a
--  linha reta (rota nunca é menor que a reta, nem absurdamente maior).
--  Sem rota coerente, estima linha reta × 1,5.
-- ═══════════════════════════════════════════════════════════

create or replace function public.calcular_entrega(p_config jsonb, p_end jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_lat   numeric; v_lng numeric; v_rota numeric;
  v_reta  numeric; v_km  numeric; v_fonte text;
  v_taxa  numeric := coalesce(nullif(p_config->>'taxa_entrega', '')::numeric, 0);
  v_raio  numeric := nullif(p_config->>'entrega_raio_km', '')::numeric;
begin
  begin
    v_lat := (p_end->>'lat')::numeric; v_lng := (p_end->>'lng')::numeric;
    v_rota := nullif(p_end->>'rota_km', '')::numeric;
  exception when others then v_lat := null; v_lng := null; v_rota := null;
  end;
  if v_lat between -90 and 90 and v_lng between -180 and 180
     and nullif(p_config->>'loja_lat', '') is not null and nullif(p_config->>'loja_lng', '') is not null then
    v_reta := public.distancia_km((p_config->>'loja_lat')::numeric, (p_config->>'loja_lng')::numeric, v_lat, v_lng);
    if v_rota is not null and v_rota >= v_reta * 0.98 and v_rota <= greatest(v_reta * 3, v_reta + 2) then
      v_km := round(v_rota, 2);
      v_fonte := case when p_end->>'rota_fonte' = 'estimado' then 'estimado' else 'rota' end;
    else
      v_km := round(v_reta * 1.5, 2); v_fonte := 'estimado';
    end if;
    if v_raio is not null and v_km > v_raio then
      v_taxa := coalesce(nullif(p_config->>'taxa_entrega_longe', '')::numeric, v_taxa);
    end if;
  end if;
  return jsonb_build_object('taxa', v_taxa, 'km', v_km, 'fonte', v_fonte);
end $$;

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
  v_ent       jsonb;
  v_km        numeric;
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
    v_ent := public.calcular_entrega(v_loja.config, v_end);
    v_taxa := (v_ent->>'taxa')::numeric;
    v_km := nullif(v_ent->>'km', '')::numeric;
    if v_km is not null then v_end := v_end || jsonb_build_object('rota_km', v_km, 'rota_fonte', v_ent->>'fonte'); end if;
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
