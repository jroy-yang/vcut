@echo off
REM vcut - direct launcher using absolute python path
REM Avoids all PATH / encoding issues.
cd /d "%~dp0"

if exist "C:\Python314\python.exe" (
    "C:\Python314\python.exe" vcut.py
) else if exist "C:\Python313\python.exe" (
    "C:\Python313\python.exe" vcut.py
) else if exist "C:\Python312\python.exe" (
    "C:\Python312\python.exe" vcut.py
) else if exist "C:\Python311\python.exe" (
    "C:\Python311\python.exe" vcut.py
) else (
    REM Last resort: use whatever 'py' launcher finds
    py vcut.py
)