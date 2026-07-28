@echo off
REM 兜底启动器 - 显式用 C:\Python314\python.exe
chcp 65001 >nul
cd /d "%~dp0"

set "PY=C:\Python314\python.exe"
if not exist "%PY%" set "PY=C:\Python3*\python.exe"

echo 使用 python: %PY%
"%PY%" vcut.py
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] vcut 运行失败
    pause
)