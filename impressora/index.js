'use strict';
// ═══════════════════════════════════════════════════════════
//  IMPRESSORA AUTOMÁTICA — Adriano Lanches
//  Acompanha os pedidos da loja no Supabase e imprime cada via
//  como um trabalho SEPARADO na impressora do Windows (uma
//  comanda por papel). Marca pedidos.impresso_em para nunca
//  imprimir em dobro, mesmo depois de reiniciar o notebook.
//  Uso: node index.js           (monitorar)
//       node index.js --teste   (imprime uma comanda de exemplo)
// ═══════════════════════════════════════════════════════════
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const net = require('node:net');
const { spawn } = require('node:child_process');
const { createClient } = require('@supabase/supabase-js');

const CONFIG = path.join(__dirname, 'config.json');
if (!fs.existsSync(CONFIG)) { console.error('Falta o config.json (copie o config.example.json e preencha).'); process.exit(1); }
const cfg = JSON.parse(fs.readFileSync(CONFIG, 'utf8'));
const VIAS = Array.isArray(cfg.vias) && cfg.vias.length ? cfg.vias : ['Cozinha', 'Entrega'];
const MODO = cfg.modo === 'escpos' ? 'escpos' : 'windows';
const PIX_NA_HORA = cfg.imprimirPix === 'na-hora';
const { comanda, itensProntos } = require('./comanda').criar(cfg.lineWidth || 42);
const ESTADO = path.join(__dirname, 'impressoes.json');

const sb = createClient(cfg.supabaseUrl, cfg.publishableKey, { auth: { persistSession: false, autoRefreshToken: true } });
let LOJA = null;
let estado = { impressos: {} };
const emAndamento = new Set();
const esperar = new Map(); // id → não tentar antes de (ms)

const log = (...a) => console.log(new Date().toLocaleString('pt-BR'), ...a);
const dormir = ms => new Promise(r => setTimeout(r, ms));
function guardar() {
  const limite = Date.now() - 7 * 864e5;
  for (const [id, t] of Object.entries(estado.impressos)) if (Date.parse(t) < limite) delete estado.impressos[id];
  fs.writeFileSync(ESTADO + '.tmp', JSON.stringify(estado, null, 2)); fs.renameSync(ESTADO + '.tmp', ESTADO);
}

// ── Serviço de impressão (PowerShell fica aberto e recebe um trabalho por linha) ──
let ps = null, pronto = null, buf = '', seq = 0;
const respostas = new Map();
function servico() {
  if (pronto) return pronto;
  pronto = new Promise((resolve, reject) => {
    const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(__dirname, 'imprimir-servidor.ps1'), '-Modo', MODO, '-Fonte', String(cfg.fonteTamanho || 9)];
    if (cfg.printerName) args.push('-NomeImpressora', cfg.printerName);
    ps = spawn('powershell.exe', args, { windowsHide: true });
    const t = setTimeout(() => reject(new Error('A impressora não respondeu ao iniciar.')), 20000);
    ps.stdout.setEncoding('utf8');
    ps.stdout.on('data', d => {
      buf += d; const linhas = buf.split(/\r?\n/); buf = linhas.pop() || '';
      for (const l of linhas) {
        if (!l.trim()) continue;
        if (l.trim().startsWith('READY')) { clearTimeout(t); log('Impressora pronta:', l.trim().slice(6) || '(padrão)', `· modo ${MODO}`); resolve(); continue; }
        try { const r = JSON.parse(l); const w = respostas.get(r.id); if (w) { respostas.delete(r.id); r.ok ? w.resolve() : w.reject(new Error(r.erro || 'Falha ao imprimir')); } }
        catch { log('Impressora disse:', l); }
      }
    });
    ps.stderr.setEncoding('utf8');
    ps.stderr.on('data', d => log('Impressora (erro):', d.trim()));
    ps.on('error', e => { clearTimeout(t); reject(e); });
    ps.on('close', code => {
      clearTimeout(t);
      for (const w of respostas.values()) w.reject(new Error(`Serviço de impressão fechou (${code})`));
      respostas.clear(); ps = null; pronto = null;
      log(`Serviço de impressão fechou (código ${code}); reabre no próximo pedido.`);
    });
  });
  return pronto;
}
// uma via = um arquivo = um trabalho no spooler (o driver corta no fim de cada um)
async function imprimirVia(texto, nome) {
  const arquivo = path.join(os.tmpdir(), `adriano-${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2)}.txt`);
  fs.writeFileSync(arquivo, texto, 'utf8');
  try {
    await servico();
    const id = String(++seq);
    await new Promise((resolve, reject) => {
      const t = setTimeout(() => { respostas.delete(id); reject(new Error('A impressora demorou demais para aceitar a comanda')); }, 60000);
      respostas.set(id, { resolve: () => { clearTimeout(t); resolve(); }, reject: e => { clearTimeout(t); reject(e); } });
      ps.stdin.write(JSON.stringify({ id, arquivo, nome }) + '\n');
    });
  } finally { fs.rmSync(arquivo, { force: true }); }
}
async function imprimirPedido(p) {
  for (let i = 0; i < VIAS.length; i++) {
    await imprimirVia(comanda(p, { loja: cfg.nomeLoja || 'Adriano Lanches', via: VIAS[i], viaN: i + 1, viaTotal: VIAS.length }), `Pedido #${p.numero} - via ${VIAS[i]}`);
    if (i < VIAS.length - 1) await dormir(1500); // respiro entre as vias: cada uma sai cortada
  }
}

