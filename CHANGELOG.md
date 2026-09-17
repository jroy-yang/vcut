# Changelog

## v1.1 — Security hardening release

### 🔴 Critical fixes

- **C1**: Output directory no longer hardcoded to `workspace-k8sops\cc-scan`. Now defaults to script-relative `output/` and can be overridden via `-OutputDir` or config.

### 🟠 High severity fixes

- **H1 (SSRF defense)**: `Test-TargetSafe` blocks RFC1918 private IPs (10/8, 172.16/12, 192.168/16), loopback (127/8), link-local (169.254/16 — includes cloud metadata `169.254.169.254`), unspecified (0/8), and multicast (224/4). Bypass requires explicit `-AllowPrivate`.
- **H2 (Secret leakage)**: Response bodies are auto-redacted before write. Patterns covered: `api_key`, `secret`, `password`, `token`, `authorization`, `bearer`, AWS/Azure/GCP credentials, JWTs.
- **H3 (PATH hijacking)**: Replaced bare `curl.exe` with absolute path `C:\Windows\System32\curl.exe` (or `/usr/bin/curl` on Linux/macOS).

### 🟡 Medium severity fixes

- **M1 (DoS mitigation)**: Minimum `delay_ms = 50ms` enforced. Config values below threshold are auto-clamped with warning.
- **M3 (Placeholder validation)**: `TARGET_HOST` literal is now rejected with clear error message.
- **M4 (Filename collisions)**: Output filenames include zero-padded sequence number (`head_001_admin.txt` vs `head_002_admin_index.txt`) to prevent overwrites.

### 🔵 Low severity fixes

- **L1 (Tool identification)**: User-Agent now includes `webpath-scan/1.1 (authorized-testing)` for transparency.
- **L2 (Output organization)**: Each run creates a timestamped subdirectory (e.g., `output/probe_20260917_161530/`) so multiple runs don't collide.

### 📝 Structural improvements

- Shared helpers extracted to `lib/WebPathCommon.ps1` (config loader, URL validator, secret redactor, file writer, etc.)
- All scripts now use `System.Diagnostics.Process` with explicit `StartInfo` (no shell interpolation of arguments).
- Config supports both `.psd1` (PowerShell data) and key=value text files.

### 📄 Legal / commercial

- Added `LICENSE` (MIT + "Additional Terms" requiring authorized-only use).
- README expanded with SSRF-defense section, self-check section, and commercial guidance.

---

## v1.0 (predecessor) — known issues

- C1: `outDir` hardcoded to other agent's workspace.
- H1: No URL validation (SSRF).
- H2: Response bodies saved verbatim (no secret redaction).
- H3: `curl.exe` resolved via PATH (hijackable).
- M1: `delay_ms: 0` default allowed flooding.
- M2: `threads: 10` config ignored (code is sequential).
- M3: TARGET_HOST placeholder silently produces DNS errors.
- M4: Filename collisions overwrite prior results.
