@echo off
cd /d "%~dp0"
start "" "%~dp0AIDefense.exe" --main-pack "%~dp0AIDefense.pck" -- --single --windowed
