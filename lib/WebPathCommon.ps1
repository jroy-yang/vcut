# lib/WebPathCommon.ps1
# webpath-scan v1.1 — shared helpers (dot-source from each probe*.ps1)
#
# Hardening applied vs v1.0:
#   H1: URL allowlist + private-IP blocking (SSRF defense)
#   H2: Auto-redact common secret patterns in response bodies
#   H3: Absolute path to curl.exe (PATH-hijacking defense)
#   C1: Output dir default = $PSScriptRoot/output (no cross-workspace leak)
#   M1: Enforce minimum 50ms delay between requests
#   M3: Reject unset TARGET_HOST placeholder
#   L1: User-Agent includes tool name + version
#   L2: Output dir includes timestamp

$script:TOOL_NAME    = 'webpath-scan'
$script:TOOL_VERSION = '1.1'

# ---- Config loader ----
function Get-WebPathConfig {
    param(
        [hashtable]$Overrides,
        [string]$ConfigPath
    )

    $cfg = @{
        Target         = ''
        TimeoutSec     = 8
        DelayMs        = 100
        MaxBodyKB      = 8
        UserAgent      = "$script:TOOL_NAME/$script:TOOL_VERSION (authorized-testing)"
        OutputDir      = (Join-Path $PSScriptRoot '..\output')   # C1: no cross-workspace leak
        FollowRedirect = $false
        SaveBody       = $true
        AllowPrivate   = $false
    }

    if ($Overrides) {
        foreach ($k in $Overrides.Keys) { $cfg[$k] = $Overrides[$k] }
    }

    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        $ext = [System.IO.Path]::GetExtension($ConfigPath).ToLower()
        if ($ext -eq '.psd1') {
            $imported = Import-PowerShellDataFile -Path $ConfigPath
            foreach ($k in $imported.Keys) { $cfg[$k] = $imported[$k] }
        } else {
            # Simple key:value / key=value parser for yaml-style files
            foreach ($line in (Get-Content $ConfigPath)) {
                if ($line -match '^\s*#') { continue }
                if ($line -match '^\s*(\w+)\s*[:=]\s*"?([^"]*?)"?\s*$') {
                    $key = $Matches[1]
                    $val = $Matches[2].Trim()
                    switch -Regex ($key) {
                        '^target$'         { $cfg.Target         = $val }
                        '^threads?$'       { $cfg.Threads        = [int]$val }
                        '^timeout_sec$'    { $cfg.TimeoutSec     = [int]$val }
                        '^delay_ms$'       { $cfg.DelayMs        = [int]$val }
                        '^save_body$'      { $cfg.SaveBody       = [bool]$val }
                        '^follow_redirect$' { $cfg.FollowRedirect = [bool]$val }
                        '^output_dir$'     { $cfg.OutputDir      = $val }
                        '^user_agent$'     { $cfg.UserAgent      = $val }
                        '^allow_private$'  { $cfg.AllowPrivate   = [bool]$val }
                        '^max_body_kb$'    { $cfg.MaxBodyKB      = [int]$val }
                    }
                }
            }
        }
    }

    # M3: reject unset TARGET_HOST placeholder
    if (-not $cfg.Target -or $cfg.Target -eq 'TARGET_HOST' -or $cfg.Target -match 'TARGET') {
        throw "TARGET not configured. Use -Target 'example.com' or set in config file."
    }

    # M1: enforce minimum delay to prevent DoS on authorized targets
    if ($cfg.DelayMs -lt 50) {
        Write-Warning "DelayMs=$($cfg.DelayMs) below minimum 50ms; forcing 50ms."
        $cfg.DelayMs = 50
    }

    # Resolve OutputDir to absolute path
    if (-not [System.IO.Path]::IsPathRooted($cfg.OutputDir)) {
        $cfg.OutputDir = Join-Path $PSScriptRoot "..\$($cfg.OutputDir)"
    }

    return [pscustomobject]$cfg
}

