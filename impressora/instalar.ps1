# Instalador da impressora automática - Adriano Lanches.
# Rode pelo INSTALAR.cmd (dois cliques). Pode rodar de novo quantas vezes quiser.
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
$Host.UI.RawUI.WindowTitle = 'Instalar impressora automatica - Adriano Lanches'
function Passo($t) { Write-Host ''; Write-Host "==> $t" -ForegroundColor Yellow }
function Ok($t) { Write-Host "    OK: $t" -ForegroundColor Green }
function Falha($t) { Write-Host ''; Write-Host "PROBLEMA: $t" -ForegroundColor Red; exit 1 }
function AtualizarPath { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') }
$cfgPath = Join-Path $PSScriptRoot 'config.json'
function Salvar { [IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false))) }
function PararRodando {
  $pais = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$PSScriptRoot\iniciar.ps1*" }
  foreach ($p in $pais) {
    $filhos = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.ProcessId)"
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    foreach ($f in $filhos) { Stop-Process -Id $f.ProcessId -Force -ErrorAction SilentlyContinue }
  }
}

Write-Host 'IMPRESSORA AUTOMATICA - ADRIANO LANCHES' -ForegroundColor Cyan
Write-Host 'Cada pedido sai sozinho na impressora: via da cozinha e via da entrega, cada uma no seu papel.'
Get-ChildItem $PSScriptRoot -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

# 1. Node.js -------------------------------------------------------------
Passo '1/6  Node.js'
if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
  if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
    Write-Host '    Node.js nao encontrado. Instalando agora (se o Windows pedir permissao, clique em Sim)...'
    winget.exe install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
    AtualizarPath
  }
  if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    Start-Process 'https://nodejs.org/pt-br/download'
    Falha 'Instale o Node.js LTS pelo site que abriu (Avancar, Avancar, Concluir) e de dois cliques no INSTALAR.cmd de novo.'
  }
}
Ok ('Node.js ' + (& node.exe -v))

# 2. Componentes ---------------------------------------------------------
Passo '2/6  Componentes'
& npm.cmd install --omit=dev --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { Falha 'Nao consegui baixar os componentes. Confira a internet e rode o INSTALAR.cmd de novo.' }
Ok 'componentes instalados'

# 3. Login da loja -------------------------------------------------------
Passo '3/6  Conectar na loja'
if (-not (Test-Path $cfgPath)) { Copy-Item (Join-Path $PSScriptRoot 'config.example.json') $cfgPath }
$cfg = [IO.File]::ReadAllText($cfgPath).TrimStart([char]0xFEFF) | ConvertFrom-Json
$tentativas = 0
while ($true) {
  if ($cfg.senha -and $cfg.senha -notmatch '<') {
    $saida = (& node.exe .\index.js --checar 2>&1 | Out-String)
    if ($LASTEXITCODE -eq 0) { break }
    if ($saida -match 'Invalid login') { Write-Host '    PIN nao confere.' -ForegroundColor Red }
    else { Write-Host ('    Nao consegui conectar: ' + ($saida -replace '\s+', ' ').Trim()) -ForegroundColor Red }
  }
  $tentativas++
  if ($tentativas -gt 5) { Falha 'Nao consegui entrar na loja. Confira a internet e o PIN do painel.' }
  $pin = Read-Host '    Digite o PIN do painel (o mesmo que voce usa para entrar no painel)'
  $cfg.senha = 'ADL#' + $pin.Trim()
  Salvar
}
Ok 'loja conectada'

