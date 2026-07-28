"""
vcut - 轻量本地视频剪辑器
纯本地 Tkinter GUI + ffmpeg 后端。零额外依赖（Python 自带 tkinter）。

功能：
- 导入视频并预览（抽帧显示）
- 剪辑：选入点/出点、分割片段、删除片段
- 字幕/旁白：直接打字 → OpenAI TTS 合成（可选，没配也能跑）
- BGM：本地 mp3 或 wav
- 导出：ffmpeg 合成最终视频
"""

import os
import sys
import json
import shutil
import threading
import subprocess
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from tkinter import HORIZONTAL, VERTICAL
from pathlib import Path

APP_NAME = "vcut"
APP_VERSION = "0.1.0"
APP_DIR = Path.home() / ".vcut"
APP_DIR.mkdir(parents=True, exist_ok=True)
CONFIG_FILE = APP_DIR / "config.json"
SEEN_TUTORIAL = APP_DIR / "seen_tutorial.flag"


# ---------- config ----------

def _bundled_ffmpeg_paths() -> tuple[str, str] | None:
    """Detect bundled ffmpeg/ffprobe when running as a PyInstaller bundle.

    When vcut.exe is launched, PyInstaller unpacks bundled binaries into a temp
    dir and sets sys._MEIPASS. We check that dir first, then fall back to the
    directory containing the running executable (onefile mode).
    """
    candidates: list[Path] = []
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        candidates.append(Path(meipass))
    exe_dir = Path(getattr(sys, "executable", __file__)).resolve().parent
    candidates.append(exe_dir)
    for d in candidates:
        ff, fp = d / "ffmpeg.exe", d / "ffprobe.exe"
        if ff.exists() and fp.exists():
            return str(ff), str(fp)
    return None


def load_config() -> dict:
    if CONFIG_FILE.exists():
        try:
            cfg = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        except Exception:
            cfg = {}
    else:
        cfg = {}
    # Auto-fill bundled ffmpeg paths if user hasn't customized them
    if not cfg.get("ffmpeg_path") or cfg["ffmpeg_path"] == "ffmpeg":
        bundled = _bundled_ffmpeg_paths()
        if bundled:
            cfg["ffmpeg_path"], cfg["ffprobe_path"] = bundled
    cfg.setdefault("ffmpeg_path", "ffmpeg")
    cfg.setdefault("ffprobe_path", "ffprobe")
    cfg.setdefault("openai_api_key", os.environ.get("OPENAI_API_KEY", ""))
    cfg.setdefault("openai_voice", "alloy")
    return cfg


def save_config(cfg: dict) -> None:
    CONFIG_FILE.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")


# ---------- ffmpeg helpers ----------

