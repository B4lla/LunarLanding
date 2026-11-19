@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo ERROR: Run install_dependencies.bat first.
    exit /b 1
)
rem Explicit --godot is handled by train.py; otherwise discover or ask for it.
for %%A in (%*) do if /i "%%~A"=="--godot" goto train
if /i "%~1"=="--help" goto train
if /i "%~1"=="-h" goto train
if defined GODOT_EXE goto train
where godot.exe >nul 2>&1
if not errorlevel 1 goto train
where godot4.exe >nul 2>&1
if not errorlevel 1 goto train
if exist "%~dp0Godot_v4.7.2-stable_win64_console.exe" (
    set "GODOT_EXE=%~dp0Godot_v4.7.2-stable_win64_console.exe"
    goto train
)
set /p "GODOT_EXE=Full path to Godot 4.7.2 (without quotes): "
if not defined GODOT_EXE (
    echo ERROR: A path to Godot is required.
    exit /b 1
)
:train
".venv\Scripts\python.exe" python\user_algorithms\train.py %*
exit /b %errorlevel%
