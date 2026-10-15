// ═══════════════════════════════════════════════════════════
//  ADMIN — produtos (CRUD + foto) e configurações da loja
//  Usa supa, LOJA, $, esc, fmt, toast de painel.js
// ═══════════════════════════════════════════════════════════
'use strict';

let CATS = [], PRODS = [], ADDS = [];
let admQuery = '';

async function initAdmin() {
  await loadAdmin();
  renderLojaForm();
  supa.channel('admin-' + LOJA.id)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'produtos', filter: `loja_id=eq.${LOJA.id}` }, () => loadAdmin())
    .on('postgres_changes', { event: '*', schema: 'public', table: 'adicionais', filter: `loja_id=eq.${LOJA.id}` }, () => loadAdmin())
    .subscribe();
}
async function loadAdmin() {
  const [{ data: c }, { data: p }, { data: a }] = await Promise.all([
    supa.from('categorias').select('*').eq('loja_id', LOJA.id).order('ordem'),
    supa.from('produtos').select('*').eq('loja_id', LOJA.id).order('ordem'),
    supa.from('adicionais').select('*').eq('loja_id', LOJA.id).order('ordem'),
  ]);
  CATS = c || []; PRODS = p || []; ADDS = a || [];
  renderAdmin();
}

// ── Lista de produtos ──────────────────────────────────────
function renderAdmin() {
  const q = admQuery.trim().toLowerCase();
  $('admList').innerHTML = CATS.map(c => {
    const list = PRODS.filter(p => p.categoria_id === c.id && (!q || p.nome.toLowerCase().includes(q)));
    if (!list.length && q) return '';
    return `<div class="adm-cat">
      <div class="adm-cat-head"><h3>${esc(c.nome)}</h3><span>${list.length} produtos</span></div>
      ${list.map(p => `<div class="adm-row ${p.disponivel ? '' : 'off'}">
        <button class="adm-thumb" onclick="pickPhoto('${p.id}')" title="Trocar foto">${p.foto_url ? `<img src="${esc(p.foto_url)}" alt="" loading="lazy">` : 'sem foto'}</button>
        <div class="adm-name"><b>${esc(p.nome)}</b><span>${esc(p.descricao || '—')}</span></div>
        <label class="adm-price">R$<input type="number" step="0.01" min="0" value="${Number(p.preco).toFixed(2)}" onchange="savePrice('${p.id}', this.value)"></label>
        <button class="toggle ${p.disponivel ? 'on' : ''}" onclick="toggleDisp('${p.id}')"><i></i>${p.disponivel ? 'Disponível' : 'Esgotado'}</button>
        <button class="star ${p.destaque ? 'on' : ''}" onclick="toggleDest('${p.id}')" title="Destaque (Os brabos da casa)">⭐</button>
        <button class="edit edit-col" onclick="openProd('${p.id}')">Editar</button>
      </div>`).join('')}
    </div>`;
  }).join('') + (q ? '' : addsHTML());
}
// ── Adicionais (vão dentro do lanche, pagos à parte) ───────
function addsHTML() {
  return `<div class="adm-cat">
    <div class="adm-cat-head"><h3>Adicionais</h3><span>${ADDS.length} · aparecem na tela de cada lanche</span><button class="edit" style="margin-left:auto" onclick="newAdd()">+ Novo adicional</button></div>
    ${ADDS.map(x => `<div class="adm-row ${x.disponivel ? '' : 'off'}" style="grid-template-columns:1fr 128px auto auto">
      <div class="adm-name"><b>${esc(x.nome)}</b></div>
      <label class="adm-price">R$<input type="number" step="0.5" min="0" value="${Number(x.preco).toFixed(2)}" onchange="updateAdd('${x.id}', { preco: Number(this.value) }, 'Preço do adicional atualizado')"></label>
      <button class="toggle ${x.disponivel ? 'on' : ''}" onclick="updateAdd('${x.id}', { disponivel: ${!x.disponivel} }, '${x.disponivel ? 'Adicional pausado' : 'Adicional de volta'}')"><i></i>${x.disponivel ? 'Disponível' : 'Em falta'}</button>
      <button class="edit" onclick="deleteAdd('${x.id}')" title="Excluir">✕</button>
    </div>`).join('')}
  </div>`;
}
async function updateAdd(id, patch, msg) {
  const { error } = await supa.from('adicionais').update(patch).eq('id', id);
  if (error) return toast('Erro: ' + error.message);
  Object.assign(ADDS.find(x => x.id === id), patch); renderAdmin(); toast(msg);
}
async function newAdd() {
  const nome = (prompt('Nome do adicional (ex.: Picles)') || '').trim(); if (!nome) return;
  const preco = Number(String(prompt('Preço (R$)', '5') || '').replace(',', '.'));
  if (!(preco >= 0)) return toast('Preço inválido');
  const { error } = await supa.from('adicionais').insert({ loja_id: LOJA.id, nome, preco, ordem: Math.max(0, ...ADDS.map(x => x.ordem)) + 1 });
  if (error) return toast('Erro: ' + error.message);
  toast('Adicional criado'); loadAdmin();
}
async function deleteAdd(id) {
  const x = ADDS.find(a => a.id === id);
  if (!confirm(`Excluir o adicional "${x.nome}"?`)) return;
  const { error } = await supa.from('adicionais').delete().eq('id', id);
  if (error) return toast('Erro: ' + error.message);
  toast('Adicional excluído'); loadAdmin();
}
$('admSearch').oninput = e => { admQuery = e.target.value; renderAdmin(); };
$('newProdBtn').onclick = () => openProd(null);