def run(cmd: list, timeout: int = 3600) -> tuple[int, str, str]:
    """Run a subprocess, return (rc, stdout, stderr)."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError as e:
        return 127, "", str(e)
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


def ffprobe_duration(path: str) -> float:
    cfg = load_config()
    rc, out, _ = run([cfg["ffprobe_path"], "-v", "error", "-show_entries", "format=duration",
                      "-of", "default=noprint_wrappers=1:nokey=1", path])
    if rc != 0:
        return 0.0
    try:
        return float(out.strip())
    except ValueError:
        return 0.0


def extract_thumb(path: str, at_seconds: float, out_path: str, w: int = 480) -> bool:
    """Extract a single frame from `path` at `at_seconds` to `out_path`.
    Caller is responsible for choosing a sensible extension (typically .png).
    """
    cfg = load_config()
    rc, _, _ = run([
        cfg["ffmpeg_path"], "-y", "-ss", f"{at_seconds}", "-i", path,
        "-frames:v", "1", "-vf", f"scale={w}:-1", out_path,
    ])
    return rc == 0 and Path(out_path).exists()


def render_clips(clips: list, audio_path: str | None, narration_path: str | None,
                 out_path: str) -> tuple[bool, str]:
    """clips: [{path, start, end}] in seconds. Compose a concat list."""
    cfg = load_config()
    tmp = APP_DIR / "_render"
    tmp.mkdir(exist_ok=True)
    seg_files: list[str] = []

    for i, c in enumerate(clips):
        dur = max(0.1, float(c["end"]) - float(c["start"]))
        seg = tmp / f"seg_{i:04d}.mp4"
        rc, _, err = run([
            cfg["ffmpeg_path"], "-y", "-ss", f"{c['start']}", "-i", c["path"],
            "-t", f"{dur}", "-c:v", "libx264", "-preset", "veryfast",
            "-crf", "20", "-c:a", "aac", "-b:a", "160k", str(seg)
        ])
        if rc != 0:
            return False, f"clip {i} failed: {err[-400:]}"
        seg_files.append(str(seg))

    # concat
    list_file = tmp / "list.txt"
    list_file.write_text("\n".join(f"file '{p.replace(chr(92), '/')}'" for p in seg_files), encoding="utf-8")
    concat_out = tmp / "concat.mp4"
    rc, _, err = run([
        cfg["ffmpeg_path"], "-y", "-f", "concat", "-safe", "0",
        "-i", str(list_file), "-c", "copy", str(concat_out)
    ])
    if rc != 0:
        return False, f"concat failed: {err[-400:]}"

    # mix audio
    # input 0 = concat_out (video), 1 = BGM (optional), 2 = narration (optional)
    inputs = ["-i", str(concat_out)]
    audio_filters = []  # list of filter chains that each produce a labeled stream
    labels: list[str] = []  # output labels from each audio filter chain
    if audio_path:
        inputs += ["-i", audio_path]
        label = "bgm"
        audio_filters.append(f"[1:a]volume=0.5[{label}]")
        labels.append(label)
    if narration_path:
        inputs += ["-i", narration_path]
        label = "nar"
        idx = len(labels) + 1  # 1=concat, 2=BGM, 3=narration
        audio_filters.append(f"[{idx}:a]volume=1.2[{label}]")
        labels.append(label)

    if audio_filters:
        if len(labels) == 1:
            # single audio: just use the labeled filter output, no amix needed
            filt_str = audio_filters[0]
            map_audio = f"[{labels[0]}]"
        else:
            # mix all audio streams
            amix = "[" + "][".join(labels) + f"]amix=inputs={len(labels)}:duration=first[aout]"
            audio_filters.append(amix)
            filt_str = ";\n".join(audio_filters)
            map_audio = "[aout]"
        rc, _, err = run([
            cfg["ffmpeg_path"], "-y", *inputs,
            "-filter_complex", filt_str,
            "-map", "0:v", "-map", map_audio,
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
            "-shortest", out_path,
        ])
    else:
        shutil.copy2(concat_out, out_path)
        rc = 0

    if rc != 0:
        return False, f"audio mix failed: {err[-400:]}"

    # cleanup
    for f in seg_files:
        try: Path(f).unlink()
        except Exception: pass
    try: concat_out.unlink()
    except Exception: pass
    try: list_file.unlink()
    except Exception: pass

    return True, "ok"


class ToolTip:
    """Simple hover tooltip for tkinter widgets."""
    def __init__(self, widget, text: str):
        self.widget = widget
        self.text = text
        self.tip: tk.Toplevel | None = None
        widget.bind("<Enter>", self._show)
        widget.bind("<Leave>", self._hide)

    def _show(self, _evt=None):
        if self.tip:
            return
        x = self.widget.winfo_root_x() + 20
        y = self.widget.winfo_root_y() + self.widget.winfo_height() + 4
        self.tip = tk.Toplevel(self.widget)
        self.tip.wm_overrideredirect(True)
        self.tip.wm_geometry(f"+{x}+{y}")
        lbl = ttk.Label(self.tip, text=self.text, background="#ffffe0",
                        relief="solid", borderwidth=1, padding=(6, 3),
                        font=("Microsoft YaHei", 9))
        lbl.pack()

    def _hide(self, _evt=None):
        if self.tip:
            self.tip.destroy()
            self.tip = None


def tts_openai(text: str, voice: str, out_path: str) -> tuple[bool, str]:
    cfg = load_config()
    key = cfg.get("openai_api_key") or os.environ.get("OPENAI_API_KEY", "")
    if not key:
        return False, "未配置 OpenAI API key（设置 → API Key）"
    import urllib.request
    import urllib.error
    body = json.dumps({"model": "tts-1", "input": text, "voice": voice}).encode("utf-8")
    req = urllib.request.Request(
        "https://api.openai.com/v1/audio/speech",
        data=body,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = resp.read()
        Path(out_path).write_bytes(data)
        return True, "ok"
    except urllib.error.HTTPError as e:
        return False, f"TTS HTTP {e.code}: {e.read().decode('utf-8', errors='ignore')[:300]}"
    except Exception as e:
        return False, f"TTS 失败: {e}"


# ---------- GUI ----------

class VCutApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title(f"{APP_NAME} {APP_VERSION}")
        self.root.geometry("1180x720")
        self.root.minsize(960, 600)

        self.cfg = load_config()
        self.video_path: str | None = None
        self.duration: float = 0.0
        self.thumb_dir = APP_DIR / "thumbs"
        self.thumb_dir.mkdir(exist_ok=True)

        self.clips_var = tk.StringVar(value="(空) — 点「加入片段」把当前入/出点加入剪辑列表")
        self.status_var = tk.StringVar(value="就绪")

        # Hold reference to PhotoImage so it isn't garbage-collected
        # (a common tkinter gotcha — image shows blank otherwise)
        self.preview_img: tk.PhotoImage | None = None

        self._build_ui()
        self._check_ffmpeg()

        # Auto-show tutorial on first launch
        if not SEEN_TUTORIAL.exists():
            try:
                SEEN_TUTORIAL.write_text("1", encoding="utf-8")
            except Exception:
                pass
            self.root.after(400, self.show_tutorial)

    def _build_ui(self):
        # top toolbar
        bar = ttk.Frame(self.root, padding=6)
        bar.pack(side=tk.TOP, fill=tk.X)

        ttk.Button(bar, text="📂 打开视频", command=self.on_open, width=14).pack(side=tk.LEFT, padx=2)
        ttk.Separator(bar, orient=tk.VERTICAL).pack(side=tk.LEFT, fill=tk.Y, padx=6)
        ttk.Button(bar, text="⚙ 设置", command=self.on_settings, width=10).pack(side=tk.LEFT, padx=2)
        ttk.Button(bar, text="❓ 怎么用", command=self.show_tutorial, width=10).pack(side=tk.LEFT, padx=2)
        ttk.Separator(bar, orient=tk.VERTICAL).pack(side=tk.LEFT, fill=tk.Y, padx=6)
        ttk.Button(bar, text="🚀 导出", command=self.on_export, width=12).pack(side=tk.RIGHT, padx=2)

        # main paned
        main = ttk.Panedwindow(self.root, orient=tk.HORIZONTAL)
        main.pack(fill=tk.BOTH, expand=True, padx=6, pady=4)

        # left: preview + timeline
        left = ttk.Frame(main)
        main.add(left, weight=3)

        self.preview_label = ttk.Label(left, text="(未加载视频)", anchor="center",
                                       background="#222", foreground="#ddd")
        self.preview_label.pack(fill=tk.BOTH, expand=True, pady=(0, 6))

        # timeline
        tl = ttk.LabelFrame(left, text="时间线 / 入出点", padding=6)
        tl.pack(fill=tk.X)
        self.scale = tk.Scale(tl, from_=0, to=100, orient=tk.HORIZONTAL, resolution=0.1,
                              command=self.on_seek, showvalue=True, length=600)
        self.scale.pack(fill=tk.X)
        btns = ttk.Frame(tl)
        btns.pack(fill=tk.X, pady=4)
        for txt, cmd in [
            ("⏮ 起点", lambda: self.scale.set(0)),
            ("🔵 设为入点 (I)", self.on_set_in),
            ("🔴 设为出点 (O)", self.on_set_out),
            ("🎬 抓帧预览", self.on_thumb),
            ("➕ 加入片段", self.on_add_clip),
        ]:
            b = ttk.Button(btns, text=txt, command=cmd, width=14)
            b.pack(side=tk.LEFT, padx=2, pady=2)
        self.in_var = tk.StringVar(value="IN: 0.00")
        self.out_var = tk.StringVar(value="OUT: 0.00")
        ttk.Label(btns, textvariable=self.in_var).pack(side=tk.LEFT, padx=8)
        ttk.Label(btns, textvariable=self.out_var).pack(side=tk.LEFT, padx=8)

        # right: clip list + audio
        right = ttk.Frame(main)
        main.add(right, weight=2)

        clips_box = ttk.LabelFrame(right, text="剪辑片段（按时序拼接）", padding=6)
        clips_box.pack(fill=tk.BOTH, expand=True)
        self.clips_list = tk.Listbox(clips_box, height=10)
        self.clips_list.pack(fill=tk.BOTH, expand=True)
        cb = ttk.Frame(clips_box)
        cb.pack(fill=tk.X, pady=4)
        for txt, cmd in [
            ("🗑 删除选中", self.on_del_clip),
            ("⬆ 上移", lambda: self.on_move_clip(-1)),
            ("⬇ 下移", lambda: self.on_move_clip(1)),
            ("🧹 清空", self.on_clear_clips),
        ]:
            b = ttk.Button(cb, text=txt, command=cmd, width=10)
            b.pack(side=tk.LEFT, padx=2, pady=2)

        audio_box = ttk.LabelFrame(right, text="音频（可选）", padding=6)
        audio_box.pack(fill=tk.X, pady=(6, 0))

        bgm_row = ttk.Frame(audio_box)
        bgm_row.pack(fill=tk.X)
        ttk.Button(bgm_row, text="🎵 选 BGM", command=self.on_choose_bgm, width=12).pack(side=tk.LEFT, padx=2)
        self.bgm_var = tk.StringVar(value="(无)")
        ttk.Label(bgm_row, textvariable=self.bgm_var, foreground="#666").pack(side=tk.LEFT, padx=6)

        ttk.Separator(audio_box, orient=HORIZONTAL).pack(fill=tk.X, pady=6)

        ttk.Label(audio_box, text="旁白文字：").pack(anchor=tk.W)
        self.narration_text = tk.Text(audio_box, height=4, wrap=tk.WORD)
        self.narration_text.pack(fill=tk.X, pady=2)

        nbtn = ttk.Frame(audio_box)
        nbtn.pack(fill=tk.X)
        ttk.Button(nbtn, text="🎤 用 OpenAI TTS 生成旁白",
                   command=self.on_tts, width=24).pack(side=tk.LEFT, padx=2)
        self.voice_var = tk.StringVar(value=self.cfg.get("openai_voice", "alloy"))
        ttk.Combobox(nbtn, textvariable=self.voice_var, width=10, state="readonly",
                     values=["alloy", "echo", "fable", "onyx", "nova", "shimmer", "ash", "coral", "sage"]).pack(side=tk.LEFT, padx=2)

        # status bar
        sb = ttk.Frame(self.root, padding=(8, 2))
        sb.pack(side=tk.BOTTOM, fill=tk.X)
        ttk.Label(sb, textvariable=self.status_var).pack(side=tk.LEFT)

        # keyboard
        self.root.bind("<KeyPress-i>", lambda e: self.on_set_in())
        self.root.bind("<KeyPress-o>", lambda e: self.on_set_out())
        self.root.bind("<KeyPress-a>", lambda e: self.on_add_clip())
        self.root.bind("<Left>",  lambda e: self._nudge(-1))
        self.root.bind("<Right>", lambda e: self._nudge(1))

        # state
        self.in_point = 0.0
        self.out_point = 0.0
        self.bgm_path: str | None = None
        self.narration_path: str | None = None
        self.clips: list[dict] = []
        self._refresh_clips()

        # Tooltips
        for w, tip in [
            (bar.winfo_children()[0], "打开一个视频文件 (mp4/mov/mkv/avi/webm)"),
            (bar.winfo_children()[2], "设置 ffmpeg 路径、OpenAI API key 等"),
            (bar.winfo_children()[3], "看使用说明"),
            (bar.winfo_children()[-1], "把当前片段拼接导出为 mp4"),
        ]:
            try:
                ToolTip(w, tip)
            except Exception:
                pass

    # ---------- actions ----------

    def show_tutorial(self):
        """Show a step-by-step guide for new users."""
        win = tk.Toplevel(self.root)
        win.title("vcut 使用指南")
        win.geometry("640x560")
        win.transient(self.root)

        text = tk.Text(win, wrap=tk.WORD, padx=16, pady=16, font=("Microsoft YaHei", 10))
        text.pack(fill=tk.BOTH, expand=True)
        scroll = ttk.Scrollbar(win, orient=VERTICAL, command=text.yview)
        scroll.pack(side=tk.RIGHT, fill=tk.Y)
        text.configure(yscrollcommand=scroll.set)

        content = """🎬 vcut - 本地视频剪辑器使用指南
