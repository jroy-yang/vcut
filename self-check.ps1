# Self-check for webpath-scan v1.1
Set-Location 'C:\Users\Lenovo\Desktop\webpath-scan_v1.1'

$results = @()

# 1. lib loads
try {
    . '.\lib\WebPathCommon.ps1'
    $results += [PSCustomObject]@{ Test = '[1] lib dot-source'; Result = 'PASS' }
} catch {
    $results += [PSCustomObject]@{ Test = '[1] lib dot-source'; Result = "FAIL: $($_.Exception.Message)" }
}

# 2. SSRF block - 127.0.0.1
try {
    Test-TargetSafe -Target '127.0.0.1' -AllowPrivate $false
    $results += [PSCustomObject]@{ Test = '[2] SSRF block 127.0.0.1'; Result = 'FAIL: did not block' }
} catch {
    $results += [PSCustomObject]@{ Test = '[2] SSRF block 127.0.0.1'; Result = "PASS ($($_.Exception.Message))" }
}

# 3. SSRF block - 169.254.169.254 (cloud metadata)
try {
    Test-TargetSafe -Target '169.254.169.254' -AllowPrivate $false
    $results += [PSCustomObject]@{ Test = '[3] SSRF block cloud metadata'; Result = 'FAIL: did not block' }
} catch {
    $results += [PSCustomObject]@{ Test = '[3] SSRF block cloud metadata'; Result = "PASS ($($_.Exception.Message))" }
}

# 4. SSRF block - 10.x
try {
    Test-TargetSafe -Target '10.0.0.1' -AllowPrivate $false
    $results += [PSCustomObject]@{ Test = '[4] SSRF block 10.x'; Result = 'FAIL: did not block' }
} catch {
    $results += [PSCustomObject]@{ Test = '[4] SSRF block 10.x'; Result = "PASS ($($_.Exception.Message))" }
}

# 5. SSRF allow with -AllowPrivate
try {
    Test-TargetSafe -Target '10.0.0.1' -AllowPrivate $true
    $results += [PSCustomObject]@{ Test = '[5] SSRF allow with -AllowPrivate'; Result = 'PASS' }
} catch {
    $results += [PSCustomObject]@{ Test = '[5] SSRF allow with -AllowPrivate'; Result = "FAIL: $($_.Exception.Message)" }
}

# 6. Config rejects TARGET_HOST placeholder
try {
    $cfg = Get-WebPathConfig -Overrides @{}
    $results += [PSCustomObject]@{ Test = '[6] placeholder rejected'; Result = 'FAIL: did not reject' }
} catch {
    $results += [PSCustomObject]@{ Test = '[6] placeholder rejected'; Result = "PASS ($($_.Exception.Message))" }
}

# 7. Body redaction works
$secretBody = @'
api_key=AKIA1234567890ABCDEF
password=MySecretP@ssw0rd
authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
"private_key": "-----BEGIN RSA PRIVATE KEY-----"
'@
$redacted = Redact-Body -Body $secretBody
$hasKey = $redacted -match 'REDACTED'
$noLeak = ($redacted -notmatch 'AKIA1234567890ABCDEF') -and ($redacted -notmatch 'MySecretP@ssw0rd')
if ($hasKey -and $noLeak) {
    $results += [PSCustomObject]@{ Test = '[7] body redaction'; Result = 'PASS' }
} else {
    $results += [PSCustomObject]@{ Test = '[7] body redaction'; Result = "FAIL: leaked - $redacted" }
}

# 8. probe.ps1 rejects TARGET_HOST
try {
    & '.\probe.ps1' -Target 'TARGET_HOST'
    $results += [PSCustomObject]@{ Test = '[8] probe blocks placeholder'; Result = 'FAIL: ran' }
} catch {
    $results += [PSCustomObject]@{ Test = '[8] probe blocks placeholder'; Result = "PASS" }
}

# 9. probe.ps1 blocks 127.0.0.1
try {
    & '.\probe.ps1' -Target '127.0.0.1'
    $results += [PSCustomObject]@{ Test = '[9] probe blocks 127.0.0.1'; Result = 'FAIL: ran' }
} catch {
    $results += [PSCustomObject]@{ Test = '[9] probe blocks 127.0.0.1'; Result = "PASS" }
}

# 10. Filename sanitizer handles tricky paths
$test1 = Sanitize-FileName -Path '/admin/'
$test2 = Sanitize-FileName -Path '/../../etc/passwd'
$test3 = Sanitize-FileName -Path ''
$test1ok = ($test1 -replace '^_|_$','') -eq 'admin'
$test2ok = ($test2 -replace '^_|_$','') -match 'etc.passwd'
$test3ok = $test3 -eq 'root'
if ($test1ok -and $test2ok -and $test3ok) {
    $results += [PSCustomObject]@{ Test = '[10] filename sanitize'; Result = 'PASS' }
} else {
    $results += [PSCustomObject]@{ Test = '[10] filename sanitize'; Result = "FAIL (test1=$test1 test2=$test2 test3=$test3)" }
}

# Output
$results | Format-Table -AutoSize | Out-String | Write-Host

$fail = $results | Where-Object { $_.Result -like 'FAIL*' }
if ($fail) {
    Write-Host "OVERALL: $($fail.Count) test(s) FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "OVERALL: ALL 10 TESTS PASSED" -ForegroundColor Green
}
