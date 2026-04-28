"""SUSHI application registry with auto-discovery."""

import importlib
from pathlib import Path

from sushi_apps.base import SushiApp

# Files that are not app modules
_EXCLUDED = {"__init__", "base", "config", "r_heredoc"}

# Auto-discover and import all app modules from this directory
_this_dir = Path(__file__).parent

for _py_file in _this_dir.glob("*.py"):
    if _py_file.stem not in _EXCLUDED:
        importlib.import_module(f"sushi_apps.{_py_file.stem}")


def get_app(name: str) -> SushiApp:
    """Get an app instance by name."""
    if name not in SushiApp._registry:
        available = ", ".join(SushiApp._registry.keys())
        raise ValueError(f"Unknown app: {name}. Available: {available}")
    return SushiApp._registry[name]()


def list_apps() -> list[str]:
    """List all registered app names."""
    return list(SushiApp._registry.keys())


def get_app_class(name: str) -> type[SushiApp]:
    """Get the app class (not instance) by name."""
    if name not in SushiApp._registry:
        raise ValueError(f"Unknown app: {name}")
    return SushiApp._registry[name]
