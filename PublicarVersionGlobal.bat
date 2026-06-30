@echo off
:: =====================================================
::  PUBLICAR VERSION GLOBAL - Skeledex (SOLO DEVELOPER)
::  Empaqueta y publica una nueva version a TODAS las
::  instalaciones via el canal central (GitHub).
:: =====================================================
cd /d "%~dp0"
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PublicarVersionGlobal.ps1"
pause
