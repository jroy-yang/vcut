# 标签
git tag v1.1
git push origin v1.1
# → 触发 .github/workflows/release.yml
# → 自动：跑 self-check → 编译 .exe → 打 ZIP → SHA-256 → 创建 GitHub Release

# 如果 release 跑挂了，本地手动重试
.\release.ps1 -Version "1.1" -Repo "<你的用户名>/webpath-scan"