async function updateProd(id, patch, okMsg) {
  const p = PRODS.find(x => x.id === id); const before = { ...p };
  Object.assign(p, patch); renderAdmin();
  const { error } = await supa.from('produtos').update(patch).eq('id', id);
  if (error) { Object.assign(p, before); renderAdmin(); return toast('Erro: ' + error.message); }
  if (okMsg) toast(okMsg);
}
function savePrice(id, v) {
  const n = Math.round(parseFloat(String(v).replace(',', '.')) * 100) / 100;
  if (!(n >= 0)) return toast('Preço inválido');
  updateProd(id, { preco: n }, 'Preço atualizado no cardápio');
}
function toggleDisp(id) { const p = PRODS.find(x => x.id === id); updateProd(id, { disponivel: !p.disponivel }, p.disponivel ? 'Marcado como esgotado' : 'Voltou pro cardápio'); }
function toggleDest(id) { const p = PRODS.find(x => x.id === id); updateProd(id, { destaque: !p.destaque }, p.destaque ? 'Saiu dos destaques' : 'Agora é um dos brabos ⭐'); }

// ── Foto ───────────────────────────────────────────────────
let photoTarget = null;
function pickPhoto(id) { photoTarget = id; $('fileInput').value = ''; $('fileInput').click(); }
$('fileInput').onchange = async e => {
  const file = e.target.files[0]; if (!file || !photoTarget) return;
  toast('Enviando foto…');
  try {
    const blob = await toWebp(file, 1000, .82);
    const path = `${LOJA.slug}/${photoTarget}-${Date.now()}.webp`;
    const { error } = await supa.storage.from('produto-fotos').upload(path, blob, { contentType: 'image/webp', upsert: true });
    if (error) throw error;
    const { data } = supa.storage.from('produto-fotos').getPublicUrl(path);
    await updateProd(photoTarget, { foto_url: data.publicUrl }, 'Foto no ar 📸');
    if ($('modal').classList.contains('open') && $('mFoto')) $('mFoto').innerHTML = `<img src="${esc(data.publicUrl)}" alt="">`;
  } catch (err) { toast('Falhou: ' + (err.message || err)); }
};
function toWebp(file, max, q) {
  return new Promise((res, rej) => {
    const img = new Image();
    img.onload = () => {
      const s = Math.min(1, max / Math.max(img.width, img.height));
      const c = document.createElement('canvas'); c.width = Math.round(img.width * s); c.height = Math.round(img.height * s);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      c.toBlob(b => b ? res(b) : rej(new Error('Não deu pra converter a imagem')), 'image/webp', q);
      URL.revokeObjectURL(img.src);
    };
    img.onerror = () => rej(new Error('Imagem inválida'));
    img.src = URL.createObjectURL(file);
  });
}