================================

【五步走完一个视频】

第 1 步：打开视频
  点击顶部「📂 打开视频」，选一个视频文件
  （mp4 / mov / mkv / avi / webm 都可以）
  → 加载成功后底部会显示「已加载：xxx.mp4 时长 XX.XXs」

第 2 步：拖动时间滑块找位置
  下方进度条可以从左到右拖动
  - 按 ← / → 一次走 1 秒
  - 拖到你想裁剪的起点
  - 点击「🎬 抓帧预览」可看到当前位置的画面

第 3 步：设置入点和出点
  拖到起点 → 按 I（或点「🔵 设为入点」）
  拖到终点 → 按 O（或点「🔴 设为出点」）
  → 会出现「IN: 1.0  OUT: 3.0」这样的提示
  → 这一段就是要裁下来的片段

第 4 步：加入片段
  点「➕ 加入片段」（或按 A）
  → 右侧「剪辑片段」会出现一条记录
  → 重复第 2-4 步可以加多个片段
  → 多个片段会按时序拼接

第 5 步：导出
  点右上「🚀 导出」→ 选保存路径
  → 几秒到几十秒，桌面会收到成品 mp4

================================

【可选：加旁白和背景音乐】

背景音乐：
  点「🎵 选 BGM」选一个 mp3/wav
  → 导出时自动混入（音量 0.5）

