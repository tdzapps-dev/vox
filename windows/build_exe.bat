@echo off
REM (Opcional / avancado) Gera um Vox.exe portatil com PyInstaller.
REM O modelo de voz NAO vai dentro do exe: ele baixa sozinho no 1o uso.
cd /d "%~dp0"
call .venv\Scripts\activate.bat
pip install pyinstaller
pyinstaller --noconfirm --windowed --onefile --name Vox ^
    --collect-all faster_whisper ^
    --collect-all ctranslate2 ^
    vox.py
echo.
echo Exe gerado em: dist\Vox.exe
pause
