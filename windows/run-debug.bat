@echo off
cd /d "%~dp0"
REM Igual ao run.bat, mas mantem a janela aberta mostrando logs/erros.
call .venv\Scripts\activate.bat
python vox.py
pause
