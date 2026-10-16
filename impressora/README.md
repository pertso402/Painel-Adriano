# Impressora automática — Adriano Lanches

Programa que fica rodando no notebook do balcão e imprime sozinho cada pedido que chega no painel.

- **Cada via é um trabalho separado** na impressora (Cozinha e Entrega), cada uma cortada no seu papel — nunca duas comandas emendadas.
- **Nunca imprime em dobro**: marca `pedidos.impresso_em` no banco (mesmo reiniciando o notebook).
- **PIX só imprime depois de conferido** no painel (botão "PIX conferido"), para a cozinha não fazer pedido não pago.
- Mostra adicionais, observação de cada item, endereço completo, distância, troco e forma de pagamento.

## Instalar (uma vez)

1. Instale o **Node.js LTS** (https://nodejs.org) no notebook.
2. Copie esta pasta `impressora` para o notebook (ex.: `C:\AdrianoImpressora`).
3. Copie `config.example.json` para `config.json` e preencha:
   - `senha`: `ADL#` + o PIN do painel (ex.: PIN 1234 → `ADL#1234`).
   - `printerName`: nome exato da impressora como aparece no Windows (vazio = impressora padrão).
4. Se o programa antigo de impressão estiver instalado, **desative-o** (senão sai em dobro):
   Agendador de Tarefas → apague a tarefa `Restaurante - Impressao automatica de pedidos`.
5. Clique com o botão direito em `instalar.ps1` → **Executar com o PowerShell**.
   Ele instala as dependências e cria a tarefa `Adriano Lanches - Impressao automatica`, que liga junto com o Windows.
6. Teste: abra o PowerShell na pasta e rode `npm run teste` — devem sair **2 papéis separados**.

O registro do que aconteceu fica em `monitor.log`.

## config.json

| Campo | O que é |
|---|---|
| `vias` | Quais vias imprimir, na ordem. Padrão `["Cozinha", "Entrega"]`. Só uma: `["Cozinha"]`. |
| `imprimirPix` | `"conferido"` (padrão) imprime PIX depois do "PIX conferido"; `"na-hora"` imprime assim que entra. |
| `modo` | `"windows"` (padrão) imprime pelo driver; `"escpos"` manda comando de corte direto para a térmica. |
| `lineWidth` | Colunas da comanda: `42` para bobina 80 mm, `32` para 58 mm. |
| `fonteTamanho` | Tamanho da letra no modo `windows` (padrão 9). |

## Se as vias saírem sem corte entre elas

1. No Windows: Impressoras → (sua térmica) → Preferências de impressão → procure **"Cortar papel"/"Paper cut"** e escolha **"no fim do documento"** (não "no fim do trabalho"/"desativado").
2. Se o driver não tiver essa opção, troque `"modo": "escpos"` no `config.json` (funciona com Epson, Elgin, Bematech, Daruma, Tanca e genéricas ESC/POS). Reinicie o notebook ou a tarefa.

## Parar / remover

- Parar agora: Agendador de Tarefas → `Adriano Lanches - Impressao automatica` → Finalizar.
- Remover: botão direito em `desinstalar.ps1` → Executar com o PowerShell.
