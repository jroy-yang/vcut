"""Build vcut with PyInstaller, bundling ffmpeg + ffprobe + required DLLs.

Cross-platform:
- Reads ffmpeg bin dir from env VCUT_FFMPEG_BIN (set by CI workflow)
- Falls back to a per-OS default search:
    - Windows: ~/Downloads/ffmpeg-gpl/.../bin (manual download)
    - macOS:   vendor/ffmpeg/bin (CI default)
    - Linux:   vendor/ffmpeg/bin (CI default)
- Uses platform-correct separator for --add-binary (; on Windows, : elsewhere)
"""
from __future__ import annotations

import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent
DIST = ROOT / "dist"
BUILD = ROOT / "build"
SPEC = ROOT / "vcut.spec"


def find_ffmpeg_bin() -> Path:
    """Locate ffmpeg/ffprobe binary directory."""
    # 1. explicit env var (CI sets this)
    env = os.environ.get("VCUT_FFMPEG_BIN")
    if env:
        p = Path(env)
        if p.exists() and (p / "ffmpeg").exists() or (p / "ffmpeg.exe").exists():
            return p
    # 2. vendored local copy
    vendor = ROOT / "vendor" / "ffmpeg" / "bin"
    if vendor.exists():
        return vendor
    # 3. Windows dev fallback
    win_default = (
        Path.home() / "Downloads" / "ffmpeg-gpl"
        / "ffmpeg-master-latest-win64-gpl-shared" / "bin"
    )
    if win_default.exists():
        return win_default
    sys.exit(
        "[ERROR] ffmpeg binary directory not found.\n"
        "  Set VCUT_FFMPEG_BIN env var, or place files in vendor/ffmpeg/bin/,\n"
        "  or download ffmpeg to ~/Downloads/ffmpeg-gpl/.../bin (Windows)."
    )


def main() -> int:
    # Clean previous build artifacts
    for d in (DIST, BUILD):
        if d.exists():
            shutil.rmtree(d)
    if SPEC.exists():
        SPEC.unlink()

    ffmpeg_bin = find_ffmpeg_bin()
    system = platform.system().lower()  # 'windows' | 'darwin' | 'linux'

    # Files to bundle: ffmpeg + ffprobe + DLLs (skip ffplay)
    bundled = sorted(
        p for p in ffmpeg_bin.iterdir()
        if p.is_file()
        and (
            p.name in ("ffmpeg", "ffmpeg.exe", "ffprobe", "ffprobe.exe")
            or p.suffix in (".dll", ".so", ".dylib")
        )
        and "ffplay" not in p.name
    )

    if not bundled:
        sys.exit(f"[ERROR] no ffmpeg/ffprobe found in {ffmpeg_bin}")

    print(f"[build] platform: {system}")
    print(f"[build] bundling {len(bundled)} files from {ffmpeg_bin}:")
    for f in bundled:
        print(f"   - {f.name} ({f.stat().st_size / 1e6:.1f} MB)")

    # Platform-correct separator for --add-binary
    sep = ";" if system == "windows" else ":"

    add_binaries = [f"--add-binary={f}{sep}." for f in bundled]

    hidden_imports = [
        "--hidden-import=tkinter",
        "--hidden-import=tkinter.ttk",
        "--hidden-import=tkinter.filedialog",
        "--hidden-import=tkinter.messagebox",
    ]

    # Icon only on Windows; .ico doesn't apply on macOS/Linux
    icon_arg = []
    ico = ROOT / "vcut.ico"
    if system == "windows" and ico.exists():
        icon_arg = [f"--icon={ico}"]

    # Output binary name (no .exe suffix on POSIX)
    binary_name = "vcut.exe" if system == "windows" else "vcut"

    cmd = [
        sys.executable, "-m", "PyInstaller",
        f"--name={binary_name.removesuffix('.exe')}",
        "--onefile",
        "--noconsole",
        "--clean",
        *icon_arg,
        *hidden_imports,
        *add_binaries,
        str(ROOT / "vcut.py"),
    ]

    print(f"\n[build] running: {' '.join(cmd)}\n")
    result = subprocess.run(cmd, cwd=str(ROOT))
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())