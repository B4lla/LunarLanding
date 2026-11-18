@echo off
setlocal
cd /d "%~dp0"
echo Downloading optional assets from Poly Haven and NASA...
if exist ".venv\Scripts\python.exe" goto use_venv
where py >nul 2>&1
if not errorlevel 1 goto use_launcher
where python >nul 2>&1
if errorlevel 1 goto missing_python
set "PYTHON=python"
goto download
:use_launcher
set "PYTHON=py -3"
goto download
:use_venv
set "PYTHON=.venv\Scripts\python.exe"
:download
%PYTHON% tools\fetch_cc0.py
if errorlevel 1 goto failed
%PYTHON% tools\fetch_nasa.py
if errorlevel 1 goto failed
echo Assets downloaded. Open or restart the Godot editor to import them.
echo The NASA model is optional and requires activation; see README.md.
exit /b 0
:missing_python
echo ERROR: Install Python 3.10 or later and add Python or py to PATH.
exit /b 1
:failed
echo ERROR: Download failed. Check your internet connection and try again.
exit /b 1
