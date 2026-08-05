"""Authorization helpers shared across the service layer."""

from typing import Protocol

from app.core.config import settings
from app.core.exceptions import ForbiddenError


class _ProjectAccessible(Protocol):
    is_employee: bool
    projects: list[int]


def require_project_access(project_number: int, user: _ProjectAccessible) -> None:
    """Raise ForbiddenError if user does not have access to a project."""
    if settings.SKIP_AUTH or user.is_employee:
        return
    if project_number not in user.projects:
        raise ForbiddenError(f"You don't have access to project {project_number}")
