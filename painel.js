// ═══════════════════════════════════════════════════════════
//  PAINEL — login por PIN, pedidos em tempo real, resumo do dia
// ═══════════════════════════════════════════════════════════
'use strict';

const supa = window.supabase.createClient(SUPABASE_CONFIG.url, SUPABASE_CONFIG.key);
const $ = id => document.getElementById(id);
const fmt = v => 'R$ ' + Number(v || 0).toFixed(2).replace('.', ',');
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const pref = { get: (k, d) => { try { return JSON.parse(localStorage.getItem(k)) ?? d; } catch { return d; } }, set: (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} } };

let LOJA = null;
let PEDIDOS = new Map();      // id -> pedido com itens_pedido
let period = 'hoje';
let soundOn = pref.get('adl_som', true);
const freshIds = new Set();

// ── Toast ──────────────────────────────────────────────────
let toastT;
function toast(m) { const t = $('toast'); t.textContent = m; t.classList.add('show'); clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove('show'), 2200); }

// ── LOGIN ──────────────────────────────────────────────────
let pin = '';
function renderPin() { [...$('pinDots').children].forEach((d, i) => d.classList.toggle('on', i < pin.length)); }
$('pinpad').addEventListener('click', async e => {
  const b = e.target.closest('button'); if (!b) return;
  unlockAudio();
  const k = b.dataset.k;
  if (k === 'clear') pin = '';
  else if (k === 'back') pin = pin.slice(0, -1);
  else if (pin.length < 4) pin += b.textContent;
  $('pinErr').textContent = '';
  renderPin();
  if (pin.length === 4) await tryLogin();
});
document.addEventListener('keydown', e => {
  if ($('login').hidden) return;
  if (/^\d$/.test(e.key) && pin.length < 4) { pin += e.key; renderPin(); if (pin.length === 4) tryLogin(); }
  if (e.key === 'Backspace') { pin = pin.slice(0, -1); renderPin(); }
});
async function tryLogin() {
  const { error } = await supa.auth.signInWithPassword({ email: PAINEL_EMAIL, password: PIN_PREFIX + pin });
  if (error) {
    pin = ''; renderPin();
    $('pinDots').classList.remove('shake'); void $('pinDots').offsetWidth; $('pinDots').classList.add('shake');
    $('pinErr').textContent = 'PIN errado';
    return;
  }
  await enter();
}
async function enter() {
  const { data: loja, error } = await supa.from('lojas').select('*').eq('slug', LOJA_SLUG).single();
  if (error || !loja) { $('pinErr').textContent = 'Sem acesso a essa loja'; await supa.auth.signOut(); return; }
  LOJA = loja;
  $('login').hidden = true; $('app').hidden = false;
  renderModo();
  await loadPedidos();
  subscribe();
  initAdmin();
  initClientes();
  setInterval(renderBoard, 30000); // atualiza "há X min"
}
$('logoutBtn').onclick = async () => { await supa.auth.signOut(); location.reload(); };

// ── Abas ───────────────────────────────────────────────────
document.querySelectorAll('.bar-tabs button').forEach(b => b.onclick = () => {
  document.querySelectorAll('.bar-tabs button').forEach(x => x.classList.toggle('on', x === b));
  document.querySelectorAll('.view').forEach(v => v.hidden = v.id !== 'view-' + b.dataset.view);
});

// ── Modo da loja ───────────────────────────────────────────
function renderModo() { document.querySelectorAll('#modo button').forEach(b => b.classList.toggle('on', b.dataset.modo === LOJA.modo)); }
document.querySelectorAll('#modo button').forEach(b => b.onclick = async () => {
  const modo = b.dataset.modo;
  const { error } = await supa.from('lojas').update({ modo }).eq('id', LOJA.id);
  if (error) return toast('Erro ao mudar: ' + error.message);
  LOJA.modo = modo; renderModo();
  toast({ auto: 'Abre e fecha sozinha no horário', aberta: 'Loja ABERTA pra pedidos', fechada: 'Loja FECHADA' }[modo]);
});