旁白（用 OpenAI TTS）：
  1. 先点「⚙ 设置」填 OpenAI API key
  2. 在「旁白文字」框里写一段话
  3. 选个声音（alloy / nova / shimmer 等）
  4. 点「🎤 用 OpenAI TTS 生成旁白」
  → 导出时自动混入（音量 1.2，盖过 BGM）

================================

【快捷键】

  I      设入点
  O      设出点
  A      加入片段
  ←      后退 1 秒
  →      前进 1 秒

================================

【常见问题】

Q: 预览是黑的？
A: 点一下「🎬 抓帧预览」按钮。

Q: 导出失败？
A: 检查「⚙ 设置」里 ffmpeg 路径是否对。

Q: 怎么删掉一个片段？
A: 右侧列表里点中要删的，按「🗑 删除选中」。

Q: 片段顺序不对？
A: 用「⬆ 上移」「⬇ 下移」调整。

Q: 可以加转场/字幕/滤镜吗？
A: 当前版本不支持。告诉作者，以后加。

================================
祝玩得开心 ✨
"""
        text.insert("1.0", content)
        text.configure(state="disabled")

        ttk.Button(win, text="明白了", command=win.destroy).pack(pady=8)

    def _check_ffmpeg(self):
        rc, _, err = run([self.cfg["ffmpeg_path"], "-version"])
        if rc != 0:
            messagebox.showerror("ffmpeg 未找到",
                                 "请先安装 ffmpeg 并加入 PATH，或在「设置」里指定路径。\n\n"
                                 "下载：https://www.gyan.dev/ffmpeg/builds/")
            self.status_var.set("⚠ ffmpeg 未找到")
        else:
            self.status_var.set("✅ ffmpeg 就绪")

    def on_settings(self):
        win = tk.Toplevel(self.root)
        win.title("设置")
        win.geometry("420x280")

        ttk.Label(win, text="ffmpeg 路径：").grid(row=0, column=0, sticky=tk.W, padx=8, pady=6)
        ffmpeg_var = tk.StringVar(value=self.cfg.get("ffmpeg_path", "ffmpeg"))
        ttk.Entry(win, textvariable=ffmpeg_var, width=40).grid(row=0, column=1, padx=8)

        ttk.Label(win, text="ffprobe 路径：").grid(row=1, column=0, sticky=tk.W, padx=8, pady=6)
        ffprobe_var = tk.StringVar(value=self.cfg.get("ffprobe_path", "ffprobe"))
        ttk.Entry(win, textvariable=ffprobe_var, width=40).grid(row=1, column=1, padx=8)

        ttk.Label(win, text="OpenAI API Key：").grid(row=2, column=0, sticky=tk.W, padx=8, pady=6)
        key_var = tk.StringVar(value=self.cfg.get("openai_api_key", ""))
        key_entry = ttk.Entry(win, textvariable=key_var, width=40, show="*")
        key_entry.grid(row=2, column=1, padx=8)

        ttk.Label(win, text="(key 仅保存在本地 ~/.vcut/config.json)", foreground="#888").grid(
            row=3, column=1, sticky=tk.W, padx=8)

        def save():
            self.cfg["ffmpeg_path"] = ffmpeg_var.get().strip() or "ffmpeg"
            self.cfg["ffprobe_path"] = ffprobe_var.get().strip() or "ffprobe"
            self.cfg["openai_api_key"] = key_var.get().strip()
            self.cfg["openai_voice"] = self.voice_var.get()
            save_config(self.cfg)
            self.status_var.set("设置已保存")
            win.destroy()
            self._check_ffmpeg()

        ttk.Button(win, text="保存", command=save).grid(row=4, column=1, pady=14, sticky=tk.E)

    def on_open(self):
        path = filedialog.askopenfilename(
            title="选择视频",
            filetypes=[("视频文件", "*.mp4 *.mov *.mkv *.avi *.webm *.flv *.wmv"), ("所有文件", "*.*")],
        )
        if not path:
            return
        self.video_path = path
        self.duration = ffprobe_duration(path)
        if self.duration <= 0:
            messagebox.showerror("错误", f"无法读取视频时长：{path}")
            return
        self.scale.configure(to=self.duration)
        self.scale.set(0)
        self.in_point = 0.0
        self.out_point = min(2.0, self.duration)
        self._update_io_vars()
        self.status_var.set(f"已加载：{Path(path).name}  时长 {self.duration:.2f}s")
        self.on_thumb()
        # Friendly hint on first successful open
        if not (APP_DIR / "opened_once.flag").exists():
            try:
                (APP_DIR / "opened_once.flag").write_text("1", encoding="utf-8")
            except Exception:
                pass
            messagebox.showinfo(
                "已加载，下一步？",
                "视频已加载。\n\n"
                "接下来的 3 步：\n"
                "1. 拖动进度条到起点 → 按 I 设入点\n"
                "2. 拖到终点 → 按 O 设出点\n"
                "3. 点「➕ 加入片段」\n\n"
                "需要完整说明？点顶部「❓ 怎么用」。"
            )

    def on_seek(self, val):
        # debounce-ish: only update label
        if self.video_path:
            self.status_var.set(f"位置: {float(val):.2f}s / {self.duration:.2f}s")

    def _nudge(self, delta_sec: float):
        if not self.video_path:
            return
        v = max(0.0, min(self.duration, self.scale.get() + delta_sec))
        self.scale.set(v)

    def on_set_in(self):
        if not self.video_path:
            return
        self.in_point = float(self.scale.get())
        if self.out_point < self.in_point:
            self.out_point = min(self.duration, self.in_point + 1.0)
        self._update_io_vars()

    def on_set_out(self):
        if not self.video_path:
            return
        self.out_point = float(self.scale.get())
        if self.in_point > self.out_point:
            self.in_point = max(0.0, self.out_point - 1.0)
        self._update_io_vars()

    def _update_io_vars(self):
        self.in_var.set(f"IN: {self.in_point:.2f}")
        self.out_var.set(f"OUT: {self.out_point:.2f}")

    def on_thumb(self):
        if not self.video_path:
            return
        t = float(self.scale.get())
        out = self.thumb_dir / "preview.png"
        ok = extract_thumb(self.video_path, t, str(out), w=480)
        if ok:
            try:
                self.preview_img = tk.PhotoImage(file=str(out))
                self.preview_label.configure(image=self.preview_img, text="")
            except Exception as e:
                self.preview_label.configure(text=f"预览失败: {e}", image="")
        else:
            self.preview_label.configure(text="(抓帧失败)", image="")

    def on_add_clip(self):
        if not self.video_path:
            messagebox.showinfo("提示", "先打开一个视频")
            return
        s, e = sorted([self.in_point, self.out_point])
        if e - s < 0.1:
            messagebox.showwarning("太短", "入/出点间隔太短（< 0.1s）")
            return
        self.clips.append({"path": self.video_path, "start": float(s), "end": float(e)})
        self._refresh_clips()

    def _refresh_clips(self):
        self.clips_list.delete(0, tk.END)
        for i, c in enumerate(self.clips):
            dur = c["end"] - c["start"]
            self.clips_list.insert(tk.END, f"#{i+1}  {Path(c['path']).name}  {c['start']:.2f} → {c['end']:.2f}  ({dur:.2f}s)")
        self.clips_var.set(f"{len(self.clips)} 个片段")

    def on_del_clip(self):
        sel = self.clips_list.curselection()
        if not sel:
            return
        self.clips.pop(sel[0])
        self._refresh_clips()

    def on_move_clip(self, delta):
        sel = self.clips_list.curselection()
        if not sel:
            return
        i = sel[0]
        j = i + delta
        if j < 0 or j >= len(self.clips):
            return
        self.clips[i], self.clips[j] = self.clips[j], self.clips[i]
        self._refresh_clips()
        self.clips_list.selection_set(j)

    def on_clear_clips(self):
        self.clips.clear()
        self._refresh_clips()

    def on_choose_bgm(self):
        path = filedialog.askopenfilename(
            title="选 BGM",
            filetypes=[("音频", "*.mp3 *.wav *.m4a *.aac *.ogg"), ("所有", "*.*")],
        )
        if path:
            self.bgm_path = path
            self.bgm_var.set(Path(path).name)

    def on_tts(self):
        text = self.narration_text.get("1.0", tk.END).strip()
        if not text:
            messagebox.showinfo("提示", "先在「旁白文字」里写一段话")
            return
        voice = self.voice_var.get()
        out = APP_DIR / "narration.mp3"
        self.status_var.set("TTS 生成中…")
        self.root.update()

        def worker():
            ok, msg = tts_openai(text, voice, str(out))
            if ok:
                self.narration_path = str(out)
                self.root.after(0, lambda: self.status_var.set(f"✅ 旁白已生成：{out}"))
            else:
                self.root.after(0, lambda: messagebox.showerror("TTS 失败", msg))
                self.root.after(0, lambda: self.status_var.set("❌ TTS 失败"))

        threading.Thread(target=worker, daemon=True).start()

    def on_export(self):
        if not self.clips:
            messagebox.showinfo("提示", "剪辑片段为空，先加几个片段")
            return
        out = filedialog.asksaveasfilename(
            title="导出",
            defaultextension=".mp4",
            filetypes=[("mp4", "*.mp4")],
            initialfile="vcut_out.mp4",
        )
        if not out:
            return
        self.status_var.set("渲染中…")
        self.root.update()

        def worker():
            ok, msg = render_clips(self.clips, self.bgm_path, self.narration_path, out)
            if ok:
                self.root.after(0, lambda: self.status_var.set(f"✅ 导出完成：{out}"))
                self.root.after(0, lambda: messagebox.showinfo("完成", f"导出成功：\n{out}"))
            else:
                self.root.after(0, lambda: messagebox.showerror("导出失败", msg))
                self.root.after(0, lambda: self.status_var.set("❌ 导出失败"))

        threading.Thread(target=worker, daemon=True).start()


def main():
    root = tk.Tk()
    try:
        from tkinter import ttk as _t
        _t.Style().theme_use("clam")
    except Exception:
        pass
    VCutApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()