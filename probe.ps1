#!/usr/bin/env pwsh
# webpath-scan v1.1 - probe.ps1 (main script)
# Features: B (throttle+concurrency), D (--demo)
#
# Usage:
#   .\probe.ps1 -Target 'example.com'
#   .\probe.ps1 -Target 'example.com' -Throttle 5 -MaxConcurrency 4
#   .\probe.ps1 -Demo                                    # scans scanme.nmap.org

[CmdletBinding()]
param(
    [string]$Target,
    [string]$Config,
    [string]$OutputDir,
    [int]$TimeoutSec,
    [int]$DelayMs,
    [int]$MaxBodyKB,
    [bool]$FollowRedirect,
    [bool]$SaveBody,
    [bool]$AllowPrivate,
    [int]$MaxConcurrency = 4,
    [int]$Throttle = 0,
    [switch]$Demo
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'lib\WebPathCommon.ps1')

# D: --demo mode
if ($Demo) {
    if ($Target) {
        Write-Warning "-Demo ignored: -Target '$Target' already specified"
    } else {
        $Target = 'scanme.nmap.org'
        Write-Host "[probe] Demo mode: scanning $Target (Nmap's authorized test target)" -ForegroundColor Cyan
    }
}

$overrides = @{}
if ($PSBoundParameters.ContainsKey('OutputDir'))     { $overrides.OutputDir      = $OutputDir }
if ($PSBoundParameters.ContainsKey('TimeoutSec'))    { $overrides.TimeoutSec     = $TimeoutSec }
if ($PSBoundParameters.ContainsKey('DelayMs'))       { $overrides.DelayMs        = $DelayMs }
if ($PSBoundParameters.ContainsKey('MaxBodyKB'))     { $overrides.MaxBodyKB      = $MaxBodyKB }
if ($PSBoundParameters.ContainsKey('FollowRedirect')) { $overrides.FollowRedirect = $FollowRedirect }
if ($PSBoundParameters.ContainsKey('SaveBody'))       { $overrides.SaveBody       = $SaveBody }
if ($PSBoundParameters.ContainsKey('AllowPrivate'))   { $overrides.AllowPrivate   = $AllowPrivate }
if ($Target) { $overrides.Target = $Target }

$cfg = Get-WebPathConfig -Overrides $overrides -ConfigPath $Config
Test-TargetSafe -Target $cfg.Target -AllowPrivate $cfg.AllowPrivate

# B: throttle takes precedence over delay_ms (computed from -Throttle req/sec)
if ($Throttle -gt 0) {
    $cfg.DelayMs = [int](1000 / $Throttle)
    Write-Host "[probe] Throttle: $Throttle req/s -> ${cfg.DelayMs}ms between requests"
}

$outDir = New-TimestampedDir -BaseDir $cfg.OutputDir -Tag 'probe'
Write-Host "[probe] Target: $($cfg.Target)  Concurrency: $MaxConcurrency  Out: $outDir"

