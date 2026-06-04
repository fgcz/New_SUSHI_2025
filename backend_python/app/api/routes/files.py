"""File routes - gStore directory browsing."""

from fastapi import APIRouter, Query

from app.api.deps import CurrentUserDep, FileServiceDep

router = APIRouter()


@router.get("/{path:path}", response_model=None)
def get_path(
    path: str,
    current_user: CurrentUserDep,
    file_service: FileServiceDep,
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
    return file_service.get(path, current_user, page, per_page, sort_by, sort_desc)
