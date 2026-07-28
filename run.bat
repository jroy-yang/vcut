@echo off
REM vcut launcher - ASCII only, no encoding issues
cd /d "%~dp0"

echo ============================================
echo   vcut - Local Video Cutter
echo ============================================

REM Find real python.exe (skip WindowsApps stub)
set "PY_EXE="
for /f "delims=" %%P in ('where python 2^>nul') do (
    echo %%P | findstr /i "WindowsApps" >nul
    if errorlevel 1 (
        set "PY_EXE=%%P"
        goto :found
    )
)

:found
if "%PY_EXE%"=="" (
    echo [ERROR] python not found in PATH
    echo Please install Python 3.10+ and ensure "Add to PATH" is checked.
    pause
    exit /b 1
)
echo [OK] python: %PY_EXE%

where ffmpeg >nul 2>nul
if %errorlevel% neq 0 (
    echo [WARN] ffmpeg not in PATH. Get it from https://www.gyan.dev/ffmpeg/builds/
) else (
    echo [OK] ffmpeg found
)

echo.
echo Starting vcut GUI...
"%PY_EXE%" vcut.py
if %errorlevel% neq 0 (
    echo [ERROR] vcut failed to start
    pause
)