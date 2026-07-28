# ============================================================
# vcut release builder (PowerShell)
# Produces:
#   dist\vcut-<ver>-win64.zip          (portable archive)
#   dist\vcut-<ver>-win64.zip.sha256   (integrity check)
#   dist\RELEASE_INFO.txt              (metadata)
# Optional: -Push will run `gh release create` to publish.
# ============================================================

param(
    [switch]$Push,
    [string]$Repo = "",          # e.g. "Lenovo/vcut" — required for -Push
    [string]$Notes = ""          # optional release notes (markdown)
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# --- read version from vcut.py ---
$versionLine = Select-String -Path ".\vcut.py" -Pattern '^APP_VERSION\s*=' | Select-Object -First 1
if (-not $versionLine) {
    Write-Host "[ERROR] APP_VERSION not found in vcut.py" -ForegroundColor Red
    exit 1
}
$VERSION = ($versionLine.Line -replace 'APP_VERSION\s*=\s*', '').Trim().Trim('"').Trim("'")
Write-Host "============================================"
Write-Host "  vcut release builder  v$VERSION"
Write-Host "============================================"

if (-not (Test-Path "dist\vcut.exe")) {
    Write-Host "[ERROR] dist\vcut.exe not found. Run build.py first." -ForegroundColor Red
    exit 1
}

$ZIP_NAME = "vcut-${VERSION}-win64.zip"
$SHA_NAME = "vcut-${VERSION}-win64.zip.sha256"
$INFO_NAME = "RELEASE_INFO.txt"

Remove-Item -Force "dist\$ZIP_NAME", "dist\$SHA_NAME", "dist\$INFO_NAME" -ErrorAction SilentlyContinue

# --- zip ---
Write-Host ""
Write-Host "[1/3] Zipping dist\ to $ZIP_NAME ..."
Compress-Archive -Path "dist\*" -DestinationPath "dist\$ZIP_NAME" -Force

# --- sha256 (PowerShell-native, no certutil localization issues) ---
Write-Host ""
Write-Host "[2/3] Generating SHA256 ..."
$hash = (Get-FileHash "dist\$ZIP_NAME" -Algorithm SHA256).Hash
$hash | Out-File -FilePath "dist\$SHA_NAME" -Encoding ascii -NoNewline
Write-Host "   $hash"

# --- gather contents ---
$contentsLines = Get-ChildItem "dist\*" |
    Where-Object { $_.Name -ne $ZIP_NAME -and $_.Name -ne $SHA_NAME -and $_.Name -ne $INFO_NAME } |
    ForEach-Object { "   $($_.Name)  $([math]::Round($_.Length/1MB, 2).ToString('N2')) MB" }

# --- write info ---
$zipSize = (Get-Item "dist\$ZIP_NAME").Length
$infoLines = @(
    "vcut release v$VERSION"
    "=============================="
    "Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    "Host:  $env:COMPUTERNAME / $($env:OS)"
    ""
    "File:  $ZIP_NAME"
    "Size:  $zipSize bytes"
    ""
    "Contents of archive:"
    $contentsLines
    ""
    "SHA256:"
    "   $hash"
    ""
    "FFmpeg bundled: BtbN/FFmpeg-Builds (GPLv3)"
    "   https://github.com/BtbN/FFmpeg-Builds"
)
$infoLines | Out-File -FilePath "dist\$INFO_NAME" -Encoding ascii

Write-Host ""
Write-Host "[3/3] Wrote RELEASE_INFO.txt"
Get-Content "dist\$INFO_NAME"

# --- optionally push ---
if ($Push) {
    if (-not $Repo) {
        Write-Host "[ERROR] -Push requires -Repo 'owner/name'" -ForegroundColor Red
        exit 1
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] gh CLI not found. Install: https://cli.github.com" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
    Write-Host "[push] Creating GitHub release $Repo @ v$VERSION ..."
    $body = if ($Notes) { $Notes } else { Get-Content "dist\$INFO_NAME" -Raw }
    gh release create "v$VERSION" `
        "dist\$ZIP_NAME" `
        "dist\$ZIP_NAME.sha256" `
        "dist\$INFO_NAME" `
        --repo "$Repo" `
        --title "vcut v$VERSION" `
        --notes "$body"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[push] OK -> https://github.com/$Repo/releases/tag/v$VERSION" -ForegroundColor Green
    } else {
        Write-Host "[push] FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host ""
Write-Host "============================================"
Write-Host "  [OK] Release ready in dist\" -ForegroundColor Green
Write-Host "============================================"
Get-ChildItem "dist\" | Format-Table Name, @{n='Size';e={"$([math]::Round($_.Length/1MB,2)) MB"}} -AutoSize