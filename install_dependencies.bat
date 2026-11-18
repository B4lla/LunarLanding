@echo off
setlocal
cd /d "%~dp0"
echo Preparing Python environment in .venv...
if exist ".venv\Scripts\python.exe" goto install
where py >nul 2>&1
if not errorlevel 1 goto use_launcher
where python >nul 2>&1
if errorlevel 1 goto missing_python
python -m venv .venv
if errorlevel 1 goto failed
goto install
:use_launcher
py -3 -m venv .venv
if errorlevel 1 goto failed
:install
".venv\Scripts\python.exe" -c "import sys; sys.exit(not sys.version_info.__ge__((3, 10)))"
if errorlevel 1 (
    echo ERROR: Python 3.10 or later is required.
    exit /b 1
)
.venv\Scripts\python.exe -m pip install -e "./python[training]"
if errorlevel 1 goto failed
echo Dependencies installed successfully.
exit /b 0
:missing_python
echo ERROR: Install Python 3.10 or later and add Python or py to PATH.
exit /b 1
:failed
echo ERROR: Could not install dependencies. Check Python and your internet connection.
exit /b 1
