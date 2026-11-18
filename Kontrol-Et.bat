@echo off
rem PC Saglik Kontrolu - yonetici olarak calistirir
set "SCRIPT=%~dp0PC-Saglik-Kontrol.ps1"
if not exist "%SCRIPT%" (
  echo PC-Saglik-Kontrol.ps1 bulunamadi. Iki dosyayi ayni klasore koy.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('\"' + $env:SCRIPT + '\"'))"
