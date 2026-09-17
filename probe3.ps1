#!/usr/bin/env pwsh
# webpath-scan v1.1 - probe3.ps1 (DEEP mode: long timeout, follow redirects, save body)
# Features: B (throttle+concurrency), D (--demo)

[CmdletBinding()]
param(
    [string]$Target,
    [string]$Config,
    [string]$OutputDir,
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

if ($Demo -and -not $Target) {
    $Target = 'scanme.nmap.org'
    Write-Host "[probe3] Demo mode: scanning $Target" -ForegroundColor Cyan
}

$overrides = @{
    TimeoutSec     = 15
    DelayMs        = 100
    SaveBody       = $true
    MaxBodyKB      = 32
    FollowRedirect = $true
}
if ($PSBoundParameters.ContainsKey('OutputDir'))     { $overrides.OutputDir      = $OutputDir }
if ($PSBoundParameters.ContainsKey('DelayMs'))       { $overrides.DelayMs        = $DelayMs }
if ($PSBoundParameters.ContainsKey('MaxBodyKB'))     { $overrides.MaxBodyKB      = $MaxBodyKB }
if ($PSBoundParameters.ContainsKey('FollowRedirect')) { $overrides.FollowRedirect = $FollowRedirect }
if ($PSBoundParameters.ContainsKey('SaveBody'))       { $overrides.SaveBody       = $SaveBody }
if ($PSBoundParameters.ContainsKey('AllowPrivate'))   { $overrides.AllowPrivate   = $AllowPrivate }
if ($Target) { $overrides.Target = $Target }

$cfg = Get-WebPathConfig -Overrides $overrides -ConfigPath $Config
Test-TargetSafe -Target $cfg.Target -AllowPrivate $cfg.AllowPrivate

if ($Throttle -gt 0) {
    $cfg.DelayMs = [int](1000 / $Throttle)
    Write-Host "[probe3] Throttle: $Throttle req/s -> ${cfg.DelayMs}ms"
}

$outDir = New-TimestampedDir -BaseDir $cfg.OutputDir -Tag 'probe3-deep'
Write-Host "[probe3] Target: $($cfg.Target)  Concurrency: $MaxConcurrency  FollowRedirect: $($cfg.FollowRedirect)  Out: $outDir"

$paths = @(
    '/admin/','/admin/index/','/admin/login/','/admin/api/','/admin/v1/','/admin/console/',
    '/manage/','/manage/login/','/manage/api/','/backend/','/console/',
    '/api/v1/','/api/v2/','/api/v3/','/v1/','/v2/','/v3/',
    '/internal/','/internal/api/','/gateway/','/proxy/','/open/',
    '/yws/','/yws/login/','/yws/api/','/yws/user/','/yws/note/','/yws/admin/',
    '/legu/','/legu/admin/','/legu/api/','/legu/login/','/legu/user/',
    '/healthz/','/status/','/ping/','/info/','/metrics/','/version/',
    '/actuator/','/actuator/env/','/actuator/health/','/actuator/beans/',
    '/actuator/configprops/','/actuator/mappings/','/actuator/trace/','/actuator/loggers/',
    '/actuator/info/','/actuator/heapdump/',
    '/swagger/','/swagger-ui/','/swagger-resources/','/api-docs/',
    '/v2/api-docs/','/v3/api-docs/','/graphiql/','/graphql/','/doc/','/docs/',
    '/debug/','/dev/'
)

$pathDescriptors = for ($i = 0; $i -lt $paths.Count; $i++) {
    [PSCustomObject]@{ Index = $i + 1; Path = $paths[$i] }
}

$job = {
    param($item)
    $i = $item.Index
    $p = $item.Path
    $url = Build-TargetUrl -Target $cfg.Target -Path $p
    $safe = Sanitize-FileName -Path $p
    $seq = $i.ToString('000')

    $headR = Invoke-SafeRequest -Url $url -TimeoutSec $cfg.TimeoutSec -FollowRedirect $cfg.FollowRedirect -UserAgent $cfg.UserAgent
    $codeLine = ($headR.Output -split "`n")[0] -replace '\r','' -replace 'HTTP/\S+\s*',''
    $code = if ($codeLine -match '^(\d{3})') { $Matches[1] } else { 'NO-RESP' }

    $blen = 0
    if ($cfg.SaveBody) {
        $bodyR = Invoke-SafeRequest -Url $url -TimeoutSec $cfg.TimeoutSec -FollowRedirect $cfg.FollowRedirect -UserAgent $cfg.UserAgent
        $body = $bodyR.Output
        $blen = if ($body) { $body.Length } else { 0 }
        $bfile = Join-Path $outDir ("b_${seq}_${safe}.txt")
        Save-Body -Body $body -OutFile $bfile -MaxBodyKB $cfg.MaxBodyKB -Redact $true
    }

    $hfile = Join-Path $outDir ("h_${seq}_${safe}.txt")
    $headContent = $headR.Output
    if (-not $headContent) { $headContent = '# ' + $headR.Status }
    Set-Content -Path $hfile -Value $headContent -Encoding utf8

    [PSCustomObject]@{
        N       = $i
        Path    = $p
        Code    = $code
        BodyLen = $blen
        Status  = $headR.Status
    }
}

$results = Invoke-ParallelRequests -ScriptBlock $job -InputObjects $pathDescriptors `
                                   -MaxConcurrency $MaxConcurrency `
                                   -ThrottlePerSec $Throttle

$csv = Join-Path $outDir 'summary3.csv'
$results | Sort-Object N | Export-Csv $csv -NoTypeInformation -Encoding utf8

Write-Host ""
Write-Host "[probe3] Done. $($results.Count) requests"
$results | Sort-Object Code, BodyLen -Descending | Format-Table N, Code, BodyLen, Status, Path -AutoSize | Out-String | Write-Host
Write-Host "[probe3] Output: $outDir"
