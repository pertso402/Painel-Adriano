# Liga a impressora automática e religa sozinho se ela cair (ex.: internet caiu, impressora desligada).
Set-Location $PSScriptRoot
while ($true) {
  if ((Test-Path .\monitor.log) -and (Get-Item .\monitor.log).Length -gt 5MB) { Move-Item .\monitor.log .\monitor.old.log -Force }
  & node.exe .\index.js *>> .\monitor.log
  if ($LASTEXITCODE -eq 3) { break }  # já tem uma rodando
  Start-Sleep -Seconds 15
}
