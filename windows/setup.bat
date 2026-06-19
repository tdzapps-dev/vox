@echo off
setlocal
cd /d "%~dp0"

echo ============================================
echo   Vox (Windows) - instalacao
echo ============================================
echo.

where python >nul 2>nul
if errorlevel 1 (
    echo [ERRO] Python nao encontrado.
    echo Instale o Python 3.11+ em https://www.python.org/downloads/
    echo IMPORTANTE: marque a caixa "Add Python to PATH" na instalacao.
    echo.
    pause
    exit /b 1
)

echo [1/3] Criando ambiente virtual (.venv)...
python -m venv .venv
call .venv\Scripts\activate.bat

echo [2/3] Instalando dependencias...
python -m pip install --upgrade pip
pip install -r requirements.txt
if errorlevel 1 (
    echo [ERRO] Falha ao instalar dependencias.
    pause
    exit /b 1
)

echo [3/3] Baixando o modelo de voz (uma vez so)...
python -c "from faster_whisper import WhisperModel; WhisperModel('small', device='cpu', compute_type='int8'); print('modelo ok')"
if errorlevel 1 (
    echo [ERRO] Falha ao baixar o modelo.
    pause
    exit /b 1
)

echo.
echo ============================================
echo   Pronto! Agora e so dar 2 cliques em run.bat
echo ============================================
pause