// ── Modal de produto ───────────────────────────────────────
function openModal(html) { $('modal').innerHTML = html; $('modal').classList.add('open'); $('modalScrim').classList.add('open'); }
function closeModal() { $('modal').classList.remove('open'); $('modalScrim').classList.remove('open'); }
$('modalScrim').onclick = closeModal;
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeModal(); });

function openProd(id) {
  const p = id ? PRODS.find(x => x.id === id) : { nome: '', descricao: '', preco: '', categoria_id: CATS[0]?.id, disponivel: true, destaque: false, upgrade_para: null, tags: [] };
  const others = PRODS.filter(x => x.id !== id && x.categoria_id === p.categoria_id);
  openModal(`
    <h3>${id ? 'Editar produto' : 'Novo produto'}</h3>
    <div class="modal-grid">
      <div class="lf full"><label>Nome</label><input class="field" id="mNome" value="${esc(p.nome)}"></div>
      <div class="lf full"><label>Ingredientes / descrição</label><textarea class="field" id="mDesc" rows="2" placeholder="Pão, salsicha, milho e alface.">${esc(p.descricao || '')}</textarea><small>Separe por vírgula: o cardápio transforma em ingredientes que o cliente pode tirar.</small></div>
      <div class="lf"><label>Preço (R$)</label><input class="field" id="mPreco" type="number" step="0.01" min="0" value="${p.preco === '' ? '' : Number(p.preco).toFixed(2)}"></div>
      <div class="lf"><label>Categoria</label><select class="field" id="mCat">${CATS.map(c => `<option value="${c.id}" ${c.id === p.categoria_id ? 'selected' : ''}>${esc(c.nome)}</option>`).join('')}</select></div>
      <div class="lf full"><label>⚡ Turbinar para (upsell)</label><select class="field" id="mUp"><option value="">— nenhum —</option>${others.map(o => `<option value="${o.id}" ${o.id === p.upgrade_para ? 'selected' : ''}>${esc(o.nome)} (${fmt(o.preco)})</option>`).join('')}</select><small>O cliente vê "Turbina por + R$ X" na tela desse lanche e na comanda.</small></div>
      <div class="lf full"><label>Selos</label><input class="field" id="mTags" value="${esc((p.tags || []).join(', '))}" placeholder="mais-pedido, favorito, monstro, premium, veggie"></div>
      ${id ? `<div class="lf full"><label>Foto</label><div style="display:flex;gap:12px;align-items:center"><div class="adm-thumb" id="mFoto" style="width:96px;height:72px">${p.foto_url ? `<img src="${esc(p.foto_url)}" alt="">` : 'sem foto'}</div><button class="btn ghost" type="button" onclick="pickPhoto('${id}')">Trocar foto</button></div></div>` : ''}
    </div>
    <div class="modal-foot">
      ${id ? `<button class="btn danger" onclick="deleteProd('${id}')">Excluir</button>` : '<span></span>'}
      <div style="display:flex;gap:10px"><button class="btn ghost" onclick="closeModal()">Cancelar</button><button class="btn" onclick="saveProd(${id ? `'${id}'` : 'null'})">Salvar</button></div>
    </div>`);
  $('mCat').onchange = () => {
    const cat = $('mCat').value;
    $('mUp').innerHTML = '<option value="">— nenhum —</option>' + PRODS.filter(x => x.id !== id && x.categoria_id === cat).map(o => `<option value="${o.id}">${esc(o.nome)} (${fmt(o.preco)})</option>`).join('');
  };
}
async function saveProd(id) {
  const nome = $('mNome').value.trim();
  const preco = Math.round(parseFloat($('mPreco').value.replace(',', '.')) * 100) / 100;
  if (!nome) return toast('Dá um nome pro produto');
  if (!(preco >= 0)) return toast('Preço inválido');
  const row = {
    nome, preco,
    descricao: $('mDesc').value.trim() || null,
    categoria_id: $('mCat').value,
    upgrade_para: $('mUp').value || null,
    tags: $('mTags').value.split(',').map(s => s.trim().toLowerCase()).filter(Boolean),
  };
  let error;
  if (id) ({ error } = await supa.from('produtos').update(row).eq('id', id));
  else ({ error } = await supa.from('produtos').insert({ ...row, loja_id: LOJA.id, ordem: (Math.max(0, ...PRODS.map(p => p.ordem)) + 1) }));
  if (error) return toast('Erro: ' + error.message);
  closeModal(); toast(id ? 'Produto salvo' : 'Produto criado'); loadAdmin();
}
async function deleteProd(id) {
  const p = PRODS.find(x => x.id === id);
  if (!confirm(`Excluir "${p.nome}" do cardápio? Dá pra só marcar como esgotado, se preferir.`)) return;
  const { error } = await supa.from('produtos').delete().eq('id', id);
  if (error) return toast('Erro: ' + error.message);
  closeModal(); toast('Produto excluído'); loadAdmin();
}

