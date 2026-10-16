$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
node.exe .\index.js *>> .\monitor.log
