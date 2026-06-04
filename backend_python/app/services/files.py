"""File system service for directory listing with caching."""

import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from time import time
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.api.deps import CurrentUser


def format_size(size_bytes: int | None) -> str:
    """Format bytes to human-readable size string.

    Mimics Rails' number_to_human_size helper.

    Args:
        size_bytes: Size in bytes, or None for directories

    Returns:
        Human-readable string like "1.2 MB", "500 KB", or "-" for directories
    """
    if size_bytes is None:
        return "-"

    if size_bytes == 0:
        return "0 B"

    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    unit_index = 0
    size = float(size_bytes)

    while size >= 1024 and unit_index < len(units) - 1:
        size /= 1024
        unit_index += 1

    # Format: no decimals for bytes, 1 decimal for others
    if unit_index == 0:
        return f"{int(size)} B"
    return f"{size:.1f} {units[unit_index]}"


@dataclass
class FileInfo:
    """Information about a file or directory."""

    name: str
    type: str  # "file" or "directory"
    size: int | None  # bytes, None for directories
    modified: str  # ISO format timestamp

    def to_dict(self, human_sizes: bool = True) -> dict:
        return {
            "name": self.name,
            "type": self.type,
            "size": format_size(self.size) if human_sizes else self.size,
            "size_bytes": self.size,
            "modified": self.modified,
        }


