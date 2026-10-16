@echo off
title Teste de impressao - Adriano Lanches
cd /d "%~dp0"
echo Imprimindo um pedido de teste (2 vias)...
node.exe index.js --teste
echo.
pause
