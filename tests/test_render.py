"""Tests for ffmpeg-related helpers.

Requires an actual ffmpeg/ffmpeg binary available. These tests use the same
ffmpeg that ships with vcut's bundled dev env
(Downloads/ffmpeg-gpl/.../bin) and fall back to PATH if not present.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))
import vcut  # noqa: E402


# --- locate a working ffmpeg ---

FFMPEG_BIN_CANDIDATE = (
    Path.home()
    / "Downloads" / "ffmpeg-gpl"
    / "ffmpeg-master-latest-win64-gpl-shared" / "bin" / "ffmpeg.exe"
)


def _has_ffmpeg() -> bool:
    return shutil.which("ffmpeg") is not None or FFMPEG_BIN_CANDIDATE.exists()


pytestmark = pytest.mark.skipif(
    not _has_ffmpeg(), reason="ffmpeg not available in this environment"
)


@pytest.fixture(scope="module")
def fixture_video(tmp_path_factory) -> Path:
    """Create a 2-second test video with silence audio, returns the path."""
    out = tmp_path_factory.mktemp("vid") / "input.mp4"
    ffmpeg = shutil.which("ffmpeg") or str(FFMPEG_BIN_CANDIDATE)
    cmd = [
        ffmpeg, "-y", "-f", "lavfi",
        "-i", "color=c=blue:size=320x240:rate=30:duration=2",
        "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
        "-c:v", "libx264", "-preset", "ultrafast",
        "-c:a", "aac", "-shortest",
        str(out),
    ]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, f"ffmpeg failed: {r.stderr[-500:]}"
    assert out.exists()
    return out


@pytest.fixture(scope="module")
def fixture_audio(tmp_path_factory) -> Path:
    """Create a 4-second BGM, returns the path."""
    out = tmp_path_factory.mktemp("aud") / "bgm.mp3"
    ffmpeg = shutil.which("ffmpeg") or str(FFMPEG_BIN_CANDIDATE)
    cmd = [
        ffmpeg, "-y", "-f", "lavfi",
        "-i", "sine=frequency=220:duration=4",
        "-c:a", "libmp3lame",
        str(out),
    ]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, f"ffmpeg failed: {r.stderr[-500:]}"
    return out


def test_ffmpeg_detected():
    """ffprobe_duration should succeed with the system ffmpeg."""
    # Just check the ffmpeg binary vcut resolves to is callable
    cfg = vcut.load_config()
    rc, _, _ = vcut.run([cfg["ffmpeg_path"], "-version"])
    assert rc == 0


def test_ffprobe_duration(fixture_video):
    dur = vcut.ffprobe_duration(str(fixture_video))
    assert 1.5 < dur < 2.5, f"expected ~2s, got {dur}"


def test_render_clips_silent(fixture_video, tmp_path):
    """Plain concat, no audio track."""
    out = tmp_path / "silent.mp4"
    clips = [{"path": str(fixture_video), "start": 0.0, "end": 1.5}]
    ok, msg = vcut.render_clips(clips, audio_path=None, narration_path=None, out_path=str(out))
    assert ok, f"render failed: {msg}"
    assert out.exists()
    assert out.stat().st_size > 0


def test_render_clips_single_audio(fixture_video, fixture_audio, tmp_path):
    """Single BGM audio path (the bug we fixed)."""
    out = tmp_path / "bgm.mp4"
    clips = [{"path": str(fixture_video), "start": 0.0, "end": 1.5}]
    ok, msg = vcut.render_clips(clips, audio_path=str(fixture_audio),
                                narration_path=None, out_path=str(out))
    assert ok, f"render failed: {msg}"
    assert out.exists()
    # verify output has both video and audio streams
    rc, out_text, _ = vcut.run([vcut.load_config()["ffprobe_path"], "-v", "error",
                                "-show_streams", str(out)])
    assert rc == 0
    assert "codec_type=video" in out_text
    assert "codec_type=audio" in out_text


def test_render_clips_mixed_audio(fixture_video, fixture_audio, tmp_path):
    """Both BGM + narration (amix path)."""
    out = tmp_path / "mix.mp4"
    clips = [{"path": str(fixture_video), "start": 0.0, "end": 1.5}]
    ok, msg = vcut.render_clips(clips, audio_path=str(fixture_audio),
                                narration_path=str(fixture_audio), out_path=str(out))
    assert ok, f"render failed: {msg}"
    assert out.exists()


def test_render_clips_multiple(fixture_video, tmp_path):
    """Multiple clips concatenated."""
    out = tmp_path / "multi.mp4"
    clips = [
        {"path": str(fixture_video), "start": 0.0, "end": 1.0},
        {"path": str(fixture_video), "start": 0.5, "end": 1.5},
    ]
    ok, msg = vcut.render_clips(clips, audio_path=None, narration_path=None,
                                out_path=str(out))
    assert ok, f"render failed: {msg}"
    assert out.exists()


def test_render_clips_invalid_returns_error(fixture_video, tmp_path):
    """Bad clip range should fail gracefully, not crash."""
    out = tmp_path / "bad.mp4"
    clips = [{"path": str(fixture_video), "start": 100.0, "end": 200.0}]  # way past end
    ok, msg = vcut.render_clips(clips, audio_path=None, narration_path=None,
                                out_path=str(out))
    # Either fails OR produces something; we just want no exception
    assert isinstance(ok, bool)
    assert isinstance(msg, str)


def test_extract_thumb(fixture_video, tmp_path):
    """extract_thumb produces a valid PNG (uses default .png extension now)."""
    out = tmp_path / "thumb.png"
    ok = vcut.extract_thumb(str(fixture_video), 1.0, str(out))
    assert ok
    assert out.exists()
    assert out.stat().st_size > 100  # not empty