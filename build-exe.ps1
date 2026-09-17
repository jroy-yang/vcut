# build-exe.ps1 - 编译 4 个 probe 脚本为 .exe
# Requires: ps2exe module (Install-Module ps2exe -Scope CurrentUser)
# Usage: .\build-exe.ps1

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $scriptDir 'dist'

# Ensure dist directory
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

# Import ps2exe
Import-Module ps2exe -ErrorAction Stop
Write-Host "ps2exe loaded: $((Get-Module ps2exe).Version)" -ForegroundColor Green

$scripts = @('probe.ps1', 'probe2.ps1', 'probe3.ps1', 'probe4.ps1')

foreach ($script in $scripts) {
    $src = Join-Path $scriptDir $script
    $dst = Join-Path $distDir ($script -replace '\.ps1$', '.exe')
    
    if (-not (Test-Path $src)) {
        Write-Warning "Source not found: $src"
        continue
    }
    
    Write-Host ""
    Write-Host "Compiling $script -> $($script -replace '\.ps1$', '.exe')" -ForegroundColor Cyan
    
    try {
        Invoke-PS2EXE `
            -inputFile $src `
            -outputFile $dst `
            -requireAdmin:$false `
            -noConsole:$false `
            -x64 `
            -title 'webpath-scan' `
            -description 'Web path discovery and response capture tool' `
            -company 'webpath-scan' `
            -product 'webpath-scan v1.1' `
            -copyright '(c) 2026 webpath-scan contributors' `
            -version '1.1.0.0' `
            -noError:$false `
            -noOutput:$false `
            -verbose:$false | Out-Null
        
        if (Test-Path $dst) {
            $size = (Get-Item $dst).Length
            Write-Host "  OK: $dst ($([math]::Round($size/1KB, 1)) KB)" -ForegroundColor Green
        } else {
            Write-Error "Output file not created: $dst"
        }
    } catch {
        Write-Warning "Failed to compile $script : $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "=== Build complete ===" -ForegroundColor Green
Write-Host "Output: $distDir"
Get-ChildItem $distDir -File | Select-Object Name, Length | Format-Table -AutoSize
