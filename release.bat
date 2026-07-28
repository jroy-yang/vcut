@echo off
REM ============================================================
REM vcut release builder
REM Produces:
REM   dist\vcut-<ver>-win64.zip          (portable archive)
REM   dist\vcut-<ver>-win64.zip.sha256   (integrity check)
REM   dist\RELEASE_INFO.txt              (metadata)
REM ============================================================

setlocal EnableDelayedExpansion

cd /d "%~dp0"

REM --- read version from vcut.py ---
set "VERSION=0.1.0"
for /f "tokens=1,2,3 delims== " %%a in ('findstr /B /C:"APP_VERSION" vcut.py') do (
    set "VER=%%c"
)
if defined VER set "VERSION=!VER:"=!"

echo ============================================
echo   vcut release builder  v!VERSION!
echo ============================================

if not exist "dist\vcut.exe" (
    echo [ERROR] dist\vcut.exe not found. Run build.py first.
    pause
    exit /b 1
)

set "ZIP_NAME=vcut-!VERSION!-win64.zip"
set "SHA_NAME=vcut-!VERSION!-win64.zip.sha256"
set "INFO_NAME=RELEASE_INFO.txt"

if exist "dist\!ZIP_NAME!" del "dist\!ZIP_NAME!"
if exist "dist\!SHA_NAME!" del "dist\!SHA_NAME!"
if exist "dist\!INFO_NAME!" del "dist\!INFO_NAME!"

REM --- zip ---
echo.
echo [1/3] Zipping dist\ to !ZIP_NAME! ...
powershell -NoProfile -Command "Compress-Archive -Path 'dist\*' -DestinationPath 'dist\!ZIP_NAME!' -Force" >nul
if errorlevel 1 (
    echo [ERROR] zip failed
    pause
    exit /b 1
)

REM --- sha256 (use PowerShell; certutil output is localized) ---
echo.
echo [2/3] Generating SHA256 ...
for /f "delims=" %%L in ('powershell -NoProfile -Command "(Get-FileHash 'dist\!ZIP_NAME!' -Algorithm SHA256).Hash"') do set "SHA=%%L"
echo !SHA!> "dist\!SHA_NAME!"
echo   !SHA!

REM --- gather facts ---
for %%F in ("dist\!ZIP_NAME!") do set "ZIP_SIZE=%%~zF"
set "CONTENTS_TMP=%TEMP%\vcut_contents_!RANDOM!.txt"
powershell -NoProfile -Command "Get-ChildItem 'dist\*' | Where-Object { $_.Name -ne '!ZIP_NAME!' -and $_.Name -ne '!SHA_NAME!' -and $_.Name -ne '!INFO_NAME!' } | ForEach-Object { '   ' + $_.Name + '  ' + [math]::Round($_.Length/1MB,2).ToString('N2') + ' MB' } | Out-File -FilePath '!CONTENTS_TMP!' -Encoding ascii -NoNewline" >nul

REM --- write info file ---
echo.
echo [3/3] Writing RELEASE_INFO.txt ...
echo.
echo [3/3] Writing RELEASE_INFO.txt ...
> "dist\!INFO_NAME!" (
    echo vcut release v!VERSION!
    echo ==============================
    echo Built: %DATE% %TIME%
    echo Host:  %COMPUTERNAME% / %OS%
    echo.
    echo File:  !ZIP_NAME!
    echo Size:  !ZIP_SIZE! bytes
    echo.
    echo Contents of archive:
)
type "!CONTENTS_TMP!" >> "dist\!INFO_NAME!"
del "!CONTENTS_TMP!" >nul 2>nul
>> "dist\!INFO_NAME!" (
    echo.
    echo SHA256:
    echo   !SHA!
    echo.
    echo FFmpeg bundled: BtbN/FFmpeg-Builds ^(GPLv3^)
    echo   https://github.com/BtbN/FFmpeg-Builds
)

echo.
type "dist\!INFO_NAME!"

echo.
echo ============================================
echo   [OK] Release ready in dist\
echo ============================================
dir /b "dist\"
echo.
pause