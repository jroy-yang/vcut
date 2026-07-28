"""Tests for the bundled-ffmpeg auto-detection logic."""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))
import vcut  # noqa: E402


def test_bundled_ffmpeg_paths_no_bundle():
    """When sys._MEIPASS is unset and no exe next to it, returns None."""
    # Make sure we don't have a real bundle env
    if hasattr(sys, "_MEIPASS"):
        delattr(sys, "_MEIPASS")
    # Point sys.executable to a non-bundle path
    original = sys.executable
    sys.executable = str(Path(__file__).parent / "__init__.py")  # dir with no ffmpeg
    try:
        result = vcut._bundled_ffmpeg_paths()
        # Should return None because there's no ffmpeg.exe in this test dir
        assert result is None
    finally:
        sys.executable = original


def test_bundled_ffmpeg_paths_with_meipass(monkeypatch, tmp_path):
    """When _MEIPASS points to a dir with ffmpeg.exe + ffprobe.exe, return paths."""
    # Create fake bundle dir
    bundle = tmp_path / "fakebundle"
    bundle.mkdir()
    (bundle / "ffmpeg.exe").write_bytes(b"FAKE")
    (bundle / "ffprobe.exe").write_bytes(b"FAKE")

    monkeypatch.setattr(sys, "_MEIPASS", str(bundle), raising=False)
    result = vcut._bundled_ffmpeg_paths()
    assert result is not None
    ff, fp = result
    assert Path(ff).name == "ffmpeg.exe"
    assert Path(fp).name == "ffprobe.exe"
    assert Path(ff).exists()
    assert Path(fp).exists()


def test_bundled_ffmpeg_paths_partial(monkeypatch, tmp_path):
    """If only one of ffmpeg/ffprobe exists, returns None (must be both)."""
    bundle = tmp_path / "partial"
    bundle.mkdir()
    (bundle / "ffmpeg.exe").write_bytes(b"FAKE")
    # no ffprobe.exe

    monkeypatch.setattr(sys, "_MEIPASS", str(bundle), raising=False)
    result = vcut._bundled_ffmpeg_paths()
    assert result is None


def test_load_config_with_bundled(monkeypatch, tmp_path):
    """load_config() should pick up bundled paths when available."""
    bundle = tmp_path / "bundle2"
    bundle.mkdir()
    (bundle / "ffmpeg.exe").write_bytes(b"X")
    (bundle / "ffprobe.exe").write_bytes(b"X")

    monkeypatch.setattr(sys, "_MEIPASS", str(bundle), raising=False)
    cfg = vcut.load_config()
    # Should point to our fake bundle files
    assert "ffmpeg.exe" in cfg["ffmpeg_path"]
    assert "ffprobe.exe" in cfg["ffprobe_path"]