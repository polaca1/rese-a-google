@echo off
powershell.exe -NoProfile -Command "Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0Configurar.ps1\"'"