// ── Pedidos ────────────────────────────────────────────────
const deveImprimir = p => p && p.status !== 'cancelado' && !p.impresso_em
  && (p.forma_pagamento !== 'pix' || p.pago || PIX_NA_HORA);
async function buscar(id) {
  const { data, error } = await sb.from('pedidos').select('*, itens_pedido(*)').eq('id', id).single();
  if (error) throw error;
  return data;
}
async function processar(id) {
  if (emAndamento.has(id) || estado.impressos[id] || Date.now() < (esperar.get(id) || 0)) return;
  emAndamento.add(id);
  try {
    const p = await buscar(id);
    if (!deveImprimir(p)) return;
    if (!itensProntos(p)) { esperar.set(id, Date.now() + 1500); setTimeout(() => processar(id), 1600); return; }
    await imprimirPedido(p);
    estado.impressos[id] = new Date().toISOString(); guardar();
    const { error } = await sb.from('pedidos').update({ impresso_em: estado.impressos[id] }).eq('id', id);
    if (error) log(`Pedido #${p.numero}: impresso, mas não marquei no banco (${error.message}).`);
    log(`Pedido #${p.numero} impresso (${VIAS.length} via${VIAS.length > 1 ? 's' : ''}).`);
  } catch (e) {
    esperar.set(id, Date.now() + 30000);
    log(`Falha no pedido ${id}: ${e.message}. Tento de novo em 30s.`);
  } finally { emAndamento.delete(id); }
}
// rede de segurança: pega o que o tempo real perder (ex.: internet caiu)
async function varrer() {
  try {
    const desde = new Date(Date.now() - 6 * 3600e3).toISOString();
    const { data, error } = await sb.from('pedidos').select('id').eq('loja_id', LOJA.id).is('impresso_em', null).neq('status', 'cancelado').gte('created_at', desde).order('created_at');
    if (error) throw error;
    for (const { id } of data || []) await processar(id);
  } catch (e) { log('Varredura falhou:', e.message); }
}

async function entrar() {
  const { error } = await sb.auth.signInWithPassword({ email: cfg.email, password: cfg.senha });
  if (error) throw new Error('Login da loja falhou: confira email e senha no config.json (' + error.message + ')');
  const { data, error: e2 } = await sb.from('lojas').select('id, nome').eq('slug', cfg.lojaSlug).single();
  if (e2 || !data) throw new Error('Loja não encontrada: ' + (cfg.lojaSlug || '(sem lojaSlug)'));
  LOJA = data;
  log(`Conectado à loja ${LOJA.nome}.`);
}

async function iniciar() {
  if (process.platform !== 'win32') throw new Error('Rode no notebook Windows com a impressora instalada.');
  const trava = net.createServer();
  await new Promise((res, rej) => { trava.once('error', () => rej(new Error('A impressora automática já está rodando neste notebook.'))); trava.listen(47685, '127.0.0.1', res); });
  if (fs.existsSync(ESTADO)) estado = JSON.parse(fs.readFileSync(ESTADO, 'utf8'));
  await servico();
  await entrar();
  sb.channel('impressora-' + LOJA.id)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'pedidos', filter: `loja_id=eq.${LOJA.id}` }, ({ new: p }) => setTimeout(() => processar(p.id), 800))
    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'pedidos', filter: `loja_id=eq.${LOJA.id}` }, ({ new: p }) => { if (deveImprimir(p)) processar(p.id); })
    .subscribe(s => log('Tempo real:', s));
  await varrer();
  setInterval(varrer, 15000);
  log(`Monitorando pedidos · ${VIAS.length} via(s): ${VIAS.join(' + ')} · PIX imprime ${PIX_NA_HORA ? 'na hora' : 'depois de conferido'}.`);
}

async function teste() {
  const exemplo = {
    numero: 999, created_at: new Date().toISOString(), tipo_entrega: 'delivery', cliente_nome: 'Cliente Teste', cliente_telefone: '(44) 99999-0000',
    endereco: { rua: 'Rua Exemplo', numero: '123', bairro: 'Zona III', complemento: 'Casa dos fundos' }, distancia_km: 3.4,
    itens_pedido: [
      { quantidade: 2, produto_nome: 'Especial Big', subtotal: 98, adicionais: [{ nome: 'Bacon' }], observacao: 'SEM milho' },
      { quantidade: 1, produto_nome: 'Coca-Cola Lata 350ml', subtotal: 7, adicionais: [] },
    ],
    observacoes: 'Interfone quebrado, ligar quando chegar', subtotal: 105, taxa_entrega: 8, total: 113, forma_pagamento: 'dinheiro', troco_para: 150,
  };
  await servico();
  await imprimirPedido(exemplo);
  log(`Teste enviado: ${VIAS.length} comanda(s) separada(s).`);
  process.exit(0);
}

if (require.main === module) {
  (process.argv.includes('--teste') ? teste() : iniciar()).catch(e => { console.error('Não iniciou:', e.message); process.exit(1); });
}
module.exports = { deveImprimir };