# 4. Impressora ----------------------------------------------------------
Passo '4/6  Impressora'
$lista = @(Get-CimInstance Win32_Printer | Sort-Object @{ e = { -not $_.Default } }, Name)
if (-not $lista.Count) { Falha 'Nenhuma impressora instalada no Windows. Instale a impressora termica e rode o INSTALAR.cmd de novo.' }
for ($i = 0; $i -lt $lista.Count; $i++) {
  $marca = if ($lista[$i].Default) { '   <- padrao do Windows' } else { '' }
  Write-Host ('    [{0}] {1}{2}' -f ($i + 1), $lista[$i].Name, $marca)
}
$atual = if ($cfg.printerName -and ($lista.Name -contains $cfg.printerName)) { $cfg.printerName } else { $lista[0].Name }
$r = Read-Host "    Numero da impressora termica (Enter = $atual)"
if ($r -match '^\d+$' -and [int]$r -ge 1 -and [int]$r -le $lista.Count) { $cfg.printerName = $lista[[int]$r - 1].Name } else { $cfg.printerName = $atual }
Salvar
Ok "impressora: $($cfg.printerName)"

# 5. Ligar junto com o Windows ------------------------------------------
Passo '5/6  Ligar sozinho junto com o Windows'
foreach ($antiga in 'Restaurante - Impressao automatica de pedidos', 'Adriano Lanches - Impressao automatica') {
  if (Get-ScheduledTask -TaskName $antiga -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $antiga -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $antiga -Confirm:$false -ErrorAction SilentlyContinue
    Ok "desliguei o programa antigo ($antiga)"
  }
}
PararRodando
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$argumentos = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'iniciar.ps1') + '"'
$atalho = Join-Path ([Environment]::GetFolderPath('Startup')) 'Impressora Adriano Lanches.lnk'
$sc = (New-Object -ComObject WScript.Shell).CreateShortcut($atalho)
$sc.TargetPath = $ps; $sc.Arguments = $argumentos; $sc.WorkingDirectory = $PSScriptRoot; $sc.WindowStyle = 7
$sc.Description = 'Imprime sozinho os pedidos do Adriano Lanches'
$sc.Save()
Ok 'vai ligar sozinho sempre que o Windows iniciar'

# 6. Teste ---------------------------------------------------------------
Passo '6/6  Teste de impressao'
Write-Host '    Imprimindo um pedido de teste (2 vias)...'
& node.exe .\index.js --teste
$r = Read-Host '    Sairam 2 comandas, cada uma no seu papel? (S/n)'
if ($r -match '^[nN]') {
  $cfg.modo = 'escpos'; Salvar
  Write-Host '    Vou tentar o modo de corte direto da impressora termica...'
  & node.exe .\index.js --teste
  $r = Read-Host '    E agora, sairam separadas? (S/n)'
  if ($r -match '^[nN]') {
    $cfg.modo = 'windows'; Salvar
    Write-Host '    Voltei ao modo normal. Abra Impressoras > (sua termica) > Preferencias de impressao' -ForegroundColor Yellow
    Write-Host '    e ligue "Cortar papel" no fim do documento. Depois rode o TESTAR IMPRESSAO.cmd.' -ForegroundColor Yellow
  }
}

$linhasAntes = if (Test-Path .\monitor.log) { @(Get-Content .\monitor.log).Count } else { 0 }
Start-Process -FilePath $ps -ArgumentList $argumentos -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
Write-Host '    Ligando...'
$ligou = $false
for ($i = 0; $i -lt 20 -and -not $ligou; $i++) {
  Start-Sleep -Seconds 1
  if (Test-Path .\monitor.log) { $ligou = $null -ne (Get-Content .\monitor.log -ErrorAction SilentlyContinue | Select-Object -Skip $linhasAntes | Select-String 'Monitorando') }
}
Write-Host ''
if ($ligou) {
  Write-Host 'PRONTO! A impressora automatica esta ligada.' -ForegroundColor Green
  Write-Host 'No painel aparece "Impressora ligada". Pode fechar esta janela.'
} else {
  Write-Host 'Instalado, mas ainda nao confirmei que ligou. Veja o painel em 1 minuto ("Impressora ligada")' -ForegroundColor Yellow
  Write-Host "ou abra o arquivo $PSScriptRoot\monitor.log."
}
