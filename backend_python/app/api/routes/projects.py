"""Project routes - thin handlers delegating to services."""

from fastapi import APIRouter, File, Form, UploadFile

from app.api.deps import (
    CurrentUserDep,
    DatasetServiceDep,
    JobServiceDep,
    ProjectServiceDep,
    require_project_access,
)

router: APIRouter = APIRouter()


# Mock rankings data
MOCK_RANKINGS = [
    {"username": "alice.smith", "jobs_this_month": 142, "total_submissions": 3847},
    {"username": "bob.jones", "jobs_this_month": 98, "total_submissions": 2156},
    {"username": "carol.williams", "jobs_this_month": 87, "total_submissions": 1893},
    {"username": "david.brown", "jobs_this_month": 76, "total_submissions": 1654},
    {"username": "emma.davis", "jobs_this_month": 65, "total_submissions": 1432},
    {"username": "frank.miller", "jobs_this_month": 54, "total_submissions": 1287},
    {"username": "grace.wilson", "jobs_this_month": 43, "total_submissions": 956},
    {"username": "henry.moore", "jobs_this_month": 38, "total_submissions": 842},
    {"username": "iris.taylor", "jobs_this_month": 29, "total_submissions": 634},
    {"username": "jack.anderson", "jobs_this_month": 21, "total_submissions": 478},
]


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


@router.get("/rankings")
def get_rankings(current_user: CurrentUserDep) -> dict:
    """Get user rankings by job submissions.

    MOCK: Returns hardcoded rankings data.
    Real implementation would query job statistics from database.
    """
    return {"rankings": MOCK_RANKINGS}


@router.post("/{project_number}/datasets/import")
async def import_dataset(
    project_number: int,
    current_user: CurrentUserDep,
    file: UploadFile = File(...),
    name: str = Form(...),
    parent_id: int | None = Form(None),
) -> dict:
    """Import a dataset into a project.

    MOCK: Returns success without actually importing.
    Real implementation would parse the file and create dataset records.
    """
    require_project_access(project_number, current_user)

    return {
        "success": True,
        "message": f"Dataset '{name}' import initiated",
        "project_number": project_number,
        "parent_id": parent_id,
        "filename": file.filename,
    }
