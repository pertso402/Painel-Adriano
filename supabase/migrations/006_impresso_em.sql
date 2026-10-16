-- ═══════════════════════════════════════════════════════════
--  006 — Controle da impressora automática
-- ═══════════════════════════════════════════════════════════
-- quando a impressora automática terminou as vias (evita imprimir de novo, mesmo após reiniciar)
alter table public.pedidos add column impresso_em timestamptz;
-- pedidos antigos não entram na fila da impressora
update public.pedidos set impresso_em = coalesce(impresso_em, now());
create index pedidos_loja_impressao_idx on public.pedidos(loja_id, created_at) where impresso_em is null;
