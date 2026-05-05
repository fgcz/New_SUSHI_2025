"""SUSHI application registry with auto-discovery."""

import importlib
import re
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


def get_all_apps_with_details() -> list[dict]:
    """Get all registered apps with their metadata.

    Returns:
        List of app details:
        [{"name": "FastQC", "category": "QC", "description": "...", "required_columns": [...]}]
    """
    apps = []
    for name, app_cls in SushiApp._registry.items():
        apps.append({
            "name": name,
            "category": getattr(app_cls, "category", "Other"),
            "description": getattr(app_cls, "description", ""),
            "required_columns": getattr(app_cls, "required_columns", []),
        })
    return apps


# --- App matching functions ---


def _normalize_header(header: str) -> str:
    """Normalize header by removing bracket annotations.

    e.g., "Read1 [File]" -> "Read1"
    """
    return re.sub(r"\s*\[.*?\]\s*", "", header).strip()


def _check_required_columns_satisfied(
    required_columns: list, dataset_headers: set[str]
) -> bool:
    """Check if dataset headers satisfy required columns.

    Args:
        required_columns: List of required column names. Can contain:
            - Strings for AND mode: ["Name", "Read1"] - all must be present
            - Nested lists for XOR mode: [["Read1", "Read2"]] - at least one must be present
        dataset_headers: Set of normalized dataset headers

    Returns:
        True if requirements are satisfied
    """
    if not required_columns:
        return True

    for requirement in required_columns:
        if isinstance(requirement, list):
            # XOR mode: at least one of these must be present
            if not any(col in dataset_headers for col in requirement):
                return False
        else:
            # AND mode: this specific column must be present
            if requirement not in dataset_headers:
                return False

    return True


def get_runnable_apps(headers: list[str]) -> list[dict]:
    """Get applications that can run on a dataset with given headers.

    Args:
        headers: List of dataset headers (e.g., ["Name", "Read1 [File]"])

    Returns:
        List of dicts grouped by category:
        [{"category": "QC", "apps": [{"class_name": "FastQC", "description": "..."}]}]
    """
    normalized_headers = {_normalize_header(h) for h in headers}

    matching_apps: dict[str, list[dict]] = {}

    for name, app_cls in SushiApp._registry.items():
        required = getattr(app_cls, "required_columns", []) or []

        if _check_required_columns_satisfied(required, normalized_headers):
            category = getattr(app_cls, "category", "Other")
            if category not in matching_apps:
                matching_apps[category] = []
            matching_apps[category].append({
                "class_name": name,
                "description": getattr(app_cls, "description", ""),
            })

    # Convert to list format, sorted by category and app name
    return [
        {"category": cat, "apps": sorted(matching_apps[cat], key=lambda x: x["class_name"])}
        for cat in sorted(matching_apps.keys())
    ]
