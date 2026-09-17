# webpath-scan v1.1

> Web 路径/接口探测与响应采集套件（PowerShell）

⚖️ **MIT License** — 商用免费，但**仅限授权测试**（详见 [LICENSE](./LICENSE)）。

---

## ⚠️ 使用前必读

本工具仅限用于**你自己拥有**或**已取得书面授权**的系统。
未经授权对他人系统进行扫描可能违反《网络安全法》、《刑法》第285条（非法获取计算机信息系统数据）、CFAA（18 U.S.C. § 1030）及其他适用法律。

下载、安装或使用本工具即视为同意 [LICENSE](./LICENSE) 中的条款，作者不对任何滥用行为负责。

---

## 🆕 v1.1 安全增强（vs v1.0）

| ID | 修复项 | 影响 |
|----|--------|------|
| **C1** | 输出目录硬编码修复（不再写到他人的 workspace）| 🔴 Critical |
| **H1** | URL 白名单 + 私网 IP 阻断（SSRF 防御）| 🟠 High |
| **H2** | 响应 body 自动脱敏（API key/token/password）| 🟠 High |
| **H3** | curl 用绝对路径（抗 PATH 劫持）| 🟠 High |
| **M1** | delay_ms 最小值强制 50ms（防 DoS）| 🟡 Medium |
| **M3** | TARGET_HOST 占位符拒绝（不会跑成 TARGET）| 🟡 Medium |
| **M4** | 输出文件名加序号前缀（防覆盖）| 🟡 Medium |
| **L1** | UA 标识工具身份（不纯伪装 Mozilla）| 🔵 Low |
| **L2** | 输出目录带时间戳（多次跑不冲突）| 🔵 Low |

详细审计报告见 [CHANGELOG.md](./CHANGELOG.md)。

---

## 一、这是干什么

给定一个目标 URL，按内置路径字典逐个发起请求，采集 HTTP 状态码、响应头和响应体，汇总成 CSV。

**不做**的事：不爆破密码、不注入 payload、不拿 shell、不绕过防护。只负责"把门挨个敲一遍，记下谁开了"。

适用场景：
- 授权测试前的资产面梳理
- 自查敏感路径暴露（Actuator / Swagger / 备份 / 调试入口）
- 乙方交付前的结果整理
- 自己工具商业化的最小入侵面准备

---

## 二、环境

- Windows 10/11（PowerShell 5.1+）或 PowerShell Core 7+（Linux/macOS）
- 无第三方依赖（用系统 `curl.exe`）

```powershell
$PSVersionTable.PSVersion
```

---

## 三、四个脚本的区别

| 脚本 | 定位 | timeout | body | redirect |
|------|------|---------|------|----------|
| `probe.ps1` | 主流程（200+ 路径）| 8s | ✅ | ❌ |
| `probe2.ps1` | 快速模式（80 路径）| 3s | ❌ | ❌ |
| `probe3.ps1` | 深度模式（跟 3 重定向）| 15s | ✅ 32KB | ✅ |
| `probe4.ps1` | API 专项（80 `/api/*` 端点）| 8s | ✅ 16KB | ❌ |

建议顺序：**probe2 → probe → probe4 → probe3**

---

## 四、快速开始

### 最简用法（命令行传参）

```powershell
.\probe.ps1 -Target 'example.com'
```

### 用配置文件

1. 编辑 `config.psd1`，把 `target` 改成你的目标
2. 跑：

```powershell
.\probe.ps1 -Config .\config.psd1
```

### 混合（命令行覆盖配置文件）

```powershell
.\probe.ps1 -Config .\config.psd1 -DelayMs 200 -OutputDir 'D:\results\client1'
```

### 高级：扫描内部网（需明确授权）

```powershell
# ⚠️ 仅限对授权的内网/堡垒机/开发环境使用
.\probe.ps1 -Target '192.168.1.100:8080' -AllowPrivate -DelayMs 100
```

---

## 五、配置说明

`config.psd1`：

| 参数 | 含义 | 默认 | 备注 |
|------|------|------|------|
| `target` | 目标（域名或 IP）| `TARGET_HOST`（必填，否则拒绝）| 私网/loopback/link-local 默认拒绝 |
| `timeout_sec` | 单次请求超时 | 8 | 深度模式 15s |
| `delay_ms` | 请求间隔 | 100 | **最小 50ms**强制 |
| `follow_redirect` | 跟随 3xx 重定向 | $false | 跟随最多 3 次（防 SSRF）|
| `output_dir` | 输出目录 | `output` | 默认脚本同目录 |
| `save_body` | 是否保存 body | $true | 快速模式关闭 |
| `max_body_kb` | 单 body 大小上限 | 8 | 防 OOM |
| `user_agent` | UA | `webpath-scan/1.1 (authorized-testing)` | 标识工具身份 |
| `allow_private` | 允许私网扫描 | $false | $true 时仍 WARN |

---

## 六、输出结构

每次运行生成**带时间戳的子目录**（避免覆盖）：

```
output/
└── probe_20260917_161530/
    ├── summary.csv           # 状态码 + 大小汇总
    ├── head_001_admin.txt     # HEAD 响应
    ├── body_001_admin.txt     # GET 响应（自动脱敏）
    ├── head_002_api.txt
    └── ...
```

---

## 七、SSRF / 私网防护说明

v1.1 默认**拒绝**以下目标：

| 范围 | 理由 |
|------|------|
| `10.0.0.0/8` | RFC 1918 私网 |
| `172.16.0.0/12` | RFC 1918 私网 |
| `192.168.0.0/16` | RFC 1918 私网 |
| `127.0.0.0/8` | loopback |
| `169.254.0.0/16` | link-local（含云元数据 `169.254.169.254`）|
| `0.0.0.0/8` | unspecified |
| `224.0.0.0/4` | multicast/reserved |

如需扫描内网（已授权环境），加 `-AllowPrivate` 并**理解后果**。

---

## 八、商用要点

1. ✅ **MIT 许可** — 可商用、可改、可转售
2. ⚠️ **免责条款** — LICENSE 第 2 段加 "Additional Terms"，要求使用者承诺仅授权测试
3. ⚠️ **合规建议** — 部署为 SaaS 时，建议：
   - 加用户注册 + 授权审核
   - 记录扫描目标（白名单）
   - 不提供"匿名扫描"功能

---

## 九、自检（部署前跑一次）

```powershell
# 1. 语法检查
Get-ChildItem *.ps1 | ForEach-Object { [System.Management.Automation.PSParser]::Tokenize((Get-Content $_ -Raw), [ref]$null) | Out-Null; Write-Host "$($_.Name) OK" }

# 2. 私网拒绝测试（应该报错）
try { .\probe.ps1 -Target '127.0.0.1' } catch { Write-Host "[OK] refused: $_" }

# 3. 占位符拒绝测试（应该报错）
try { .\probe.ps1 } catch { Write-Host "[OK] refused: $_" }

# 4. 正常扫描（应该跑通）
.\probe2.ps1 -Target 'scanme.nmap.org' -OutputDir '.\test-output'
Get-ChildItem test-output/probe2-*/summary2.csv | Format-Table FullName
```

---

## 十、变更历史

见 [CHANGELOG.md](./CHANGELOG.md)。

---

## 致谢

内置路径字典为示例场景整理（admin/actuator/swagger 等公开情报）。扫描其他系统请自行编辑脚本顶部的 `$paths` / `$endpoints` 数组。
