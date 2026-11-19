@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo ERROR: Ejecuta install_dependencies.bat primero.
    pause
    exit /b 1
)
".venv\Scripts\python.exe" probar_modelo.py %*
set "RESULT=%errorlevel%"
echo.
pause
exit /b %RESULT%
