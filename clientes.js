// ═══════════════════════════════════════════════════════════
//  CLIENTES — base criada automaticamente a cada pedido
//  Usa supa, LOJA, $, esc, fmt, toast de painel.js
// ═══════════════════════════════════════════════════════════
'use strict';

let CLIENTES = [];
let cliSort = 'ultimo_pedido_em';
let cliQuery = '';

async function initClientes() {
  await loadClientes();
  supa.channel('clientes-' + LOJA.id)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'clientes', filter: `loja_id=eq.${LOJA.id}` }, () => loadClientes())
    .subscribe();
}
async function loadClientes() {
  const { data, error } = await supa.from('clientes_resumo').select('*').eq('loja_id', LOJA.id).order('ultimo_pedido_em', { ascending: false }).limit(5000);
  if (error) return toast('Erro ao carregar clientes');
  CLIENTES = data || [];
  renderClientes();
}

const diasDesde = ts => Math.floor((Date.now() - new Date(ts)) / 864e5);
const telFmt = t => { const d = (t || '').replace(/\D/g, ''); return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : d.length === 10 ? `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}` : t; };

function renderClientes() {
  const q = cliQuery.trim().toLowerCase();
  const qd = q.replace(/\D/g, '');
  let list = CLIENTES.filter(c => !q || c.nome.toLowerCase().includes(q) || (qd && c.telefone.includes(qd)) || (c.endereco?.bairro || '').toLowerCase().includes(q));
  const key = { ultimo_pedido_em: c => -new Date(c.ultimo_pedido_em), total_pedidos: c => -c.total_pedidos, total_gasto: c => -Number(c.total_gasto), nome: c => c.nome.toLowerCase() }[cliSort];
  list = [...list].sort((a, b) => key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0);

  const recorrentes = CLIENTES.filter(c => c.total_pedidos > 1).length;
  $('cliResumo').textContent = CLIENTES.length
    ? `${CLIENTES.length} cliente${CLIENTES.length === 1 ? '' : 's'} · ${recorrentes} ${recorrentes === 1 ? 'já voltou' : 'já voltaram'} pra pedir de novo`
    : 'Todo mundo que pedir aparece aqui, salvo automático pelo telefone.';

  const th = (k, label) => `<th class="${cliSort === k ? 'on' : ''}" onclick="sortClientes('${k}')">${label}</th>`;
  $('cliTable').innerHTML = `<thead><tr>${th('nome', 'Cliente')}<th>WhatsApp</th><th>Bairro</th>${th('total_pedidos', 'Pedidos')}${th('total_gasto', 'Total gasto')}<th>Ticket médio</th>${th('ultimo_pedido_em', 'Último pedido')}</tr></thead>
    <tbody>${list.length ? list.map(c => {
      const dias = diasDesde(c.ultimo_pedido_em);
      const badge = c.total_pedidos >= 3 ? '<span class="cli-badge">Fiel</span>' : dias > 30 && c.total_pedidos > 0 ? '<span class="cli-badge sumido">Sumido</span>' : '';
      const wa = 'https://wa.me/55' + c.telefone.replace(/^55(?=\d{10,11}$)/, '');
      return `<tr>
        <td><b>${esc(c.nome)}${badge}</b><small>cliente desde ${new Date(c.primeiro_pedido_em).toLocaleDateString('pt-BR')}</small></td>
        <td><a href="${wa}" target="_blank" rel="noopener">${esc(telFmt(c.telefone))}</a></td>
        <td>${esc(c.endereco?.bairro || '—')}</td>
        <td class="num">${c.total_pedidos}</td>
        <td class="num">${fmt(c.total_gasto)}</td>
        <td class="num">${fmt(c.total_pedidos ? c.total_gasto / c.total_pedidos : 0)}</td>
        <td>${dias === 0 ? 'hoje' : dias === 1 ? 'ontem' : `há ${dias} dias`}<br><small>${new Date(c.ultimo_pedido_em).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' })}</small></td>
      </tr>`;
    }).join('') : `<tr><td colspan="7" style="text-align:center;color:var(--ink-3);padding:40px">${q ? 'Ninguém encontrado' : 'Nenhum cliente ainda'}</td></tr>`}</tbody>`;
}
function sortClientes(k) { cliSort = k; renderClientes(); }
$('cliSearch').oninput = e => { cliQuery = e.target.value; renderClientes(); };

// Planilha para remarketing (abre no Excel/Google Sheets)
$('cliCsv').onclick = () => {
  if (!CLIENTES.length) return toast('Nenhum cliente ainda');
  const cols = ['Nome', 'Telefone', 'Rua', 'Número', 'Bairro', 'Complemento', 'Pedidos', 'Total gasto', 'Primeiro pedido', 'Último pedido'];
  const cell = v => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const rows = CLIENTES.map(c => [c.nome, telFmt(c.telefone), c.endereco?.rua, c.endereco?.numero, c.endereco?.bairro, c.endereco?.complemento,
    c.total_pedidos, Number(c.total_gasto).toFixed(2).replace('.', ','), new Date(c.primeiro_pedido_em).toLocaleDateString('pt-BR'), new Date(c.ultimo_pedido_em).toLocaleDateString('pt-BR')]);
  const csv = '﻿' + [cols, ...rows].map(r => r.map(cell).join(';')).join('\r\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
  a.download = `clientes-adriano-lanches-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click(); URL.revokeObjectURL(a.href);
};

Object.assign(window, { initClientes, sortClientes });
