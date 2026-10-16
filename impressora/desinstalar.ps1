$nome = 'Adriano Lanches - Impressao automatica'
Stop-ScheduledTask -TaskName $nome -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $nome -Confirm:$false -ErrorAction SilentlyContinue
# encerra o iniciar.ps1 e o node que ele abriu
$pais = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$PSScriptRoot\iniciar.ps1*" }
foreach ($p in $pais) {
  Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.ProcessId)" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}
Write-Host 'Impressora automatica removida.'
