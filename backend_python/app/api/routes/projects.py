"""Project routes - thin handlers delegating to services."""

from fastapi import APIRouter

from app.api.deps import (
    CurrentUserDep,
    DatasetServiceDep,
    JobServiceDep,
    ProjectServiceDep,
    require_project_access,
)

router: APIRouter = APIRouter()


@router.get("/")
def get_user_projects(current_user: CurrentUserDep, service: ProjectServiceDep) -> dict:
    """Get projects for the current authenticated user."""
    return {
        "projects": current_user.projects,
        "current_user": current_user.login,
    }


@router.get("/{project_number}/datasets")
def get_project_datasets(
    project_number: int,
    current_user: CurrentUserDep,
    service: DatasetServiceDep,
    page: int = 1,
    per: int = 50,
    q: str = "",
) -> dict:
    """Get paginated datasets for a project."""
    require_project_access(project_number, current_user)
    return service.get_paginated(project_number, page, per, q)


@router.get("/{project_number}/jobs")
def get_project_jobs(
    project_number: int,
    current_user: CurrentUserDep,
    service: JobServiceDep,
    page: int = 1,
    per: int = 50,
    status: str | None = None,
    user: str | None = None,
    q: str | None = None,
) -> dict:
    """Get paginated jobs for a project."""
    require_project_access(project_number, current_user)
    return service.get_paginated(project_number, page, per, status, user, q)


@router.get("/{project_number}/datasets/tree")
def get_project_datasets_tree(
    project_number: int,
    current_user: CurrentUserDep,
    service: DatasetServiceDep,
) -> dict:
    """Get datasets in tree structure for a project (jstree format)."""
    require_project_access(project_number, current_user)
    return service.get_tree(project_number)
