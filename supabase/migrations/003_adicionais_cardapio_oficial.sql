-- ═══════════════════════════════════════════════════════════
--  003 — Adicionais + cardápio oficial da Adriano Lanches
--  (preços e itens conforme o cardápio impresso, 15/10/2026)
-- ═══════════════════════════════════════════════════════════

-- ── Adicionais (extras pagos que vão dentro do lanche) ─────
create table public.adicionais (
  id         uuid primary key default gen_random_uuid(),
  loja_id    uuid not null references public.lojas(id) on delete cascade,
  nome       text not null,
  preco      numeric(10,2) not null check (preco >= 0),
  ordem      int not null default 0,
  disponivel boolean not null default true,
  created_at timestamptz not null default now()
);
create index adicionais_loja_idx on public.adicionais(loja_id);
alter table public.adicionais enable row level security;
create policy adicionais_select on public.adicionais for select to anon, authenticated using (true);
create policy adicionais_insert on public.adicionais for insert to authenticated with check (public.is_membro(loja_id));
create policy adicionais_update on public.adicionais for update to authenticated using (public.is_membro(loja_id)) with check (public.is_membro(loja_id));
create policy adicionais_delete on public.adicionais for delete to authenticated using (public.is_membro(loja_id));
alter publication supabase_realtime add table public.adicionais;

-- quais categorias aceitam adicionais (lanches sim, bebidas não)
alter table public.categorias add column aceita_adicionais boolean not null default false;
-- adicionais escolhidos em cada item: [{id, nome, preco}]
alter table public.itens_pedido add column adicionais jsonb not null default '[]'::jsonb;

-- ── criar_pedido: preço do item = produto + adicionais ─────
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

    -- adicionais: sempre com preço do banco
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

  v_gratis := nullif(v_loja.config->>'frete_gratis_acima', '')::numeric;
  if v_tipo = 'delivery' then
    v_taxa := coalesce(nullif(v_loja.config->>'taxa_entrega', '')::numeric, 0);
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
    loja_id, numero, cliente_id, cliente_nome, cliente_telefone, tipo_entrega, endereco,
    forma_pagamento, troco_para, subtotal, taxa_entrega, total, observacoes)
  values (
    v_loja.id, v_numero, v_cliente, left(v_nome, 80), left(v_tel, 30), v_tipo,
    case when v_tipo = 'delivery' then v_end else null end,
    v_pag,
    case when v_pag = 'dinheiro' then nullif(p_pedido->>'troco_para', '')::numeric else null end,
    v_subtotal, v_taxa, v_total, left(nullif(trim(p_pedido->>'observacoes'), ''), 500))
  returning * into v_pedido;

  insert into public.itens_pedido (pedido_id, loja_id, produto_id, produto_nome, observacao, preco_unitario, quantidade, subtotal, origem, adicionais)
  select v_pedido.id, v_loja.id, (l->>'produto_id')::uuid, l->>'nome', l->>'obs',
         (l->>'preco')::numeric, (l->>'qtd')::int, (l->>'preco')::numeric * (l->>'qtd')::int, l->>'origem', l->'adicionais'
  from jsonb_array_elements(v_linhas) l;

  return jsonb_build_object('id', v_pedido.id, 'numero', v_pedido.numero, 'token', v_pedido.token,
                            'subtotal', v_subtotal, 'taxa_entrega', v_taxa, 'total', v_total);
end $$;

-- ═══ Dados: cardápio oficial ═══════════════════════════════
do $$
declare
  l uuid := (select id from public.lojas where slug = 'adriano-lanches');
  c_veg uuid; c_molho uuid; c_beb uuid; c_alc uuid; c_ham uuid;
