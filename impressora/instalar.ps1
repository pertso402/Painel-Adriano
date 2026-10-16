# Instala a impressora automática da Adriano Lanches para iniciar junto com o Windows.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) { throw 'Instale o Node.js LTS (nodejs.org) e abra um novo PowerShell.' }
if (-not (Test-Path .\config.json)) { Copy-Item .\config.example.json .\config.json; throw 'Criei o config.json: preencha a senha (ADL# + PIN do painel) e rode de novo.' }
npm.cmd install --omit=dev
if ($LASTEXITCODE -ne 0) { throw 'Falha ao instalar as dependencias.' }
$nome = 'Adriano Lanches - Impressao automatica'
$acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSScriptRoot + '\iniciar.ps1"') -WorkingDirectory $PSScriptRoot
$gatilho = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$ajustes = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1)
$quem = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $nome -Action $acao -Trigger $gatilho -Settings $ajustes -Principal $quem -Force | Out-Null
Start-ScheduledTask -TaskName $nome
Write-Host "Pronto. A impressora automatica esta rodando e volta sozinha quando o Windows ligar."
Write-Host "Acompanhe em $PSScriptRoot\monitor.log"
