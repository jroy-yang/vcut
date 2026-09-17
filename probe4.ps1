#!/usr/bin/env pwsh
# webpath-scan v1.1 - probe4.ps1 (API-specific endpoint probe)
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
    Write-Host "[probe4] Demo mode: scanning $Target" -ForegroundColor Cyan
}

$overrides = @{
    TimeoutSec = 8
    DelayMs    = 100
    SaveBody   = $true
    MaxBodyKB  = 16
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
    Write-Host "[probe4] Throttle: $Throttle req/s -> ${cfg.DelayMs}ms"
}

$outDir = New-TimestampedDir -BaseDir $cfg.OutputDir -Tag 'probe4-api'
Write-Host "[probe4] Target: $($cfg.Target)  Concurrency: $MaxConcurrency  Out: $outDir"

$endpoints = @(
    '/api/user/info','/api/user/profile','/api/user/get','/api/user/list','/api/user/me',
    '/api/me','/api/home','/api/index','/api/news','/api/notice','/api/feed',
    '/api/banner','/api/topic','/api/category','/api/live','/api/room','/api/room/info',
    '/api/room/list','/api/getroom','/api/getRoomInfo','/api/getuserinfo','/api/search',
    '/api/search/user','/api/search/room','/api/suggest','/api/index/notice',
    '/api/index/live','/api/index/banner','/api/live/list','/api/live/notice',
    '/api/live/home','/api/home/live','/api/home/feed','/api/feed/live',
    '/api/feed/home','/api/feed/index','/api/feed/news','/api/announcement',
    '/api/announcements','/api/marquee','/api/slider','/api/recommend','/api/recommends',
    '/api/index/feed','/api/index/recommend','/api/index/recommends',
    '/api/h5/notice','/api/h5/live','/api/h5/home','/api/h5/news',
    '/api/web/notice','/api/web/news','/api/web/live','/api/web/home',
    '/api/getHome','/api/getNotice','/api/getNews','/api/getLive','/api/getIndex',
    '/api/homepage','/api/v1/home','/api/v1/index','/api/v1/news','/api/v1/notice',
    '/api/v1/live','/api/v1/room','/api/v1/user','/api/v1/user/info'
)

$endpointsDescriptors = for ($i = 0; $i -lt $endpoints.Count; $i++) {
    [PSCustomObject]@{ Index = $i + 1; Endpoint = $endpoints[$i] }
}

$job = {
    param($item)
    $i = $item.Index
    $e = $item.Endpoint
    $url = Build-TargetUrl -Target $cfg.Target -Path $e

    $r = Invoke-SafeRequest -Url $url -TimeoutSec $cfg.TimeoutSec -FollowRedirect $cfg.FollowRedirect -UserAgent $cfg.UserAgent
    $codeLine = ($r.Output -split "`n")[0].Trim() -replace '\r','' -replace 'HTTP/\S+\s*',''
    $code = if ($codeLine -match '^(\d{3})') { $Matches[1] } else { 'NO-RESP' }

    $blen = 0
    if ($cfg.SaveBody -and $r.Output) {
        $blen = $r.Output.Length
        $bfile = Join-Path $outDir ("body$($i.ToString('000'))_$(Sanitize-FileName -Path $e).txt")
        Save-Body -Body $r.Output -OutFile $bfile -MaxBodyKB $cfg.MaxBodyKB -Redact $true
    }

    [PSCustomObject]@{
        N        = $i
        Endpoint = $e
        Code     = $code
        BodyLen  = $blen
        Status   = $r.Status
    }
}

$results = Invoke-ParallelRequests -ScriptBlock $job -InputObjects $endpointsDescriptors `
                                   -MaxConcurrency $MaxConcurrency `
                                   -ThrottlePerSec $Throttle

$csv = Join-Path $outDir 'summary_api.csv'
$results | Sort-Object N | Export-Csv $csv -NoTypeInformation -Encoding utf8

Write-Host ""
Write-Host "[probe4] Done. $($results.Count) endpoints"
$results | Sort-Object BodyLen -Descending | Format-Table N, Code, BodyLen, Endpoint -AutoSize | Out-String | Write-Host
Write-Host "[probe4] Output: $outDir"