// ── Configurações da loja ──────────────────────────────────
function renderLojaForm() {
  const c = LOJA.config || {};
  const h = c.horario || {};
  $('lojaForm').innerHTML = `
    <div class="lf"><label>Taxa de entrega (R$)</label><input class="field" name="taxa_entrega" type="number" step="0.5" min="0" value="${c.taxa_entrega ?? ''}"></div>
    <div class="lf"><label>Frete grátis acima de (R$)</label><input class="field" name="frete_gratis_acima" type="number" step="1" min="0" value="${c.frete_gratis_acima ?? ''}" placeholder="vazio = sem frete grátis"><small>Liga a barra "faltam R$ X pro frete grátis" no cardápio.</small></div>
    <div class="lf"><label>Pedido mínimo (R$)</label><input class="field" name="pedido_minimo" type="number" step="1" min="0" value="${c.pedido_minimo ?? 0}"></div>
    <div class="lf"><label>Abre às</label><input class="field" name="abre" type="time" value="${h.abre || '19:00'}"></div>
    <div class="lf"><label>Fecha às</label><input class="field" name="fecha" type="time" value="${h.fecha || '01:00'}"><small>No modo "Auto" a loja abre e fecha sozinha nesse horário.</small></div>
    <div class="lf"><label>Tempo de entrega</label><input class="field" name="tempo_entrega" value="${esc(c.tempo_entrega || '')}" placeholder="40-60 min"></div>
    <div class="lf"><label>Tempo de retirada</label><input class="field" name="tempo_retirada" value="${esc(c.tempo_retirada || '')}" placeholder="20-30 min"></div>
    <div class="lf"><label>WhatsApp da loja</label><input class="field" name="whatsapp" value="${esc(c.whatsapp || '')}" placeholder="44999999999"></div>
    <div class="lf"><label>Chave PIX</label><input class="field" name="chave_pix" value="${esc(c.chave_pix || '')}" placeholder="celular com +55, CPF, CNPJ, e-mail ou aleatória"><small>Com a chave preenchida, o cliente que escolhe PIX recebe QR Code e copia e cola com o valor do pedido.</small></div>
    <div class="lf" style="grid-column:1/-1"><label>Endereço (retirada)</label><input class="field" name="endereco" value="${esc(c.endereco || '')}"></div>
    <div class="lf-actions"><button class="btn" type="submit">Salvar configurações</button></div>`;
}
$('lojaForm').onsubmit = async e => {
  e.preventDefault();
  const f = Object.fromEntries(new FormData(e.target));
  const num = v => v === '' ? null : Number(v);
  const config = {
    ...(LOJA.config || {}),
    taxa_entrega: num(f.taxa_entrega) ?? 0,
    frete_gratis_acima: num(f.frete_gratis_acima),
    pedido_minimo: num(f.pedido_minimo) ?? 0,
    horario: { abre: f.abre, fecha: f.fecha },
    tempo_entrega: f.tempo_entrega, tempo_retirada: f.tempo_retirada,
    whatsapp: f.whatsapp.replace(/\D/g, '') || null,
    chave_pix: f.chave_pix.trim() || null,
    endereco: f.endereco.trim(),
  };
  const { error } = await supa.from('lojas').update({ config }).eq('id', LOJA.id);
  if (error) return toast('Erro: ' + error.message);
  LOJA.config = config; toast('Configurações salvas ✓');
};

Object.assign(window, { updateAdd, newAdd, deleteAdd, initAdmin, pickPhoto, savePrice, toggleDisp, toggleDest, openProd, saveProd, deleteProd, closeModal, renderLojaForm });
