# build-release.ps1 - 打包 webpath-scan v1.1 准备上架
$ErrorActionPreference = 'Stop'
$src = 'C:\Users\Lenovo\Desktop\webpath-scan_v1.1'
$stage = Join-Path $src '_stage'
$dist = Join-Path $src 'dist'
$zipOut = Join-Path $src '..\webpath-scan_v1.1.zip'

# 1) 准备暂存目录（如果存在先清空）
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

# 2) 复制运行时所需文件（ps1、配置、文档、lib）
$filesToCopy = @('probe.ps1','probe2.ps1','probe3.ps1','probe4.ps1','config.psd1','README.md','CHANGELOG.md','LICENSE')
foreach ($f in $filesToCopy) {
    $from = Join-Path $src $f
    if (Test-Path $from) { Copy-Item -Path $from -Destination $stage }
}

# 3) 复制 lib 目录
if (Test-Path (Join-Path $src 'lib')) {
    Copy-Item -Path (Join-Path $src 'lib') -Destination $stage -Recurse
}

# 4) 复制 dist/ 里的 .exe
if (Test-Path $dist) {
    New-Item -ItemType Directory -Path (Join-Path $stage 'dist') | Out-Null
    Get-ChildItem -Path $dist -Filter '*.exe' | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $stage 'dist')
    }
}

Write-Host '=== Staged files ==='
Get-ChildItem $stage -Recurse | Select-Object FullName, Length | Format-Table -AutoSize

# 5) 生成校验和（SHA-256）— 卖家上架常用
Write-Host ''
Write-Host '=== Generating SHA-256 checksums ==='
$checksums = Join-Path $stage 'SHA256SUMS.txt'
$lines = @()
Get-ChildItem -Path $stage -File -Recurse | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | ForEach-Object {
    $h = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
    $rel = $_.FullName.Substring($stage.Length + 1).Replace('\','/')
    $lines += "$h  $rel"
}
$lines | Sort-Object | Set-Content -Path $checksums -Encoding utf8
Get-Content $checksums | ForEach-Object { Write-Host $_ }

# 6) 打成 zip
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipOut, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Write-Host ''
Write-Host "=== ZIP created ==="
Get-Item $zipOut | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
