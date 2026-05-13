"""Project routes - thin handlers delegating to services."""

from fastapi import APIRouter, File, Form, UploadFile
from pydantic import BaseModel

from app.api.deps import (
    CurrentUserDep,
    DatasetImportServiceDep,
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
    import_service: DatasetImportServiceDep,
    file: UploadFile = File(...),
    parent_id: int | None = Form(None),
    allow_duplicate: bool = Form(False),
) -> dict:
    """Import a dataset into a project from a TSV file.

    The dataset name and other metadata are extracted from the TSV content.
    """
    require_project_access(project_number, current_user)

    # Read file content
    content = await file.read()
    content_str = content.decode("utf-8")

    # Import dataset
    dataset = import_service.import_from_tsv(
        content=content_str,
        project_number=project_number,
        user=current_user,
        parent_id=parent_id,
        allow_duplicate=allow_duplicate,
    )

    return {
        "success": True,
        "dataset": {
            "id": dataset.id,
            "name": dataset.name,
            "num_samples": dataset.num_samples,
            "comment": dataset.comment,
            "order_ids": dataset.order_ids,
        },
    }


@router.post("/{project_number}/datasets/import/preview")
async def preview_dataset_import(
    project_number: int,
    current_user: CurrentUserDep,
    import_service: DatasetImportServiceDep,
    file: UploadFile = File(...),
) -> dict:
    """Preview what would be imported without actually importing.

    Parses the TSV, validates structure, and checks for duplicates
    in the target project. Does NOT create any database records.

    Args:
        project_number: Target project
        file: TSV file to preview

    Returns:
        Preview info including name, samples count, columns, and duplicate check
    """
    require_project_access(project_number, current_user)

    # Read file content
    content = await file.read()
    content_str = content.decode("utf-8")

    # Get preview
    return import_service.preview_import(content_str, project_number)


class DatasetRegisterRequest(BaseModel):
    name: str | None = None
    path: str
    parent_id: int | None = None


@router.post("/{project_number}/datasets/register")
def register_dataset(
    project_number: int,
    body: DatasetRegisterRequest,
    import_service: DatasetImportServiceDep,
) -> dict:
    """Register a dataset from a server-side TSV file path.

    The project is created automatically if it does not exist.
    Intended for script/btools callers; no authentication required.
    """
    dataset = import_service.import_from_path(
        path=body.path,
        project_number=project_number,
        name_override=body.name,
        parent_id=body.parent_id,
    )
    return {"message": "OK", "data_set_id": dataset.id}
