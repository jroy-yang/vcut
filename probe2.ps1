#!/usr/bin/env pwsh
# webpath-scan v1.1 - probe2.ps1 (FAST mode)
# Features: B (throttle+concurrency), D (--demo)

[CmdletBinding()]
param(
    [string]$Target,
    [string]$Config,
    [string]$OutputDir,
    [int]$DelayMs,
    [int]$MaxBodyKB,
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
    Write-Host "[probe2] Demo mode: scanning $Target" -ForegroundColor Cyan
}

$overrides = @{ TimeoutSec = 3; DelayMs = 50; SaveBody = $false; MaxBodyKB = 0 }
if ($PSBoundParameters.ContainsKey('OutputDir'))     { $overrides.OutputDir    = $OutputDir }
if ($PSBoundParameters.ContainsKey('DelayMs'))       { $overrides.DelayMs      = $DelayMs }
if ($PSBoundParameters.ContainsKey('MaxBodyKB'))     { $overrides.MaxBodyKB    = $MaxBodyKB }
if ($PSBoundParameters.ContainsKey('AllowPrivate'))   { $overrides.AllowPrivate = $AllowPrivate }
if ($Target) { $overrides.Target = $Target }

$cfg = Get-WebPathConfig -Overrides $overrides -ConfigPath $Config
Test-TargetSafe -Target $cfg.Target -AllowPrivate $cfg.AllowPrivate

if ($Throttle -gt 0) {
    $cfg.DelayMs = [int](1000 / $Throttle)
    Write-Host "[probe2] Throttle: $Throttle req/s -> ${cfg.DelayMs}ms"
}

$outDir = New-TimestampedDir -BaseDir $cfg.OutputDir -Tag 'probe2-fast'
Write-Host "[probe2] Target: $($cfg.Target)  Concurrency: $MaxConcurrency  Out: $outDir"

$paths = @(
    '/admin/','/admin/index/','/admin/login/','/admin/api/','/admin/v1/','/admin/console/',
    '/manage/','/manage/login/','/manage/api/',
    '/backend/','/console/','/api/v1/','/api/v2/','/api/v3/','/v1/','/v2/','/v3/',
    '/internal/','/internal/api/','/gateway/','/proxy/','/open/',
    '/yws/','/yws/login/','/yws/api/','/yws/user/','/yws/note/','/yws/admin/',
    '/legu/','/legu/admin/','/legu/api/','/legu/login/','/legu/user/',
    '/healthz/','/status/','/ping/','/info/','/metrics/','/version/',
    '/actuator/','/actuator/env/','/actuator/health/','/actuator/beans/',
    '/actuator/configprops/','/actuator/mappings/','/actuator/trace/','/actuator/loggers/',
    '/actuator/info/','/actuator/heapdump/',
    '/swagger/','/swagger-ui/','/swagger-resources/','/api-docs/',
    '/v2/api-docs/','/v3/api-docs/','/graphiql/','/graphql/','/doc/','/docs/',
    '/debug/','/test/','/dev/'
)

$pathDescriptors = for ($i = 0; $i -lt $paths.Count; $i++) {
    [PSCustomObject]@{ Index = $i + 1; Path = $paths[$i] }
}

$job = {
    param($item)
    $i = $item.Index
    $p = $item.Path
    $url = Build-TargetUrl -Target $cfg.Target -Path $p

    $r = Invoke-SafeRequest -Url $url -TimeoutSec $cfg.TimeoutSec -FollowRedirect $false -UserAgent $cfg.UserAgent
    $firstLine = ($r.Output -split "`n")[0].Trim() -replace '\r',''
    $code = if ($firstLine -match '^HTTP/\S+\s+(\d{3})') { $Matches[1] } else { 'NO-RESP' }
    $size = if ($r.Output) { $r.Output.Length } else { 0 }

    [PSCustomObject]@{
        N     = $i
        Path  = $p
        Code  = $code
        Size  = $size
        State = $r.Status
    }
}

$results = Invoke-ParallelRequests -ScriptBlock $job -InputObjects $pathDescriptors `
                                   -MaxConcurrency $MaxConcurrency `
                                   -ThrottlePerSec $Throttle

$csv = Join-Path $outDir 'summary2.csv'
$results | Sort-Object N | Export-Csv $csv -NoTypeInformation -Encoding utf8

Write-Host ""
Write-Host "[probe2] Done. $($results.Count) requests"
$results | Sort-Object Code, Size -Descending | Format-Table N, Code, Size, Path -AutoSize | Out-String | Write-Host
Write-Host "[probe2] Output: $outDir"
