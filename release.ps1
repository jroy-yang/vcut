# release.ps1 - 打 tag + 创建 GitHub Release（上传 ZIP + SHA256）
# 前置：
#   1. git init / add / commit 已经跑过
#   2. gh auth login 已经做过
#   3. 已建好远端 GitHub 仓库
# 用法：.\release.ps1 -Version "1.1" -Repo "yourname/webpath-scan"

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$Repo
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# 1) 重新打包
Write-Host "[release] Building ZIP..." -ForegroundColor Cyan
& ".\build-release.ps1"

$zipPath = Join-Path (Split-Path $PSScriptRoot -Parent) "webpath-scan_v$Version.zip"
if (-not (Test-Path $zipPath)) {
    throw "ZIP not found at $zipPath"
}
$zipSha = (Get-FileHash $zipPath -Algorithm SHA256).Hash
Write-Host "[release] ZIP: $zipPath" -ForegroundColor Green
Write-Host "[release] SHA-256: $zipSha"

# 2) 生成 release notes
$notes = @"
# webpath-scan v$Version

PowerShell-based web path discovery + response capture, with v1.1 security hardening.

## Highlights
- **SSRF defense** \u2014 blocks private IPs (10/8, 172.16/12, 192.168/16, 127/8, 169.254/16, 0/8, 224/4)
- **Secret redaction** \u2014 auto-masks api_key, password, JWT, etc. in response bodies
- **PATH-hijack safe** \u2014 uses absolute path to curl.exe
- **DoS guard** \u2014 minimum 50ms between requests
- **MIT licensed** + "authorized testing only" terms

## Modes
| Script | Mode | Timeout | Body | Redirect |
|--------|------|---------|------|----------|
| probe.ps1 | main (200+ paths) | 8s | yes | no |
| probe2.ps1 | fast (80 paths) | 3s | no | no |
| probe3.ps1 | deep (follows 3 redirects) | 15s | 32KB | yes |
| probe4.ps1 | API (80 /api/* endpoints) | 8s | 16KB | no |

Plus pre-compiled \`dist/*.exe\` \u2014 no PowerShell install needed.

## Quick Start

\`\`\`powershell
# Demo (legal test target: scanme.nmap.org)
.\probe2.exe -Demo

# Custom target
.\probe.exe -Target 'example.com' -Throttle 5

# With config file
.\probe.exe -Config .\config.psd1
\`\`\`

## Verification

\`\`\`powershell
# 10 security self-tests
.\self-check.ps1
\`\`\`

## SHA-256

\`\`\`
$zipSha  webpath-scan_v$Version.zip
\`\`\`

## License

MIT \u2014 see LICENSE. **Authorized testing only.**
"@

$notesPath = Join-Path $PSScriptRoot "RELEASE_NOTES_v$Version.md"
$notes | Set-Content -Path $notesPath -Encoding utf8

# 3) 创建 GitHub Release（如果 gh 已登录）
Write-Host ""
Write-Host "[release] Creating GitHub Release v$Version..." -ForegroundColor Cyan
gh release create "v$Version" $zipPath `
    --repo $Repo `
    --title "webpath-scan v$Version" `
    --notes-file $notesPath `
    --target main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "[release] Done! View at: https://github.com/$Repo/releases/tag/v$Version" -ForegroundColor Green
} else {
    Write-Warning "gh release create failed (code=$LASTEXITCODE). Check gh auth status."
}
