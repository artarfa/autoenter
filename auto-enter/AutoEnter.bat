@echo off
rem Double-click to start. Extra arguments are passed through, e.g.:
rem   AutoEnter.bat -MinSeconds 30 -MaxSeconds 40 -StartDelay 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AutoEnter.ps1" %*
pause
