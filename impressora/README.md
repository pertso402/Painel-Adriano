# Impressora automática — Adriano Lanches

Programa que fica rodando no computador do balcão e imprime sozinho cada pedido que chega no painel.

- **Cada via é um trabalho separado** na impressora (Cozinha e Entrega), cada uma cortada no seu papel — nunca duas comandas emendadas.
- **Nunca imprime em dobro**: marca `pedidos.impresso_em` no banco (mesmo reiniciando o computador).
- **PIX só imprime depois de conferido** no painel (botão "PIX conferido"), para a cozinha não fazer pedido não pago.
- **Liga sozinho com o Windows** e religa sozinho se cair.
- O painel mostra **"Impressora ligada"** (verde) ou **"Impressora desligada"** (vermelho).

## Instalar (uma vez, no computador da impressora)

1. Copie a pasta `impressora` para o computador (ex.: `C:\AdrianoImpressora`). Pode ser pelo pen drive ou pelo arquivo `impressora-adriano.zip` (botão direito → Extrair tudo).
2. Dê **dois cliques em `INSTALAR.cmd`**. Se o Windows avisar, clique em **Mais informações → Executar assim mesmo**.
3. Responda o que ele perguntar:
   - **PIN do painel** (o mesmo de entrar no painel);
   - **número da impressora** térmica na lista;
   - se as **2 comandas de teste** saíram separadas.
4. Pronto. Ele instala o que faltar (inclusive o Node.js), desliga o programa antigo e passa a ligar junto com o Windows.

Pode rodar o `INSTALAR.cmd` de novo a qualquer momento (trocar a impressora, mudou o PIN, etc.).

## Outros atalhos

| Arquivo | Para que serve |
|---|---|
| `TESTAR IMPRESSAO.cmd` | Imprime um pedido de exemplo (2 vias) |
| `DESINSTALAR.cmd` | Para e tira da inicialização do Windows |
| `monitor.log` | Registro do que aconteceu (abre no Bloco de Notas) |

## config.json (o instalador preenche)

| Campo | O que é |
|---|---|
| `vias` | Quais vias imprimir, na ordem. Padrão `["Cozinha", "Entrega"]`. Só uma: `["Cozinha"]`. |
| `imprimirPix` | `"conferido"` (padrão) imprime PIX depois do "PIX conferido"; `"na-hora"` imprime assim que entra. |
| `modo` | `"windows"` (padrão) imprime pelo driver; `"escpos"` manda o comando de corte direto para a térmica. |
| `lineWidth` | Colunas da comanda: `42` para bobina 80 mm, `32` para 58 mm. |
| `fonteTamanho` | Tamanho da letra no modo `windows` (padrão 9). |

## Se as vias saírem sem corte entre elas

O instalador já tenta o modo `escpos` quando você responde que não saíram separadas. Se mesmo assim não cortar: Impressoras → (sua térmica) → Preferências de impressão → **"Cortar papel"** no **fim do documento**. Depois rode o `TESTAR IMPRESSAO.cmd`.

## O painel mostra "Impressora desligada"

O computador do balcão está desligado, sem internet ou o programa foi fechado. Ligue o computador (o programa volta sozinho) ou dê dois cliques no `INSTALAR.cmd` de novo. Passe o mouse no aviso para ver a última vez que ela deu sinal.
