'use strict';
// Monta o texto da comanda (largura fixa, para bobina de 80mm ou 58mm).

const brl = v => `R$ ${Number(v || 0).toFixed(2).replace('.', ',')}`;
const limpar = t => String(t ?? '').replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();

function criar(largura = 42) {
  const L = Math.max(24, Math.min(56, Number(largura) || 42));
  const linha = (c = '-') => c.repeat(L);
  const centro = t => { t = limpar(t).slice(0, L); const e = Math.floor((L - t.length) / 2); return ' '.repeat(Math.max(0, e)) + t; };

  // quebra em linhas de L colunas; "recuo" vale das linhas seguintes, "primeiro" da primeira
  function quebrar(texto, recuo = '', primeiro = '') {
    const out = [];
    let atual = '';
    const max = L - Math.max(recuo.length, primeiro.length);
    for (const palavra of limpar(texto).split(' ')) {
      for (const parte of palavra.match(new RegExp(`.{1,${max}}`, 'g')) || ['']) {
        if (!atual) atual = (out.length ? recuo : primeiro) + parte;
        else if ((atual + ' ' + parte).length > L) { out.push(atual); atual = recuo + parte; }
        else atual += ' ' + parte;
      }
    }
    if (atual) out.push(atual);
    return out;
  }
  // texto à esquerda + valor à direita na mesma linha
  function par(rotulo, valor) {
    const r = limpar(rotulo), v = limpar(valor);
    if (r.length + v.length + 1 <= L) return [r + ' '.repeat(L - r.length - v.length) + v];
    const q = quebrar(r);
    const ult = q.pop();
    return ult.length + v.length + 1 <= L ? [...q, ult + ' '.repeat(L - ult.length - v.length) + v] : [...q, ult, ' '.repeat(L - v.length) + v];
  }

  // pedido = linha de "pedidos" com itens_pedido(*)
  function comanda(pedido, { loja = 'ADRIANO LANCHES', via = '', viaN = 1, viaTotal = 1 } = {}) {
    const entrega = pedido.tipo_entrega === 'delivery';
    const e = pedido.endereco || {};
    const out = [
      centro(loja.toUpperCase()),
      via ? centro(`VIA ${via.toUpperCase()}${viaTotal > 1 ? ` (${viaN}/${viaTotal})` : ''}`) : '',
      linha('='),
      ...par(`PEDIDO #${String(pedido.numero).padStart(3, '0')}`, new Date(pedido.created_at).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })),
      entrega ? '>> ENTREGA' : '>> RETIRADA NO BALCAO',
      linha(),
      ...quebrar(`Cliente: ${pedido.cliente_nome || '-'}`),
      ...quebrar(`Tel: ${pedido.cliente_telefone || '-'}`),
    ].filter(x => x !== '');
    if (entrega) {
      out.push(...quebrar(`End: ${[e.rua, e.numero].filter(Boolean).join(', ')}${e.bairro ? ' - ' + e.bairro : ''}`, '     '));
      if (e.complemento) out.push(...quebrar(`Compl: ${e.complemento}`, '       '));
      if (pedido.distancia_km != null) out.push(`Dist: ${String(Number(pedido.distancia_km)).replace('.', ',')} km de carro`);
    }
    out.push(linha());
    for (const it of pedido.itens_pedido || []) {
      out.push(...par(`${it.quantidade}x ${it.produto_nome}`, brl(it.subtotal)));
      const adds = (it.adicionais || []).map(a => '+ ' + a.nome).join(', ');
      if (adds) out.push(...quebrar(adds, '   ', '   '));
      if (it.observacao) out.push(...quebrar(`* ${it.observacao}`, '     ', '   '));
    }
    if (pedido.observacoes) { out.push(linha()); out.push(...quebrar(`OBS: ${pedido.observacoes}`)); }
    out.push(linha());
    out.push(...par('Subtotal', brl(pedido.subtotal)));
    if (entrega) out.push(...par('Entrega', Number(pedido.taxa_entrega) ? brl(pedido.taxa_entrega) : 'gratis'));
    if (Number(pedido.desconto) > 0) out.push(...par('Desconto', '- ' + brl(pedido.desconto)));
    out.push(...par('TOTAL', brl(pedido.total)));
    out.push(linha());
    const pag = { pix: 'PIX', dinheiro: 'DINHEIRO', cartao: 'CARTAO' }[pedido.forma_pagamento] || limpar(pedido.forma_pagamento).toUpperCase();
    if (pedido.forma_pagamento === 'pix') out.push(pedido.pago ? 'Pagamento: PIX - JA PAGO' : 'Pagamento: PIX - CONFERIR PAGAMENTO');
    else if (pedido.forma_pagamento === 'dinheiro') {
      out.push(`Pagamento: ${pag}${entrega ? ' NA ENTREGA' : ' NA RETIRADA'}`);
      if (Number(pedido.troco_para) > 0) out.push(...quebrar(`Troco p/ ${brl(pedido.troco_para)} (levar ${brl(Math.max(0, pedido.troco_para - pedido.total))})`));
    } else out.push(`Pagamento: ${pag}${entrega ? ' - LEVAR MAQUININHA' : ' NO BALCAO'}`);
    return out.map(l => l.slice(0, L)).join('\n');
  }

  // os itens já chegaram todos? (o pedido entra antes dos itens no banco)
  function itensProntos(p) {
    const itens = p?.itens_pedido || [];
    if (!itens.length) return false;
    const soma = itens.reduce((n, i) => n + Number(i.subtotal || 0), 0);
    return Math.abs(soma - Number(p.subtotal || 0)) < 0.03;
  }
  return { comanda, itensProntos, largura: L };
}

module.exports = { criar };