# ---- H1: SSRF defense ----
function Test-TargetSafe {
    param([string]$Target, [bool]$AllowPrivate)
    if ($AllowPrivate) {
        Write-Warning "AllowPrivate enabled — scanning private IPs. Use only on authorized systems."
        return
    }
    $hostPart = $Target -replace '^https?://', '' -replace '/.*$', '' -replace ':.*$', ''
    [System.Net.IPAddress]$ip = $null
    $isIp = [System.Net.IPAddress]::TryParse($hostPart, [ref]$ip)
    if (-not $isIp) {
        try { $ip = [System.Net.Dns]::GetHostAddresses($hostPart) | Select-Object -First 1 } catch {}
    }
    if ($ip) {
        $b = $ip.GetAddressBytes()
        $blocked = $false
        $reason = ''
        if ($b[0] -eq 10)                          { $blocked = $true; $reason = '10.0.0.0/8 (private)' }
        elseif ($b[0] -eq 127)                      { $blocked = $true; $reason = '127.0.0.0/8 (loopback)' }
        elseif ($b[0] -eq 169 -and $b[1] -eq 254)   { $blocked = $true; $reason = '169.254.0.0/16 (link-local / cloud metadata)' }
        elseif ($b[0] -eq 192 -and $b[1] -eq 168)    { $blocked = $true; $reason = '192.168.0.0/16 (private)' }
        elseif ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) { $blocked = $true; $reason = '172.16.0.0/12 (private)' }
        elseif ($b[0] -eq 0)                       { $blocked = $true; $reason = '0.0.0.0/8 (unspecified)' }
        elseif ($b[0] -ge 224)                      { $blocked = $true; $reason = 'multicast/reserved' }
        if ($blocked) {
            throw "Refusing to scan private/reserved IP $host ($reason). Use -AllowPrivate to override (for authorized internal testing only)."
        }
    }
}

