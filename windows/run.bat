@echo off
cd /d "%~dp0"
if not exist ".venv\Scripts\pythonw.exe" (
    echo Ambiente nao encontrado. Rode setup.bat primeiro.
    pause
    exit /b 1
)
REM pythonw = roda sem janela de console (so o icone na bandeja).
start "" ".venv\Scripts\pythonw.exe" vox.py
