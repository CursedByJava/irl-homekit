@echo off
rem Double-click to install (or update) IRL Homekit.
rem Windows asks for administrator permission, then the installer asks you a few questions.
title IRL Homekit installer
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