# ---- H3: absolute curl path ----
function Get-CurlPath {
    $candidates = @(
        (Join-Path $env:WINDIR 'System32\curl.exe'),
        '/usr/bin/curl',
        '/usr/local/bin/curl'
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    throw "curl.exe not found in known locations."
}

# ---- invoke safe HTTP ----
function Invoke-SafeRequest {
    param(
        [string]$Url,
        [int]$TimeoutSec = 8,
        [bool]$FollowRedirect = $false,
        [string]$UserAgent
    )
    $curl = Get-CurlPath
    $args = @('-s', '-m', "$TimeoutSec", '-A', $UserAgent)
    if ($FollowRedirect) {
        $args += @('-L', '--max-redirs', '3')   # cap redirects (SSRF mitigation)
    }
    $args += $Url
    $stdout = ''
    $stderr = ''
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $curl
        $pinfo.Arguments = ($args | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
        $pinfo.UseShellExecute = $false
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($pinfo)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        if (-not $proc.WaitForExit($TimeoutSec * 1000 + 5000)) {
            try { $proc.Kill() } catch {}
            return @{ Output = ''; Status = 'TIMEOUT'; ExitCode = -1 }
        }
        return @{ Output = $stdout; Status = 'OK'; ExitCode = $proc.ExitCode }
    } catch {
        return @{ Output = ''; Status = "ERR: $($_.Exception.Message)"; ExitCode = -1 }
    }
}

# ---- parse HTTP status ----
function Format-CurlStatus {
    param([string]$Output)
    if (-not $Output) { return 'NO-RESP' }
    $first = ($Output -split "`n")[0].Trim() -replace '\r',''
    if ($first -match '^HTTP/\S+\s+(\d{3})\s*(.*)$') {
        return "$($Matches[1]) $($Matches[2].Trim())"
    }
    return 'NO-RESP'
}

# ---- H2: secret redaction ----
# Strategy: run multiple simple -replace patterns with $1/$2 substitution.
# Avoids scriptblock-callback compatibility issues across PS 5.1 / PS 7+.
function Redact-Body {
    param([string]$Body)
    if (-not $Body) { return $Body }
    $out = $Body

    # Pattern A: KEY=VALUE / "KEY": "VALUE"  (covers api_key, password, aws_*, etc.)
    # Structure: (qualifier)?[_|-]?(keytype)? then = then value
    # qualifier is one of: api|app|aws|...|password|passwd|pwd
    # keytype is one of: key|token|secret|password|passwd|pwd
    # Both qualifier and keytype are OPTIONAL (covers both 'password=...' and 'api_key=...')
    $keyValuePat = '(?i)("?)([A-Za-z0-9_\-]*?(?:api|app|aws|azure|gcp|access|secret|client|db|database|admin|root|jwt|session|bearer|private|password|passwd|pwd)[A-Za-z0-9_\-]*?)\1\s*[:=]\s*["\x27]?([^\s"\x27,;}{\r\n]{6,})'
    $out = [regex]::Replace($out, $keyValuePat, '$2=***REDACTED***')

    # Pattern B: Authorization header  ("Authorization: Bearer xxx")
    $authPat = '(?i)(authorization\s*[:=]\s*["\x27]?)(bearer\s+)?([A-Za-z0-9_\-\.=]{12,})'
    $out = [regex]::Replace($out, $authPat, '$1$2***REDACTED***')

    # Pattern C: JWT tokens (eyJxxx.yyy.zzz)
    $jwtPat = '(eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,})'
    $out = [regex]::Replace($out, $jwtPat, '***REDACTED***')

    return $out
}

# ---- save body with truncation + redaction ----
function Save-Body {
    param(
        [string]$Body,
        [string]$OutFile,
        [int]$MaxBodyKB = 8,
        [bool]$Redact = $true
    )
    if (-not $Body) {
        Set-Content -Path $OutFile -Value '' -Encoding utf8
        return
    }
    if ($Redact) { $Body = Redact-Body -Body $Body }
    $maxBytes = $MaxBodyKB * 1024
    if ($Body.Length -gt $maxBytes) {
        $Body = $Body.Substring(0, $maxBytes) + "`n# ... [truncated from $($Body.Length) bytes]"
    }
    Set-Content -Path $OutFile -Value $Body -Encoding utf8
}

# ---- timestamped output dir (L2) ----
function New-TimestampedDir {
    param([string]$BaseDir, [string]$Tag)
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir = Join-Path $BaseDir "${Tag}_${stamp}"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# ---- safe filename component ----
function Sanitize-FileName {
    param([string]$Path)
    $s = $Path -replace '[/\\?&=:*"<>\|\x00-\x1F]', '_'
    if ($s.Length -gt 100) { $s = $s.Substring(0, 100) }
    if (-not $s) { $s = 'root' }
    return $s
}

# ---- friendly URL helper ----
function Build-TargetUrl {
    param([string]$Target, [string]$Path)
    if ($Target -match '^https?://') {
        return "$Target$Path"
    }
    return "https://$Target$Path"
}

# ---- config self-check ----
function Test-CurlAvailable {
    try {
        $curl = Get-CurlPath
        return $true
    } catch {
        Write-Error $_.Exception.Message
        return $false
    }
}

# ---- Throttled runner (B: rate limit) ----
# PS 5.1+ compatible. Sequential with per-request throttle.
# For true parallelism, run multiple instances of the script in parallel.
function Invoke-ParallelRequests {
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][object[]]$InputObjects,
        [int]$MaxConcurrency = 4,
        [int]$ThrottlePerSec = 0,
        [int]$TimeoutSec = 30
    )
    if ($MaxConcurrency -lt 1) { $MaxConcurrency = 1 }
    if ($null -eq $InputObjects -or $InputObjects.Count -eq 0) { return @() }

    # Apply throttle: minimum ms between requests
    $minMs = 0
    if ($ThrottlePerSec -gt 0) {
        $minMs = [int](1000 / $ThrottlePerSec)
        if ($minMs -lt 1) { $minMs = 1 }
    }

    # Static last-call timestamp (script scope for cross-call state)
    if (-not $script:_wpsLastCallTime) { $script:_wpsLastCallTime = [datetime]::MinValue }

    $results = @()
    foreach ($item in $InputObjects) {
        # Throttle: wait until minMs elapsed since last call
        if ($minMs -gt 0) {
            $now = [DateTime]::UtcNow
            $elapsed = ($now - $script:_wpsLastCallTime).TotalMilliseconds
            if ($elapsed -lt $minMs -and $script:_wpsLastCallTime -ne [datetime]::MinValue) {
                Start-Sleep -Milliseconds ([int]($minMs - $elapsed))
            }
            $script:_wpsLastCallTime = [DateTime]::UtcNow
        }

        # Invoke the user's scriptblock
        $results += & $ScriptBlock $item
    }
    return $results
}
