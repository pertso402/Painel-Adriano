# Remove a impressora automática (não liga mais com o Windows e para a que está rodando).
Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'Impressora Adriano Lanches.lnk') -Force -ErrorAction SilentlyContinue
foreach ($t in 'Adriano Lanches - Impressao automatica', 'Restaurante - Impressao automatica de pedidos') {
  Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
}
$pais = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$PSScriptRoot\iniciar.ps1*" }
foreach ($p in $pais) {
  $filhos = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.ProcessId)"
  Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  foreach ($f in $filhos) { Stop-Process -Id $f.ProcessId -Force -ErrorAction SilentlyContinue }
}
Write-Host 'Impressora automatica removida. Ela nao liga mais com o Windows.' -ForegroundColor Green