// ── Pedidos ────────────────────────────────────────────────
function periodStart(p) {
  const ymd = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
  const today = new Date(`${ymd}T00:00:00-03:00`);
  if (p === 'ontem') return [new Date(today - 864e5), today];
  if (p === '7d') return [new Date(today - 6 * 864e5), null];
  return [today, null];
}
async function loadPedidos() {
  const [from, to] = periodStart(period);
  const since48 = new Date(Date.now() - 48 * 3600e3).toISOString();
  let q = supa.from('pedidos').select('*, itens_pedido(*)').eq('loja_id', LOJA.id).gte('created_at', from.toISOString()).order('created_at', { ascending: false }).limit(500);
  if (to) q = q.lt('created_at', to.toISOString());
  const [{ data: hist, error }, { data: ativos }] = await Promise.all([
    q,
    supa.from('pedidos').select('*, itens_pedido(*)').eq('loja_id', LOJA.id).in('status', ['novo', 'preparo', 'pronto', 'entrega']).gte('created_at', since48),
  ]);
  if (error) return toast('Erro ao carregar pedidos');
  PEDIDOS = new Map();
  [...(hist || []), ...(ativos || [])].forEach(p => PEDIDOS.set(p.id, p));
  renderBoard(); renderStats();
}
document.querySelectorAll('#period button').forEach(b => b.onclick = () => {
  period = b.dataset.p;
  document.querySelectorAll('#period button').forEach(x => x.classList.toggle('on', x === b));
  loadPedidos();
});

function inPeriod(p) {
  const [from, to] = periodStart(period);
  const t = new Date(p.created_at);
  return t >= from && (!to || t < to);
}
function renderStats() {
  const list = [...PEDIDOS.values()].filter(p => inPeriod(p) && p.status !== 'cancelado');
  const fat = list.reduce((s, p) => s + Number(p.total), 0);
  const itens = list.flatMap(p => p.itens_pedido || []);
  const sug = itens.filter(i => ['upsell', 'bump'].includes(i.origem)).reduce((s, i) => s + Number(i.subtotal), 0);
  const turb = itens.filter(i => i.origem === 'upgrade').reduce((s, i) => s + i.quantidade, 0);
  const vendasItens = itens.reduce((s, i) => s + Number(i.subtotal), 0);
  $('stFat').textContent = fmt(fat);
  $('stQtd').textContent = list.length;
  $('stTicket').textContent = fmt(list.length ? fat / list.length : 0);
  $('stUp').textContent = fmt(sug);
  $('stUpPct').textContent = list.length ? `${vendasItens ? Math.round(sug / vendasItens * 100) : 0}% dos itens · ${turb} turbinado${turb === 1 ? '' : 's'}` : '';
}

const pixAguardando = p => p.status === 'novo' && p.forma_pagamento === 'pix' && !p.pago;
const colOf = p => pixAguardando(p) ? 'pix' : ({ novo: 'novo', preparo: 'preparo', pronto: 'pronto', entrega: 'pronto', finalizado: 'finalizado', cancelado: 'finalizado' }[p.status]);
function ago(ts) {
  const m = Math.floor((Date.now() - new Date(ts)) / 60000);
  if (m < 1) return 'agora';
  if (m < 60) return `há ${m} min`;
  return `há ${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}`;
}
function nextAction(p) {
  if (pixAguardando(p)) return { to: 'pix', label: '✓ PIX conferido', cls: 'green' };
  if (p.status === 'novo') return { to: 'preparo', label: '🔥 Aceitar · pra chapa', cls: '' };
  if (p.status === 'preparo') return p.tipo_entrega === 'delivery'
    ? { to: 'entrega', label: '🛵 Saiu pra entrega', cls: 'blue' }
    : { to: 'pronto', label: '🛎️ Pronto p/ retirar', cls: 'blue' };
  if (p.status === 'pronto' || p.status === 'entrega') return { to: 'finalizado', label: '✓ Finalizar', cls: 'green' };
  return null;
}
const payLabel = { pix: 'PIX', dinheiro: 'Dinheiro', cartao: 'Cartão' };
function waLink(tel) { const d = (tel || '').replace(/\D/g, ''); return 'https://wa.me/' + (d.length <= 11 ? '55' + d : d); }

