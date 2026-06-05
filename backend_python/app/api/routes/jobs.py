"""Job routes - thin handlers delegating to services."""

from fastapi import APIRouter
from pydantic import BaseModel

from app.api.deps import CurrentUserDep, JobServiceDep, JobSubmissionServiceDep

router = APIRouter()


class NextDatasetRequest(BaseModel):
    name: str
    comment: str | None = None


class JobSubmitRequest(BaseModel):
    project_number: int
    dataset_id: int
    app_name: str
    next_dataset: NextDatasetRequest
    parameters: dict


@router.get("/")
def get_all_jobs(
    current_user: CurrentUserDep,
    service: JobServiceDep,
    page: int = 1,
    per: int = 50,
    status: str | None = None,
    user: str | None = None,
    dataset_name: str | None = None,
) -> dict:
    """Get all jobs paginated with optional filters."""
    return service.get_all_paginated(page, per, status, user, dataset_name)


@router.get("/{job_id}")
def get_job(
    job_id: int,
    current_user: CurrentUserDep,
    service: JobServiceDep,
) -> dict:
    """Get full job details by ID."""
    return service.get_by_id(job_id, current_user)


@router.get("/{job_id}/script")
def get_job_script(
    job_id: int,
    current_user: CurrentUserDep,
    service: JobServiceDep,
) -> dict:
    """Get job script content."""
    script = service.get_script(job_id, current_user)
    return {"script": script}


@router.get("/{job_id}/logs")
def get_job_logs(
    job_id: int,
    current_user: CurrentUserDep,
    service: JobServiceDep,
) -> dict:
    """Get job logs (stdout and stderr separately)."""
    return service.get_logs(job_id, current_user)


@router.post("/")
def submit_job(
    request: JobSubmitRequest,
    current_user: CurrentUserDep,
    submission_service: JobSubmissionServiceDep,
) -> dict:
    """Submit a new job for execution."""
    # Extract from request for clarity
    dataset_id = request.dataset_id
    project_number = request.project_number
    user_login = current_user.login

    app_name = request.app_name
    params = request.parameters
    next_dataset_name = request.next_dataset.name
    next_dataset_comment = request.next_dataset.comment

    return submission_service.submit(
        # Identity
        dataset_id=dataset_id,
        project_number=project_number,
        user_login=user_login,
        # App configuration
        app_name=app_name,
        params=params,
        next_dataset_name=next_dataset_name,
        next_dataset_comment=next_dataset_comment,
    )


@router.post("/dry-run")
def dry_run_job(
    request: JobSubmitRequest,
    current_user: CurrentUserDep,
    submission_service: JobSubmissionServiceDep,
) -> dict:
    """Preview job submission without actually submitting to SLURM.

    Performs all validation and script generation, writes the script to disk,
    but does NOT create a database record or submit to SLURM.

    Returns script path and resource details for inspection.
    """
    return submission_service.submit(
        dataset_id=request.dataset_id,
        project_number=request.project_number,
        user_login=current_user.login,
        app_name=request.app_name,
        params=request.parameters,
        next_dataset_name=request.next_dataset.name,
        next_dataset_comment=request.next_dataset.comment,
        dry_run=True,
    )
