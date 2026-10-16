-- Sinal de vida da impressora automática: o painel mostra se ela está ligada.
-- Tabela à parte (não em "lojas") para não recarregar o cardápio dos clientes a cada minuto.
create table public.impressora_status (
  loja_id    uuid primary key references public.lojas(id) on delete cascade,
  visto_em   timestamptz not null default now(),
  impressora text,
  erro       text
);
alter table public.impressora_status enable row level security;
create policy impressora_status_select on public.impressora_status for select to authenticated using (public.is_membro(loja_id));
create policy impressora_status_insert on public.impressora_status for insert to authenticated with check (public.is_membro(loja_id));
create policy impressora_status_update on public.impressora_status for update to authenticated using (public.is_membro(loja_id)) with check (public.is_membro(loja_id));