$paths = @(
    '/','/admin','/admin/','/admin/index','/admin/login','/admin/api','/admin/v1','/admin/console',
    '/manage','/manage/','/manage/login','/manage/api','/backend','/backend/','/console','/console/',
    '/api','/api/','/api/v1','/api/v2','/api/v3','/v1','/v2','/v3',
    '/internal','/internal/','/internal/api','/gateway','/proxy','/proxy/','/open','/open/',
    '/yws','/yws/','/yws/login','/yws/api','/yws/user','/yws/note','/yws/admin',
    '/legu','/legu/','/legu/admin','/legu/api','/legu/login','/legu/user',
    '/health','/health/','/healthz','/ready','/ready/','/live','/live/','/status','/status/',
    '/ping','/ping/','/info','/info/','/metrics','/metrics/','/version','/version/',
    '/actuator','/actuator/','/actuator/env','/actuator/health','/actuator/beans','/actuator/configprops',
    '/actuator/mappings','/actuator/trace','/actuator/loggers','/actuator/info','/actuator/heapdump',
    '/swagger','/swagger/','/swagger-ui','/swagger-ui/','/swagger-ui.html','/swagger-resources',
    '/api-docs','/api-docs/','/api-docs/swagger.json','/v2/api-docs','/v3/api-docs',
    '/graphiql','/graphql','/doc','/doc/','/docs','/docs/','/docs/api',
    '/.git/config','/.env','/config.json','/config.yaml','/config.yml','/settings.py','/application.yml',
    '/WEB-INF/web.xml','/crossdomain.xml','/robots.txt','/sitemap.xml','/favicon.ico',
    '/user','/user/','/users','/users/','/profile','/profile/','/me','/me/','/info/user',
    '/order','/order/','/orders','/trade','/pay','/billing','/invoice','/invoice/',
    '/search','/search/','/query','/query/','/fetch','/fetch/','/get','/s','/s/',
    '/cgi-bin','/cgi-bin/','/cgi-bin/test','/cgi-bin/admin','/cgi-bin/login','/cgi-bin/api',
    '/nc','/nc/','/netease','/cc','/cc/','/cc/api','/cc/admin',
    '/wp-admin','/wp-login.php','/wp-json','/xmlrpc.php',
    '/debug','/debug/','/debug/pprof','/debug/vars','/debug/info','/debug/requests',
    '/test','/test/','/dev','/dev/','/staging','/prod','/old','/backup',
    '/.well-known','/.well-known/security.txt','/server-status','/server-info'
)

# Pre-build path descriptor objects (preserves order)
$pathDescriptors = for ($i = 0; $i -lt $paths.Count; $i++) {
    [PSCustomObject]@{ Index = $i + 1; Path = $paths[$i] }
}

# B: parallel throttled scanner
$job = {
    param($item)
    $i = $item.Index
    $p = $item.Path
    $safe = Sanitize-FileName -Path $p
    $seq = $i.ToString('000')
    $url = Build-TargetUrl -Target $cfg.Target -Path $p

    $headResult = Invoke-SafeRequest -Url $url -TimeoutSec $cfg.TimeoutSec -FollowRedirect $cfg.FollowRedirect -UserAgent $cfg.UserAgent
    $statusLine = Format-CurlStatus -Output $headResult.Output

    $blen = 0
    if ($cfg.SaveBody) {
        $bodyResult = Invoke-SafeRequest -Url $url -TimeoutSec $cfg.TimeoutSec -FollowRedirect $cfg.FollowRedirect -UserAgent $cfg.UserAgent
        $body = $bodyResult.Output
        $blen = if ($body) { $body.Length } else { 0 }
        $bfile = Join-Path $outDir ("body_${seq}_${safe}.txt")
        Save-Body -Body $body -OutFile $bfile -MaxBodyKB $cfg.MaxBodyKB -Redact $true
    }

    $hfile = Join-Path $outDir ("head_${seq}_${safe}.txt")
    $headContent = $headResult.Output
    if ($headContent.Length -gt 4096) { $headContent = $headContent.Substring(0, 4096) + "`n# [truncated]" }
    if (-not $headContent) { $headContent = '# ' + $headResult.Status }
    Set-Content -Path $hfile -Value $headContent -Encoding utf8

    [PSCustomObject]@{
        N        = $i
        Path     = $p
        Url      = $url
        Status   = $statusLine
        BodyLen  = $blen
        SaveBody = $cfg.SaveBody
    }
}

$results = Invoke-ParallelRequests -ScriptBlock $job -InputObjects $pathDescriptors `
                                   -MaxConcurrency $MaxConcurrency `
                                   -ThrottlePerSec $Throttle `
                                   -TimeoutSec $cfg.TimeoutSec

$csvPath = Join-Path $outDir 'summary.csv'
$results | Sort-Object N | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8

Write-Host ""
Write-Host "[probe] Done. $($results.Count) requests, results at $outDir"
$results | Where-Object { $_.Status -match '^2|^3|^4|^5' } | Sort-Object Status, BodyLen -Descending | Format-Table N, Status, BodyLen, Path -AutoSize | Out-String | Write-Host

Write-Host "[probe] Output: $outDir"
Write-Host "[probe] Summary CSV: $csvPath"