begin
  if l is null then return; end if;

  update public.lojas set config = config
    || jsonb_build_object('whatsapp', '5544988270834', 'instagram', 'adrianolanchesumu')
    where id = l;

  -- categorias
  update public.categorias set aceita_adicionais = true where loja_id = l and slug in ('prensados-salsicha', 'lanches-hamburguer');
  insert into public.categorias (loja_id, slug, nome, ordem, aceita_adicionais) values
    (l, 'vegetarianos', 'Vegetarianos', 3, true),
    (l, 'molhos', 'Molho da casa', 4, false),
    (l, 'bebidas-alcoolicas', 'Bebidas alcoólicas', 6, false)
  on conflict (loja_id, slug) do nothing;
  update public.categorias set ordem = 5 where loja_id = l and slug = 'bebidas';
  select id into c_veg from public.categorias where loja_id = l and slug = 'vegetarianos';
  select id into c_molho from public.categorias where loja_id = l and slug = 'molhos';
  select id into c_beb from public.categorias where loja_id = l and slug = 'bebidas';
  select id into c_alc from public.categorias where loja_id = l and slug = 'bebidas-alcoolicas';
  select id into c_ham from public.categorias where loja_id = l and slug = 'lanches-hamburguer';

  -- preços dos lanches (cardápio impresso)
  update public.produtos p set preco = v.preco from (values
    ('Simples', 22), ('Simples com Batata Palha', 24), ('Especial com Bacon', 27), ('Especial com Bacon e Catupiry', 33),
    ('Especial com Catupiry', 27), ('Especial com Calabresa', 27), ('Especial com Bacon e Calabresa', 33), ('Especial com Frango', 27),
    ('Especial com Frango e Bacon', 33), ('Especial com Frango, Bacon e Catupiry', 37), ('Especial com Frango e Calabresa', 33),
    ('Especial com Frango ao Catupiry', 33), ('Especial Big', 42),
    ('X-Salada', 27), ('X-Bacon', 33), ('X-Egg', 31), ('X-Catupiry', 33), ('X-Calabresa', 33), ('X-Frango', 34),
    ('Misto Quente', 20), ('Bauru', 21), ('X-Picanha', 39), ('X-Picanha c/ Cheddar', 44), ('X-Tudo', 43), ('X-Galinha', 31),
    ('X-Burg', 26.50), ('X-Cheddar', 33),
    ('X-Vegetariano', 27), ('X-Vegetariano Catupiry', 32), ('X-Vegetariano Cheddar', 32)
  ) v(nome, preco) where p.loja_id = l and p.nome = v.nome;

  -- vegetarianos ganham categoria própria
  update public.produtos set categoria_id = c_veg where loja_id = l and nome like 'X-Vegetariano%';

  -- bebidas: preços do cardápio
  update public.produtos p set preco = v.preco from (values
    ('Coca-Cola Lata 350ml', 7), ('Fanta Lata 350ml', 7), ('Guaraná Antarctica Lata 350ml', 7), ('Sprite Lata 350ml', 7),
    ('Guaraná Antarctica Zero Lata 350ml', 7), ('Coca-Cola Zero Lata 350ml', 7),
    ('Coca-Cola KS 290ml', 6), ('Fanta KS 290ml', 6), ('Sprite KS 290ml', 6),
    ('Coca-Cola 600ml', 12), ('Guaraná Antarctica 600ml', 12),
    ('Festysuco Laranja 900ml', 18), ('Energético Monster', 12), ('Água Mineral', 4.50), ('H2O', 8)
  ) v(nome, preco) where p.loja_id = l and p.nome = v.nome;
  update public.produtos set nome = 'Suco 300ml', preco = 8 where loja_id = l and nome = 'Suco Prats 900ml';
  update public.produtos set nome = 'Itubaína 355ml', preco = 7 where loja_id = l and nome = 'Itubaína Long Neck 355ml';

  -- itens que não estão no cardápio
  delete from public.produtos where loja_id = l and nome in ('Guaraná Antarctica 2L', 'Coca-Cola 2L', 'Coca-Cola Zero 2L', 'Energético Monster Zero');

  -- molho da casa
  insert into public.produtos (loja_id, categoria_id, nome, descricao, preco, ordem) values
    (l, c_molho, 'Molho Verde (sachê 20g)', 'O molho verde da casa, no sachê.', 2, 31),
    (l, c_molho, 'Bisnaga de Molho Verde', 'A bisnaga inteira do molho verde da casa.', 15, 32);

  -- bebidas alcoólicas
  insert into public.produtos (loja_id, categoria_id, nome, preco, ordem) values
    (l, c_alc, 'Long Neck Heineken', 10, 60), (l, c_alc, 'Long Neck Stella Artois', 10, 61),
    (l, c_alc, 'Long Neck Budweiser', 10, 62), (l, c_alc, 'Long Neck Sol', 10, 63),
    (l, c_alc, 'Cerveja Brahma Lata', 7, 64), (l, c_alc, 'Cerveja Skol Lata', 7, 65),
    (l, c_alc, 'Cerveja Antarctica Boa Lata', 7, 66);

  -- adicionais
  insert into public.adicionais (loja_id, nome, preco, ordem) values
    (l, 'Ovo', 5, 1), (l, 'Salsicha', 5, 2), (l, 'Queijo', 5, 3), (l, 'Batata palha', 5, 4), (l, 'Cebola', 5, 5), (l, 'Presunto', 5, 6),
    (l, 'Hambúrguer', 7, 7), (l, 'Catupiry', 7, 8), (l, 'Cheddar', 7, 9), (l, 'Frango desfiado', 7, 10), (l, 'Bacon', 7, 11), (l, 'Calabresa', 7, 12);
end $$;