function pixLine(p) {
  if (p.forma_pagamento !== 'pix' || p.status === 'cancelado') return '';
  if (p.pago) return '<div class="tk-pix ok">⚡ PIX confirmado</div>';
  if (pixAguardando(p)) {
    if (p.comprovante_path) return `<button class="tk-proof" onclick="verComprovante('${p.id}')">${/\.pdf$/i.test(p.comprovante_path) ? '<span>📄 Comprovante em PDF · toque pra abrir</span>' : `<img data-proof="${p.id}" alt="Comprovante do PIX"><em>ampliar</em>`}</button>
      <div class="tk-pix warn">📎 Comprovante chegou · confira no banco</div>`;
    if (p.pix_informado_em) return '<div class="tk-pix warn">⚡ Disse que mandou o comprovante no WhatsApp · confira</div>';
    return `<div class="tk-wait">⏳ Esperando o cliente pagar · ${ago(p.created_at)}</div>`;
  }
  return `<div class="tk-pix ${p.pix_informado_em ? 'warn' : ''}">${p.pix_informado_em ? '⚡ Comprovante enviado no WhatsApp: confira e confirme' : '⚡ PIX: aguardando o cliente pagar'}<button onclick="confirmarPix('${p.id}')">Confirmar</button></div>`;
}
function kmLine(p) {
  const e = p.endereco || {};
  const mapa = e.lat != null ? `https://www.google.com/maps/search/?api=1&query=${e.lat},${e.lng}` : `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${e.rua}, ${e.numero}, ${e.bairro}, ${(LOJA.config?.endereco || '').split(',').pop()}`)}`;
  const km = p.distancia_km != null ? `${String(Number(p.distancia_km)).replace('.', ',')} km de carro (${e.rota_fonte === 'estimado' ? 'estimado' : e.fonte === 'gps' ? 'GPS' : 'endereço'})` : '<span class="warn">distância não conferida</span>';
  return `<div class="tk-km">${km} · <a href="${mapa}" target="_blank" rel="noopener">ver no mapa</a></div>`;
}
// foto do comprovante (bucket privado → link temporário)
const proofUrls = new Map();
async function proofUrl(p) {
  if (proofUrls.has(p.comprovante_path)) return proofUrls.get(p.comprovante_path);
  const { data } = await supa.storage.from('comprovantes').createSignedUrl(p.comprovante_path, 3600);
  if (data?.signedUrl) proofUrls.set(p.comprovante_path, data.signedUrl);
  return data?.signedUrl;
}
function loadProofs() {
  document.querySelectorAll('img[data-proof]').forEach(async img => {
    const p = PEDIDOS.get(img.dataset.proof); if (!p?.comprovante_path) return;
    const u = await proofUrl(p); if (u && img.src !== u) img.src = u;
  });
}
async function verComprovante(id) {
  const p = PEDIDOS.get(id); if (!p?.comprovante_path) return;
  const u = await proofUrl(p); if (u) window.open(u, '_blank'); else toast('Não deu pra abrir o comprovante');
}
async function confirmarPix(id) {
  const p = PEDIDOS.get(id); if (!p) return;
  ackIds.add(id);
  p.pago = true; p.pago_em = new Date().toISOString(); renderBoard();
  const { error } = await supa.from('pedidos').update({ pago: true, pago_em: p.pago_em }).eq('id', id);
  if (error) { p.pago = false; renderBoard(); return toast('Não salvou: ' + error.message); }
  toast('PIX confirmado ✓');
}
function ticketHTML(p) {
  const act = nextAction(p);
  const late = p.status === 'novo' && Date.now() - new Date(p.created_at) > 10 * 60000;
  const end = p.endereco ? `${esc(p.endereco.rua)}, ${esc(p.endereco.numero)} · ${esc(p.endereco.bairro)}${p.endereco.complemento ? ' · ' + esc(p.endereco.complemento) : ''}` : '';
  return `<article class="tk ${freshIds.has(p.id) ? 'new' : ''} ${p.status === 'finalizado' ? 'done' : ''} ${p.status === 'cancelado' ? 'cancel' : ''}">
    <div class="tk-top"><span class="tk-num">#${String(p.numero).padStart(3, '0')}</span><span class="tk-age ${late ? 'late' : ''}">${ago(p.created_at)} · ${new Date(p.created_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' })}</span></div>
    <span class="tk-tipo ${p.tipo_entrega === 'retirada' ? 'ret' : ''}">${p.tipo_entrega === 'retirada' ? '🏃 Retirada' : '🛵 Entrega'}</span>${p.status === 'cancelado' ? ' <span class="tk-tipo" style="background:var(--red)">Cancelado</span>' : ''}
    <div class="tk-cli">${esc(p.cliente_nome)} · <a href="${waLink(p.cliente_telefone)}" target="_blank" rel="noopener">${esc(p.cliente_telefone)}</a></div>
    ${end ? `<div class="tk-end">📍 ${end}</div>${kmLine(p)}` : ''}
    <div class="tk-items">${(p.itens_pedido || []).map(i => `<div class="tk-item"><b>${i.quantidade}x</b><span>${esc(i.produto_nome)}${i.adicionais?.length ? `<span class="tk-adds">${esc((i.adicionais || []).map(x => '+ ' + x.nome).join(', '))}</span>` : ''}${i.origem === 'upgrade' ? '<span class="tk-up">turbinado</span>' : ''}${['upsell', 'bump'].includes(i.origem) ? '<span class="tk-up">sugestão</span>' : ''}</span></div>${i.observacao ? `<span class="tk-obs">↳ ${esc(i.observacao)}</span>` : ''}`).join('')}</div>
    ${p.observacoes ? `<div class="tk-note">📝 ${esc(p.observacoes)}</div>` : ''}
    ${pixLine(p)}
    <div class="tk-pay"><span>${payLabel[p.forma_pagamento]}${p.pago ? ' ✓ pago' : ''}${p.troco_para ? ` · troco p/ ${fmt(p.troco_para)}` : ''}${Number(p.taxa_entrega) ? ` · entrega ${fmt(p.taxa_entrega)}` : ''}</span><span class="tk-total">${fmt(p.total)}</span></div>
    ${p.status !== 'cancelado' ? `<div class="tk-actions">
      ${act ? `<button class="tk-go ${act.cls}" onclick="${act.to === 'pix' ? `confirmarPix('${p.id}')` : `setStatus('${p.id}','${act.to}')`}">${act.label}</button>` : '<span></span>'}
      <button class="tk-sm" onclick="printPedido('${p.id}')" title="Imprimir">🖨</button>
      ${p.status !== 'finalizado' ? `<button class="tk-sm" onclick="cancelPedido('${p.id}')" title="Cancelar">✕</button>` : ''}
    </div>` : ''}
  </article>`;
}
function renderBoard() {
  const cols = { pix: [], novo: [], preparo: [], pronto: [], finalizado: [] };
  for (const p of PEDIDOS.values()) {
    const c = colOf(p);
    if (c === 'finalizado' && !inPeriod(p)) continue;
    cols[c].push(p);
  }
  for (const [c, list] of Object.entries(cols)) {
    list.sort((a, b) => c === 'finalizado' ? new Date(b.updated_at) - new Date(a.updated_at) : new Date(a.created_at) - new Date(b.created_at));
    $('col-' + c).innerHTML = list.length ? list.map(ticketHTML).join('') : `<div class="col-empty">${{ pix: 'Nenhum PIX esperando', novo: 'Nenhum pedido novo. Já já pinga 🔔', preparo: 'Chapa livre', pronto: 'Nada esperando', finalizado: 'Nada finalizado no período' }[c]}</div>`;
    $('cnt-' + c).textContent = list.length;
  }
  const novos = cols.novo.length, conferir = cols.pix.filter(p => p.pix_informado_em).length;
  $('badgeNovos').hidden = !(novos + conferir); $('badgeNovos').textContent = novos + conferir;
  document.title = novos ? `(${novos}) NOVO PEDIDO · Painel` : conferir ? `(${conferir}) PIX PRA CONFERIR · Painel` : 'Painel · Adriano Lanches';
  ringIfNeeded(cols.novo.filter(p => !ackIds.has(p.id)).length);
  remindPix(conferir);
  loadProofs();
}

async function setStatus(id, status) {
  const p = PEDIDOS.get(id); if (!p) return;
  const prev = p.status;
  p.status = status; p.updated_at = new Date().toISOString(); freshIds.delete(id);
  renderBoard(); renderStats();
  const { error } = await supa.from('pedidos').update({ status }).eq('id', id);
  if (error) { p.status = prev; renderBoard(); toast('Não salvou: ' + error.message); }
}
function cancelPedido(id) {
  const p = PEDIDOS.get(id);
  if (confirm(`Cancelar o pedido #${String(p.numero).padStart(3, '0')} de ${p.cliente_nome}?`)) setStatus(id, 'cancelado');
}

