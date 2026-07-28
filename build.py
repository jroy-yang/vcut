"""Build vcut.exe with PyInstaller, bundling ffmpeg.exe + ffprobe.exe + required DLLs.

Output: C:\\Users\\Lenovo\\Desktop\\vcut\\dist\\vcut.exe
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent
FFMPEG_DIR = Path.home() / "Downloads" / "ffmpeg-gpl" / "ffmpeg-master-latest-win64-gpl-shared" / "bin"
DIST = ROOT / "dist"
BUILD = ROOT / "build"
SPEC = ROOT / "vcut.spec"

# Clean previous build artifacts
for d in (DIST, BUILD):
    if d.exists():
        shutil.rmtree(d)
if SPEC.exists():
    SPEC.unlink()

# Files we need from ffmpeg/bin (exe + DLLs). Skip ffplay (we don't use it).
ffmpeg_files = sorted(p for p in FFMPEG_DIR.iterdir()
                      if p.is_file() and p.suffix in (".exe", ".dll")
                      and p.name != "ffplay.exe")

print(f"[build] bundling {len(ffmpeg_files)} files from ffmpeg/bin:")
for f in ffmpeg_files:
    print(f"   - {f.name} ({f.stat().st_size / 1e6:.1f} MB)")

# Build add-binary args: --add-binary "src;dest_dir_in_bundle"
add_binaries = [f"--add-binary={f};." for f in ffmpeg_files]

# Hidden imports we want explicitly (PyInstaller can miss these)
hidden_imports = [
    "--hidden-import=tkinter",
    "--hidden-import=tkinter.ttk",
    "--hidden-import=tkinter.filedialog",
    "--hidden-import=tkinter.messagebox",
]

cmd = [
    sys.executable, "-m", "PyInstaller",
    "--name=vcut",
    "--onefile",
    "--noconsole",
    "--clean",
    f"--icon={ROOT / 'vcut.ico'}",
    *hidden_imports,
    *add_binaries,
    str(ROOT / "vcut.py"),
]

print(f"\n[build] running: {' '.join(cmd)}\n")
result = subprocess.run(cmd, cwd=str(ROOT))
sys.exit(result.returncode)