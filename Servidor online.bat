@echo off
rem Arranca el servidor dedicado de Rumbang en este PC (y el tunel para jugar por internet).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\online\servidor_online.ps1"
pause