def _get_cache_bucket(ttl_seconds: int = 30) -> int:
    """Get current time bucket for cache invalidation.

    Cache entries expire when the bucket changes.
    """
    return int(time() // ttl_seconds)


def _stat_to_fileinfo(path: Path) -> FileInfo:
    """Convert a path to FileInfo using a single stat call."""
    stat = path.stat()
    is_dir = path.is_dir()

    return FileInfo(
        name=path.name,
        type="directory" if is_dir else "file",
        size=None if is_dir else stat.st_size,
        modified=_format_timestamp(stat.st_mtime),
    )


def _format_timestamp(mtime: float) -> str:
    """Format modification time as ISO string."""
    from datetime import datetime, timezone
    return datetime.fromtimestamp(mtime, tz=timezone.utc).isoformat()


@lru_cache(maxsize=256)
def _list_directory_cached(
    directory: str,
    cache_bucket: int,  # Changes every TTL seconds, invalidating cache
) -> tuple[tuple[dict, ...], int]:
    """List directory contents with caching.

    Args:
        directory: Absolute path to directory
        cache_bucket: Time bucket for cache invalidation

    Returns:
        Tuple of (items as tuple of dicts, total count)
    """
    path = Path(directory)

    if not path.exists():
        return ((), 0)

    if not path.is_dir():
        return ((), 0)

    items = []
    for entry in path.iterdir():
        try:
            items.append(_stat_to_fileinfo(entry).to_dict(human_sizes=True))
        except (PermissionError, OSError):
            # Skip files we can't stat
            continue

    # Sort by modified time descending by default (matches Ruby behavior)
    items.sort(key=lambda x: x["modified"], reverse=True)

    return (tuple(items), len(items))


def list_directory(
    directory: str,
    page: int = 1,
    per_page: int = 50,
    sort_by: str = "name",
    sort_desc: bool = False,
    use_cache: bool = True,
    cache_ttl: int = 30,
) -> dict:
    """List directory contents with pagination and sorting.

    Args:
        directory: Absolute path to directory
        page: Page number (1-indexed)
        per_page: Items per page
        sort_by: Sort field ("name", "modified", "size")
        sort_desc: Sort descending if True
        use_cache: Whether to use caching
        cache_ttl: Cache TTL in seconds

    Returns:
        {
            "items": [...],
            "pagination": {"total": N, "page": P, "per_page": PP, "total_pages": TP}
        }
    """
    # Get cached or fresh listing
    if use_cache:
        cache_bucket = _get_cache_bucket(cache_ttl)
        items_tuple, total = _list_directory_cached(directory, cache_bucket)
        items = list(items_tuple)
    else:
        items_tuple, total = _list_directory_cached.__wrapped__(directory, 0)
        items = list(items_tuple)

    # Sort
    if sort_by == "modified":
        items.sort(key=lambda x: x["modified"], reverse=sort_desc)
    elif sort_by == "size":
        # Directories (None size) sort to end
        items.sort(key=lambda x: (x["size"] is None, x["size"] or 0), reverse=sort_desc)
    elif sort_by == "name":
        items.sort(key=lambda x: x["name"].lower(), reverse=sort_desc)

    # Paginate
    total_pages = (total + per_page - 1) // per_page if total > 0 else 1
    start = (page - 1) * per_page
    end = start + per_page
    page_items = items[start:end]

    return {
        "items": page_items,
        "pagination": {
            "total": total,
            "page": page,
            "per_page": per_page,
            "total_pages": total_pages,
        },
    }


def extract_project_number(path: str) -> int | None:
    """Extract project number from path like 'p1234/...' or 'p1234'.

    Returns:
        Project number as int, or None if invalid format
    """
    match = re.match(r"^p(\d+)", path)
    if match:
        return int(match.group(1))
    return None


def validate_path(path: str) -> bool:
    """Validate that path doesn't contain traversal attempts.

    Returns:
        True if path is safe, False otherwise
    """
    # Block empty path
    if not path:
        return False

    # Block path traversal
    if ".." in path:
        return False

    # Block absolute paths (should be relative to gstore)
    if path.startswith("/"):
        return False

    # Must start with project pattern
    if not re.match(r"^p\d+", path):
        return False

    return True


def get_path_info(full_path: str) -> dict | None:
    """Get information about a path (file or directory).

    Args:
        full_path: Absolute path to check

    Returns:
        Dict with path info, or None if path doesn't exist
    """
    path = Path(full_path)

    if not path.exists():
        return None

    try:
        stat = path.stat()
        is_dir = path.is_dir()

        return {
            "name": path.name,
            "type": "directory" if is_dir else "file",
            "size": format_size(None if is_dir else stat.st_size),
            "size_bytes": None if is_dir else stat.st_size,
            "modified": _format_timestamp(stat.st_mtime),
            "full_path": str(path),
        }
    except (PermissionError, OSError):
        return None


def is_file(full_path: str) -> bool:
    """Check if path points to a file (not directory).

    Args:
        full_path: Absolute path to check

    Returns:
        True if path is a file, False otherwise
    """
    path = Path(full_path)
    return path.is_file()


class FileService:
    """Orchestrates file/directory access: validation, authorization, and listing."""

    def get(
        self,
        path: str,
        caller: "CurrentUser",
        page: int = 1,
        per_page: int = 50,
        sort_by: str | None = None,
        sort_desc: bool | None = None,
    ) -> dict:
        """Validate path, check access, and return file info or directory listing."""
        from app.core.auth import require_project_access
        from app.core.config import settings
        from app.core.exceptions import NotFoundError, ValidationError

        path = path.strip("/")

        if not validate_path(path):
            raise ValidationError(
                f"Invalid path: '{path}'. Must start with project identifier "
                "(e.g., p1234) and cannot contain '..' or be absolute."
            )

        project_number = extract_project_number(path)
        if project_number is None:
            raise ValidationError(f"Could not extract project number from path: '{path}'")

        require_project_access(project_number, caller)

        full_path = f"{settings.GSTORE_DIR}/{path}"

        if is_file(full_path):
            info = get_path_info(full_path)
            if not info:
                raise NotFoundError("File", path)
            return {
                "type": "file",
                "name": info["name"],
                "path": path,
                "size": info["size"],
                "size_bytes": info["size_bytes"],
                "modified": info["modified"],
                "download_url": f"{settings.GSTORE_URL}/projects/{path}",
            }

        return self._list_dir(path, full_path, project_number, page, per_page, sort_by, sort_desc)

    def _list_dir(
        self,
        path: str,
        full_path: str,
        project_number: int,
        page: int,
        per_page: int,
        sort_by: str | None,
        sort_desc: bool | None,
    ) -> dict:
        is_root = bool(re.match(r"^p\d+$", path))

        if sort_by is None:
            sort_by = "modified" if is_root else "name"
            sort_desc = (sort_desc if sort_desc is not None else True) if is_root else (sort_desc if sort_desc is not None else False)
        else:
            if sort_by not in ("name", "modified", "size"):
                sort_by = "name"
            sort_desc = False if sort_desc is None else sort_desc

        result = list_directory(
            directory=full_path,
            page=page,
            per_page=per_page,
            sort_by=sort_by,
            sort_desc=sort_desc,
        )

        path_parts = path.split("/") if path else []
        parent_path = "/".join(path_parts[:-1]) if len(path_parts) > 1 else None

        result["type"] = "directory"
        result["path"] = path
        result["parent_path"] = parent_path
        result["project_number"] = project_number
        return result


def clear_cache() -> None:
    """Clear the directory listing cache."""
    _list_directory_cached.cache_clear()


def get_cache_info() -> dict:
    """Get cache statistics."""
    info = _list_directory_cached.cache_info()
    return {
        "hits": info.hits,
        "misses": info.misses,
        "size": info.currsize,
        "maxsize": info.maxsize,
    }
