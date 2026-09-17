# webpath-scan — Gumroad Product Page

> 可直接复制到 Gumroad 的"Product"页字段（Title / Description / Cover / etc.）

---

## Product Name
**webpath-scan v1.1 — Web Path Discovery Toolkit (Windows)**

## Tagline (一行简介)
PowerShell-based web path discovery + response capture — self-contained .exe, MIT licensed, with built-in SSRF defense and secret redaction.

## Price
- **Personal**: $29
- **Commercial team (≤5 users)**: $99
- **Enterprise (unlimited)**: $299

（建议：先 7 折 $19 拉销量，30 天后涨到 $29。）

## Thumbnail / Cover 建议
- 尺寸：1280 × 720 px（PNG）
- 文字：`webpath-scan` 大字 + `v1.1` + `MIT` + `Windows`（不要超过 4 个关键词）
- 配色：黑底 + 蓝/绿点缀（暗示"安全 / 终端"）

## Short Description（≤ 200 字，Gumroad 卡片显示）
```
Web path scanner for Windows. 4 scan modes (main / fast / deep / API),
self-contained .exe (no PowerShell install), MIT licensed.
v1.1 adds SSRF defense + auto secret redaction. Demo target included.
```

## Long Description（Gumroad 完整描述）

```markdown
# webpath-scan v1.1 — Web Path Discovery Toolkit

**For pentesters, red teamers, and security-conscious developers.**
Scan a target web server for exposed endpoints (admin panels, actuator, swagger,
backup files, debug interfaces) and capture the responses. Pre-compiled .exe
— **no PowerShell install required**.

## What's new in v1.1 (vs v1.0)

- **SSRF defense** — refuses to scan private IPs (10/8, 172.16/12, 192.168/16,
  127/8, 169.254/16 incl. cloud metadata, 0/8, 224/4)
- **Auto secret redaction** — response bodies are masked for api_key, password,
  AWS/Azure/GCP credentials, JWT, and similar patterns before being saved
- **PATH-hijack safe** — uses absolute path to curl.exe, not PATH search
- **DoS guard** — minimum 50 ms delay between requests, even if you set 0
- **Better UX** — timestamped output dirs, sequence-numbered files, demo mode

## 4 scan modes

| Script   | Mode            | Timeout | Save body | Follow redirect |
|----------|-----------------|---------|-----------|-----------------|
| probe    | main (200+ paths) | 8 s  | yes       | no              |
| probe2   | fast (80 paths)   | 3 s  | no        | no              |
| probe3   | deep              | 15 s | 32 KB     | yes (max 3)     |
| probe4   | API (80 endpoints) | 8 s  | 16 KB     | no              |

## Quick start (30 seconds)

```powershell
# Legal demo: scanme.nmap.org (Nmap's authorized test server)
.\probe2.exe -Demo

# Your own target
.\probe.exe -Target "yourcompany-test.example" -Throttle 5

# Config file
.\probe.exe -Config .\config.psd1
```

Results land in `output\<mode>_<timestamp>\` with `summary.csv` + per-path
HEAD/response body files (redacted).

## What you get

- `webpath-scan_v1.1.zip` (~58 KB)
  - 4 × .ps1 scripts
  - 4 × pre-compiled .exe (x64, self-contained)
  - `lib\WebPathCommon.ps1` (shared security helpers)
  - `config.psd1` (PowerShell data file)
  - `README.md`, `CHANGELOG.md`, `LICENSE`
  - `SHA256SUMS.txt` for integrity check
  - 10-test self-check script

## License

MIT — use in commercial projects, modify, redistribute. **Authorized
testing only** — see LICENSE §"Additional Terms".

## Disclaimer

This tool is provided for use only against systems you own or have explicit
written authorization to test. Unauthorized use may violate CFAA,
PRC Cybersecurity Law, EU Directive 2013/40/EU, or other applicable laws.
The authors disclaim responsibility for misuse.

## System requirements

- Windows 10 / 11 (or Windows Server 2016+)
- 64-bit
- No PowerShell install needed (.exe bundles the runtime)
- Outbound HTTPS access to your target
```

## Files to attach
- `webpath-scan_v1.1.zip` (~58 KB)
- (Optional) `webpath-scan_thumbnail.png` (你做的 1280×720 封面)

## Tags / Categories
- "Security"
- "Developer tools"
- "Windows"
- "Pentesting"

## FAQ (Gumroad 自动展示)

> **Q: Does this work on macOS / Linux?**
> A: No — this is Windows-only (.exe + .ps1). The .ps1 scripts run on
> PowerShell 7+ on Linux/macOS but the bundled .exe is Windows x64.

> **Q: Will the vendor update it?**
> A: Yes, free updates to anyone who bought a license — just re-download
> from your Gumroad library.

> **Q: Can I get a refund?**
> A: Within 7 days of purchase, yes, per Gumroad policy.

---

## 🚀 快速上架步骤

### A. GitHub Release（推荐——给技术买家）

```bash
# 第一次：建远端仓库（github.com/new → Create）
# 然后本地：
cd C:\Users\Lenovo\Desktop\webpath-scan_v1.1
git init
git add .
git commit -m "v1.1: security hardening + .exe + demo mode"
git branch -M main
git remote add origin https://github.com/<你的用户名>/webpath-scan.git
git push -u origin main

# 上传 release
.\release.ps1 -Version "1.1" -Repo "<你的用户名>/webpath-scan"
```

### B. Gumroad（上架销售）

1. 注册 https://app.gumroad.com/signup
2. New Product → 上传 `webpath-scan_v1.1.zip`
3. 粘贴上面的"Long Description"作为 product description
4. 设定价格（建议起售 $19 → 7 天后 $29）
5. Publish

### C. GitHub Pages（可选，做个落地页）

1. 仓库 Settings → Pages → Source: `main` branch, `/ (root)`
2. 5 分钟后访问 `https://<你的用户名>.github.io/webpath-scan/`