// ── Realtime ───────────────────────────────────────────────
async function fetchPedido(id, tries = 3) {
  const { data } = await supa.from('pedidos').select('*, itens_pedido(*)').eq('id', id).single();
  if (data && !data.itens_pedido?.length && tries > 0) { await new Promise(r => setTimeout(r, 500)); return fetchPedido(id, tries - 1); }
  return data;
}
function subscribe() {
  supa.channel('painel-' + LOJA.id)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'pedidos', filter: `loja_id=eq.${LOJA.id}` }, async ({ new: row }) => {
      const p = await fetchPedido(row.id);
      if (!p) return;
      PEDIDOS.set(p.id, p); freshIds.add(p.id);
      renderBoard(); renderStats();
      toast(pixAguardando(p) ? `⏳ Pedido #${String(p.numero).padStart(3, '0')} · ${fmt(p.total)} · esperando o PIX` : `🔔 Novo pedido #${String(p.numero).padStart(3, '0')} · ${fmt(p.total)}`);
      if (pixAguardando(p)) chime(1);
      if (window.Notification?.permission === "granted" && document.hidden) new Notification('Novo pedido!', { body: `#${p.numero} · ${p.cliente_nome} · ${fmt(p.total)}`, icon: 'https://imvzfueqnpkcrxumiqwz.supabase.co/storage/v1/object/public/produto-fotos/adriano-lanches/logo.webp' });
    })
    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'pedidos', filter: `loja_id=eq.${LOJA.id}` }, ({ new: row }) => {
      const p = PEDIDOS.get(row.id);
      if (p && !p.comprovante_em && row.comprovante_em) { toast(`📎 Pedido #${String(row.numero).padStart(3, '0')}: comprovante do PIX chegou`); chime(); }
      else if (p && !p.pix_informado_em && row.pix_informado_em) { toast(`⚡ Pedido #${String(row.numero).padStart(3, '0')}: cliente diz que mandou o comprovante no WhatsApp`); chime(); }
      if (p) Object.assign(p, row); else PEDIDOS.set(row.id, { ...row, itens_pedido: [] });
      renderBoard(); renderStats();
    })
    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'lojas', filter: `id=eq.${LOJA.id}` }, ({ new: row }) => {
      LOJA = row; renderModo(); if (typeof renderLojaForm === 'function') renderLojaForm();
    })
    .subscribe(status => { if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') setTimeout(loadPedidos, 3000); });
  // ao voltar pra aba, garante que nada se perdeu
  document.addEventListener('visibilitychange', () => { if (!document.hidden) loadPedidos(); });
  try { if (window.Notification?.permission === "default") Notification.requestPermission(); } catch {}
}

// ── Som ────────────────────────────────────────────────────
let audioCtx = null, ringTimer = null;
function unlockAudio() { try { audioCtx ||= new (window.AudioContext || window.webkitAudioContext)(); audioCtx.resume(); } catch {} }
function beep() {
  if (!audioCtx) return;
  const t = audioCtx.currentTime;
  [[880, 0], [1175, .16], [880, .32], [1175, .48]].forEach(([f, d]) => {
    const o = audioCtx.createOscillator(), g = audioCtx.createGain();
    o.type = 'square'; o.frequency.value = f;
    g.gain.setValueAtTime(.0001, t + d); g.gain.exponentialRampToValueAtTime(.18, t + d + .02); g.gain.exponentialRampToValueAtTime(.0001, t + d + .14);
    o.connect(g).connect(audioCtx.destination); o.start(t + d); o.stop(t + d + .15);
  });
}
// toque curto e suave (PIX): 2 notas, volume baixo
function chime(notes = 2) {
  if (!audioCtx || !soundOn) return;
  const t = audioCtx.currentTime;
  [[659, 0], [988, .22]].slice(0, notes).forEach(([f, d]) => {
    const o = audioCtx.createOscillator(), g = audioCtx.createGain();
    o.type = 'sine'; o.frequency.value = f;
    g.gain.setValueAtTime(.0001, t + d); g.gain.exponentialRampToValueAtTime(.12, t + d + .03); g.gain.exponentialRampToValueAtTime(.0001, t + d + .5);
    o.connect(g).connect(audioCtx.destination); o.start(t + d); o.stop(t + d + .55);
  });
}
// comprovante esperando conferência: lembra a cada 1 minuto (não fica apitando)
let pixTimer = null;
function remindPix(n) {
  if (n && soundOn) { if (!pixTimer) pixTimer = setInterval(() => chime(), 60000); }
  else { clearInterval(pixTimer); pixTimer = null; }
}
const ackIds = new Set(); // PIX conferido aqui não precisa tocar de novo em "Novos"
function ringIfNeeded(novos) {
  if (novos && soundOn) { if (!ringTimer) { beep(); ringTimer = setInterval(beep, 3000); } }
  else { clearInterval(ringTimer); ringTimer = null; }
}
function renderSound() { $('soundBtn').classList.toggle('off', !soundOn); $('soundBtn').textContent = soundOn ? '🔔' : '🔕'; }
$('soundBtn').onclick = () => { unlockAudio(); soundOn = !soundOn; pref.set('adl_som', soundOn); renderSound(); ringIfNeeded($('col-novo').querySelectorAll('.tk').length); };
renderSound();
document.addEventListener('click', unlockAudio, { once: true });

// ── Impressão ──────────────────────────────────────────────
function printPedido(id) {
  const p = PEDIDOS.get(id); if (!p) return;
  const e = p.endereco;
  $('printArea').innerHTML = `
    <h1>ADRIANO LANCHES</h1>
    <div class="c">${new Date(p.created_at).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' })}</div>
    <hr><div class="c big">PEDIDO #${String(p.numero).padStart(3, '0')} · ${p.tipo_entrega === 'retirada' ? 'RETIRADA' : 'ENTREGA'}</div><hr>
    <div>${esc(p.cliente_nome)} · ${esc(p.cliente_telefone)}</div>
    ${e ? `<div>${esc(e.rua)}, ${esc(e.numero)} - ${esc(e.bairro)}${e.complemento ? '<br>' + esc(e.complemento) : ''}${p.distancia_km != null ? `<br>${String(Number(p.distancia_km)).replace('.', ',')} km de carro` : ''}</div>` : ''}
    <hr>
    ${(p.itens_pedido || []).map(i => `<div class="r"><span>${i.quantidade}x ${esc(i.produto_nome)}</span><span>${fmt(i.subtotal)}</span></div>${i.adicionais?.length ? `<div class="obs">${esc((i.adicionais || []).map(x => '+ ' + x.nome).join(', '))}</div>` : ''}${i.observacao ? `<div class="obs">* ${esc(i.observacao)}</div>` : ''}`).join('')}
    ${p.observacoes ? `<hr><div class="obs">OBS: ${esc(p.observacoes)}</div>` : ''}
    <hr>
    <div class="r"><span>Subtotal</span><span>${fmt(p.subtotal)}</span></div>
    <div class="r"><span>Entrega</span><span>${fmt(p.taxa_entrega)}</span></div>
    <div class="r big"><span>TOTAL</span><span>${fmt(p.total)}</span></div>
    <div>Pagamento: ${payLabel[p.forma_pagamento]}${p.troco_para ? ` (troco p/ ${fmt(p.troco_para)})` : ''}</div>
    <hr><div class="c">Obrigado pela preferência!</div>`;
  window.print();
}

// ── Sessão existente ───────────────────────────────────────
(async () => {
  const { data } = await supa.auth.getSession();
  if (data.session) await enter();
})();

Object.assign(window, { setStatus, cancelPedido, printPedido, confirmarPix, verComprovante });
