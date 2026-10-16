# Serviço de impressão: fica aberto e recebe, por linha, {"id","arquivo","nome"}.
# Cada linha recebida vira UM trabalho separado no spooler do Windows.
#   -Modo windows : imprime pelo driver (papel do tamanho exato da comanda)
#   -Modo escpos  : manda bytes ESC/POS crus com CORTE no fim (impressoras térmicas)
param([string]$NomeImpressora = '', [string]$Modo = 'windows', [int]$Fonte = 9)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Drawing

if ([string]::IsNullOrWhiteSpace($NomeImpressora)) {
  $padrao = Get-CimInstance Win32_Printer | Where-Object { $_.Default } | Select-Object -First 1
  if (-not $padrao) { throw 'Nenhuma impressora padrao no Windows.' }
  $NomeImpressora = $padrao.Name
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ImpressoraCrua {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public class DOCINFO { public string pDocName; public string pOutputFile; public string pDataType; }
  [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool OpenPrinter(string n, out IntPtr h, IntPtr d);
  [DllImport("winspool.drv", SetLastError = true)] static extern bool ClosePrinter(IntPtr h);
  [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)] static extern int StartDocPrinter(IntPtr h, int level, [In] DOCINFO di);
  [DllImport("winspool.drv", SetLastError = true)] static extern bool EndDocPrinter(IntPtr h);
  [DllImport("winspool.drv", SetLastError = true)] static extern bool StartPagePrinter(IntPtr h);
  [DllImport("winspool.drv", SetLastError = true)] static extern bool EndPagePrinter(IntPtr h);
  [DllImport("winspool.drv", SetLastError = true)] static extern bool WritePrinter(IntPtr h, byte[] b, int n, out int w);
  public static void Enviar(string impressora, string nome, byte[] dados) {
    IntPtr h;
    if (!OpenPrinter(impressora, out h, IntPtr.Zero)) throw new Exception("Nao abri a impressora " + impressora);
    try {
      if (StartDocPrinter(h, 1, new DOCINFO { pDocName = nome, pDataType = "RAW" }) == 0) throw new Exception("Spooler recusou o trabalho");
      try { StartPagePrinter(h); int w; WritePrinter(h, dados, dados.Length, out w); EndPagePrinter(h); }
      finally { EndDocPrinter(h); }
    } finally { ClosePrinter(h); }
  }
}
'@

function Via-Windows([string]$Arquivo, [string]$Nome) {
  $script:linhas = [System.IO.File]::ReadAllLines($Arquivo, [System.Text.Encoding]::UTF8)
  $doc = New-Object System.Drawing.Printing.PrintDocument
  $doc.PrinterSettings.PrinterName = $NomeImpressora
  if (-not $doc.PrinterSettings.IsValid) { throw "Impressora nao encontrada: $NomeImpressora" }
  $doc.DocumentName = $Nome
  $doc.PrintController = New-Object System.Drawing.Printing.StandardPrintController
  $doc.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(4, 4, 4, 4)
  $script:letra = New-Object System.Drawing.Font('Consolas', $Fonte, [System.Drawing.FontStyle]::Regular)
  $script:letraForte = New-Object System.Drawing.Font('Consolas', $Fonte, [System.Drawing.FontStyle]::Bold)
  # papel do tamanho exato da comanda (centésimos de polegada): nada de quebrar em duas folhas
  $largura = $doc.DefaultPageSettings.PaperSize.Width
  $alturaLinha = $Fonte * 1.6
  $altura = [int][Math]::Ceiling(($script:linhas.Length + 6) * $alturaLinha * 100 / 72) + 40
  try { $doc.DefaultPageSettings.PaperSize = New-Object System.Drawing.Printing.PaperSize('Comanda', $largura, [Math]::Max($altura, 300)) } catch {}
  $script:i = 0
  $acao = [System.Drawing.Printing.PrintPageEventHandler]{
    param($s, $e)
    $h = $script:letra.GetHeight($e.Graphics) * 1.15
    $colunas = ($script:linhas | Measure-Object -Property Length -Maximum).Maximum
    $lw = $e.Graphics.MeasureString(('W' * [Math]::Max(1, $colunas)), $script:letra).Width
    $esc = [Math]::Min(1.0, $e.MarginBounds.Width / [Math]::Max(1, $lw))
    $e.Graphics.TranslateTransform($e.MarginBounds.Left, $e.MarginBounds.Top)
    $e.Graphics.ScaleTransform($esc, $esc)
    $y = 0.0; $max = $e.MarginBounds.Height / $esc
    while ($script:i -lt $script:linhas.Length -and $y + $h -le $max) {
      $l = $script:linhas[$script:i]
      $f = if ($script:i -lt 2 -or $l -match '^(PEDIDO|TOTAL|>>)') { $script:letraForte } else { $script:letra }
      $e.Graphics.DrawString($l, $f, [System.Drawing.Brushes]::Black, 0, [single]$y)
      $y += $h; $script:i++
    }
    $e.HasMorePages = $script:i -lt $script:linhas.Length
  }
  $doc.add_PrintPage($acao)
  try { $doc.Print() } finally { $doc.remove_PrintPage($acao); $script:letra.Dispose(); $script:letraForte.Dispose(); $doc.Dispose() }
}

function Via-EscPos([string]$Arquivo, [string]$Nome) {
  $texto = [System.IO.File]::ReadAllText($Arquivo, [System.Text.Encoding]::UTF8) -replace "`r", ''
  $cp = [System.Text.Encoding]::GetEncoding(850)
  $bytes = New-Object System.Collections.Generic.List[byte]
  $bytes.AddRange([byte[]](0x1B, 0x40, 0x1B, 0x74, 0x02))           # inicia + tabela de acentos (CP850)
  $n = 0
  foreach ($l in $texto.Split("`n")) {
    $forte = $n -lt 2 -or $l -match '^(PEDIDO|TOTAL|>>)'
    if ($forte) { $bytes.AddRange([byte[]](0x1B, 0x45, 0x01)) }   # negrito
    $bytes.AddRange($cp.GetBytes($l + "`n"))
    if ($forte) { $bytes.AddRange([byte[]](0x1B, 0x45, 0x00)) }
    $n++
  }
  $bytes.AddRange([byte[]](0x1B, 0x64, 0x05, 0x1D, 0x56, 0x42, 0x00)) # avança 5 linhas e CORTA
  [ImpressoraCrua]::Enviar($NomeImpressora, $Nome, $bytes.ToArray())
}

[Console]::Out.WriteLine("READY $NomeImpressora"); [Console]::Out.Flush()
while ($null -ne ($linha = [Console]::In.ReadLine())) {
  if (-not $linha.Trim()) { continue }
  $job = $null
  try {
    $job = $linha | ConvertFrom-Json
    if ($Modo -eq 'escpos') { Via-EscPos $job.arquivo $job.nome } else { Via-Windows $job.arquivo $job.nome }
    [Console]::Out.WriteLine((@{ id = $job.id; ok = $true } | ConvertTo-Json -Compress))
  } catch {
    [Console]::Out.WriteLine((@{ id = $job.id; ok = $false; erro = ($_.Exception.Message -replace '[\r\n]+', ' ') } | ConvertTo-Json -Compress))
  }
  [Console]::Out.Flush()
}
