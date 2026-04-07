"""Job service for job-related business logic."""

from app.repositories.dataset import DatasetRepository
from app.repositories.job import JobRepository
from app.repositories.project import ProjectRepository


class JobService:
    """Service for job operations."""

    def __init__(
        self,
        job_repo: JobRepository,
        project_repo: ProjectRepository,
        dataset_repo: DatasetRepository,
    ):
        self.job_repo = job_repo
        self.project_repo = project_repo
        self.dataset_repo = dataset_repo

    def get_paginated(
        self,
        project_number: int,
        page: int,
        per: int,
        status: str | None = None,
        user: str | None = None,
        search: str | None = None,
    ) -> dict:
        """Get paginated jobs for a project."""
        # Clamp per to [1, 200]
        per = max(1, min(per, 200))

        # Get dataset IDs for this project
        dataset_ids = self.project_repo.get_dataset_ids_by_number(project_number)

        # Get jobs from repository
        jobs, total_count, total_pages = self.job_repo.get_by_project_paginated(
            dataset_ids, page, per, status, user, search
        )

        # Batch load dataset names
        job_dataset_ids = {j.next_dataset_id for j in jobs if j.next_dataset_id}
        dataset_names = self.dataset_repo.get_names_by_ids(job_dataset_ids)

        # Serialize jobs
        serialized_jobs = []
        for job in jobs:
            ds_id = job.next_dataset_id
            serialized_jobs.append({
                "id": job.id,
                "submit_job_id": job.submit_job_id,
                "status": job.status or "unknown",
                "user": job.user or "unknown",
                "dataset": {"id": ds_id, "name": dataset_names.get(ds_id)} if ds_id else None,
                "time": {
                    "start_time": job.start_time.isoformat() if job.start_time else None,
                    "end_time": job.end_time.isoformat() if job.end_time else None,
                },
                "created_at": job.created_at.isoformat() if job.created_at else None,
            })

        return {
            "jobs": serialized_jobs,
            "pagination": {
                "total_count": total_count,
                "page": page,
                "per": per,
                "total_pages": total_pages,
            },
            "filters": {
                "status": status,
                "user": user,
                "q": search,
            },
            "project_number": project_number,
        }
