"""Smoke test that all imports succeed."""
import sys
from pathlib import Path

# Make sure vcut root is importable
ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))


def test_import_vcut():
    import vcut
    assert vcut.APP_NAME == "vcut"
    assert vcut.APP_VERSION  # non-empty


def test_app_dir_created():
    """vcut creates APP_DIR on import."""
    import vcut
    assert vcut.APP_DIR.exists()
    assert vcut.APP_DIR.is_dir()