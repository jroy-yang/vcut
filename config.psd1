@{
    # webpath-scan v1.1 — default config
    # Edit values below; pass via -Config .\config.psd1 to scripts.

    # REQUIRED: target host (without scheme/port, or with scheme/port).
    # Will be REJECTED if left as TARGET_HOST placeholder.
    target         = 'TARGET_HOST'

    # Network
    timeout_sec    = 8         # per-request timeout
    delay_ms       = 100       # min 50 (scripts enforce this)
    follow_redirect = $false   # scripts follow up to 3 redirects when $true

    # Output
    output_dir     = 'output'  # relative to script dir, or absolute
    save_body      = $true
    max_body_kb    = 8         # hard cap per response file

    # Identity
    user_agent     = 'webpath-scan/1.1 (authorized-testing)'

    # Safety
    allow_private  = $false   # $true to scan private IPs (requires explicit -AllowPrivate)
}
