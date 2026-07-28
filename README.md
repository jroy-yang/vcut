# vcut - 本地视频剪辑器

> 纯本地 Windows 视频剪辑工具。Python Tkinter GUI + 内嵌 ffmpeg,**双击就跑,零额外依赖**。

![vcut icon](vcut-icon-preview.png)

[![Release](https://img.shields.io/github/v/release/jroy-yang/vcut?style=flat-square)](https://github.com/jroy-yang/vcut/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/jroy-yang/vcut/release.yml?style=flat-square&label=build)](https://github.com/jroy-yang/vcut/actions)
[![License](https://img.shields.io/github/license/jroy-yang/vcut?style=flat-square)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-12%20passed-brightgreen?style=flat-square)](tests/)

## ✨ 特性

- 📂 **打开视频** — mp4 / mov / mkv / avi / webm / flv / wmv
- 🔵🔴 **设入点 / 出点**,加入片段到时间线
- ➕ **多片段拼接** — 按时序拼接,支持上下移动、删除
- 🎵 **添加 BGM** — 本地 mp3 / wav / m4a / aac / ogg
- 🎤 **旁白文字** → OpenAI TTS 合成(需 API key)
- 🚀 **一键导出 mp4**

## 🚀 快速开始(推荐)

下载 `vcut.exe`,双击运行。**不需要安装 Python,不需要安装 ffmpeg** —— 一切都打包进去了。

| 文件 | 大小 | 说明 |
|---|---|---|
| `vcut-0.1.0-win64.zip` | ~74 MB | 内嵌 ffmpeg + ffprobe,Windows 64 位 |

### 验证下载完整性

每个发布都附带 `SHA256SUMS.txt`:
```powershell
certutil -hashfile vcut.exe SHA256
```
对照 `.sha256` 文件验证。

---

## 🛠️ 开发者安装

如果你想从源码运行:

### 1. 安装依赖

- **Python 3.10+**(Windows 安装包自带 tkinter)
- **ffmpeg** + ffprobe(已加入 PATH,或在「设置」里指定路径)

下载 ffmpeg:https://www.gyan.dev/ffmpeg/builds/

### 2. 启动

双击 `run.bat`,或在命令行:
```powershell
cd C:\path\to\vcut
python vcut.py
```

## 📖 使用流程

1. **打开视频** → 选文件
2. **拖动时间滑块**到你想裁剪的位置
3. 按 **I** 设入点,**O** 设出点 → **加入片段**
4. 重复 2-3 加入更多片段(按时序拼接)
5. (可选)选 BGM + 写旁白文字 → 用 OpenAI TTS 生成
6. **导出** → 选输出路径 → 等几秒到几十秒

## ⌨️ 快捷键

| 键 | 动作 |
|---|---|
| `I` | 设当前位置为入点 |
| `O` | 设当前位置为出点 |
| `A` | 把当前入/出点加入片段列表 |
| `←` / `→` | 1 秒步进 |

## 🎤 OpenAI TTS

- 需要在「设置」里填 API key(或设置环境变量 `OPENAI_API_KEY`)
- key 仅保存在 `~/.vcut/config.json`,不上传任何地方
- 可选声音:alloy / echo / fable / onyx / nova / shimmer / ash / coral / sage

## 💾 配置存储

`%USERPROFILE%\.vcut\`
- `config.json` — 设置(ffmpeg 路径、API key、默认声音)
- `_render/` — 临时分段
- `thumbs/` — 预览帧缓存
- `narration.mp3` — 上次生成的旁白

## 📦 从源码打包成 .exe

需要 **Python 3.10+** 和 **PyInstaller** (`pip install pyinstaller`)。

### 一次性打包

```powershell
python make_icon.py     # 生成 vcut.ico (纯 stdlib,零依赖)
python build.py         # 调 PyInstaller,产物 dist\vcut.exe
```

`build.py` 会:
1. 从 `Downloads/ffmpeg-gpl/.../bin/` 拉 ffmpeg/ffprobe + 全部 dll
2. 用 `vcut.ico` 作为 exe 图标
3. 用 `--onefile --noconsole --clean` 打包

### 自定义 ffmpeg 来源

如果你下载了别的 ffmpeg 版本(比如官方 gyan.dev),改 `build.py` 里的:

```python
FFMPEG_DIR = Path.home() / "Downloads" / "ffmpeg-gpl" / "ffmpeg-master-latest-win64-gpl-shared" / "bin"
```

指向你的 bin 目录即可。**注意:gpl 版 ffmpeg 内嵌进 exe 之后,这个 exe 也是 GPL**——分发时需遵守 GPL 义务(见下文)。

### 跨平台打包(自动)

推一个 tag 就能三平台出包。详细见 [.github/workflows/release.yml](.github/workflows/release.yml):

```bash
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions 会在 **ubuntu-latest / macos-latest / windows-latest** 三个 runner 同时打包,产物:
- `vcut-linux-x86_64.zip`
- `vcut-macos-universal2.zip` (Intel + Apple Silicon)
- `vcut-windows-x86_64.zip`

三个 runner 各自下载对应平台的 ffmpeg,用同一份源码打三个独立二进制。手动触发:`Actions → release → Run workflow`。

### 本地发布脚本

不依赖 GitHub Actions 也能手工出包:

```powershell
# 纯本地出包
powershell -File release.ps1

# 推到 GitHub Releases (需要 gh CLI)
powershell -File release.ps1 -Push -Repo "your-name/vcut"
```

## 🧪 运行测试

```powershell
pip install pytest
python -m pytest
```

12 个测试覆盖:
- `render_clips` 三种音轨路径(静默/单音轨/双音轨混音)+ 多片段 + 错误路径
- `ffprobe_duration` / `extract_thumb` 实际调 ffmpeg 出帧
- `_bundled_ffmpeg_paths` 内嵌检测(模拟 PyInstaller 环境)

不需要 GUI;只需要系统装了 ffmpeg(或 `tests/test_render.py` 会自动 skip)。

## ⚖️ GPL 致谢与许可

本软件 vcut 本身以 **MIT 协议** 发布。但内置的 [FFmpeg](https://ffmpeg.org/) 是 **GPLv3**,因此 `vcut.exe` 的二进制分发属于 GPL 衍生作品。

**分发时的义务**:
1. **提供 FFmpeg 源码获取方式** — 在你的分发页面附上:
   ```
   This software uses FFmpeg (https://ffmpeg.org), licensed under GPLv3.
   Source: https://github.com/BtbN/FFmpeg-Builds
   ```
2. **保留版权声明** — FFmpeg、libx264、LAME 等组件的许可信息
3. **不得添加额外限制** — 不能限制用户运行/修改/再分发

FFmpeg 二进制来源:[BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds)(win64-gpl-shared)。

### 如果你不想遵守 GPL

把 `build.py` 里的 ffmpeg 换成 **LGPL shared** 版(不含 libx264/libaom 等 GPL 编解码器):
- 下载:`ffmpeg-master-latest-win64-lgpl-shared.zip`
- 视频编码改用 `libopenh264`(vcut.py 里需要把 `-c:v libx264` 改成 `-c:v libopenh264`)
- 缺点:libopenh264 画质和速度都不如 libx264

## 🚧 限制 / 后续

- ❌ 不支持多轨道(视频只一条,音频最多两条:BGM + 旁白)
- ❌ 不支持转场 / 滤镜
- ❌ 不支持时间线缩略图轨道(只有进度条 + 单帧预览)
- ❌ 不支持撤销 / 重做
- ✅ 后续可加:调速、淡入淡出、字幕烧录、多段 BGM、视频拼接预览

## 📝 反馈 / 改进

直接跟 AI 助手说,你做的修改我会接着推进。

---

<sub>vcut 0.1.0 — 用 ❤️ 在 Windows 上写就</sub>