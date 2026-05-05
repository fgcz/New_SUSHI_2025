"""File routes - gStore directory browsing."""

import re

from fastapi import APIRouter, Query

from app.api.deps import CurrentUserDep, require_project_access
from app.core.config import settings
from app.core.exceptions import NotFoundError, ValidationError
from app.services.files import (
    extract_project_number,
    get_path_info,
    is_file,
    list_directory,
    validate_path,
)

router = APIRouter()


def _is_project_root(path: str) -> bool:
    """Check if path is project root (e.g., 'p1234' with no subdirs)."""
    return bool(re.match(r"^p\d+$", path))


@router.get("/{path:path}", response_model=None)
def get_path(
    path: str,
    current_user: CurrentUserDep,
    page: int = Query(1, ge=1, description="Page number (1-indexed)"),
    per_page: int = Query(50, ge=1, le=500, description="Items per page"),
    sort_by: str | None = Query(None, description="Sort field: name, modified, size"),
    sort_desc: bool | None = Query(None, description="Sort descending"),
):
    """Get directory listing or file redirect.

    For directories: Returns paginated file listing.
    For files: Returns redirect URL to external gstore server.

    Path must start with a project identifier (e.g., p1234/analysis).
    Users can only access projects they are members of, unless they
    are employees (who have global read access).
    """
    # Normalize path
    path = path.strip("/")

    # Validate path format
    if not validate_path(path):
        raise ValidationError(
            f"Invalid path: '{path}'. Path must start with project identifier "
            "(e.g., p1234) and cannot contain '..' or be absolute."
        )

    # Extract project number for access control
    project_number = extract_project_number(path)
    if project_number is None:
        raise ValidationError(f"Could not extract project number from path: '{path}'")

    # Check access (employees bypass, others need project membership)
    require_project_access(project_number, current_user)

    # Build full path
    full_path = f"{settings.GSTORE_DIR}/{path}"

    # Check if path is a file or directory
    if is_file(full_path):
        return _handle_file(path, full_path)

    # It's a directory - return listing
    return _handle_directory(path, full_path, project_number, page, per_page, sort_by, sort_desc)


def _handle_file(path: str, full_path: str) -> dict:
    """Handle file path - return download info.

    Args:
        path: Relative path (e.g., p1234/file.bam)
        full_path: Absolute filesystem path

    Returns:
        Dict with file info and download URL
    """
    info = get_path_info(full_path)
    if not info:
        raise NotFoundError("File", path)

    # Build external download URL
    download_url = f"{settings.GSTORE_URL}/projects/{path}"

    return {
        "type": "file",
        "name": info["name"],
        "path": path,
        "size": info["size"],
        "size_bytes": info["size_bytes"],
        "modified": info["modified"],
        "download_url": download_url,
    }


def _handle_directory(
    path: str,
    full_path: str,
    project_number: int,
    page: int,
    per_page: int,
    sort_by: str | None,
    sort_desc: bool | None,
) -> dict:
    """Handle directory path - return listing.

    Args:
        path: Relative path (e.g., p1234/analysis)
        full_path: Absolute filesystem path
        project_number: Extracted project number
        page: Page number
        per_page: Items per page
        sort_by: Sort field (or None for default)
        sort_desc: Sort direction (or None for default)

    Returns:
        Paginated directory listing
    """
    # Default sorting: project root sorts by modified desc, subdirs by name asc
    if sort_by is None:
        if _is_project_root(path):
            sort_by = "modified"
            sort_desc = True if sort_desc is None else sort_desc
        else:
            sort_by = "name"
            sort_desc = False if sort_desc is None else sort_desc
    else:
        # Validate sort_by parameter
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

    # Calculate parent path for navigation
    path_parts = path.split("/") if path else []
    parent_path = "/".join(path_parts[:-1]) if len(path_parts) > 1 else None

    # Add path context to response
    result["type"] = "directory"
    result["path"] = path
    result["parent_path"] = parent_path
    result["project_number"] = project_number

    return result
