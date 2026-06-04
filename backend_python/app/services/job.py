"""Job service for job-related business logic."""

from pathlib import Path
from typing import TYPE_CHECKING

from app.core.auth import require_project_access
from app.core.exceptions import NotFoundError
from app.repositories.dataset import DatasetRepository
from app.repositories.job import JobRepository
from app.repositories.project import ProjectRepository

if TYPE_CHECKING:
    from app.api.deps import CurrentUser


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

    def get_all_paginated(
        self,
        page: int,
        per: int,
        status: str | None = None,
        user: str | None = None,
        dataset_name: str | None = None,
    ) -> dict:
        """Get all jobs paginated."""
        per = max(1, min(per, 200))

        jobs, total_count, total_pages = self.job_repo.get_all_paginated(
            page, per, status, user, dataset_name
        )

        # Batch load dataset names
        job_dataset_ids = {j.next_dataset_id for j in jobs if j.next_dataset_id}
        dataset_names = {ds_id: name for ds_id, name in self.dataset_repo.get_id_name_pairs(job_dataset_ids)}

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
                "dataset_name": dataset_name,
            },
        }

    def get_by_id(self, job_id: int) -> dict:
        """Get full job details by ID."""
        job = self.job_repo.get_by_id(job_id)
        if not job:
            raise NotFoundError("Job", job_id)

        # Get project_number from dataset -> project
        project_number = None
        dataset_id = job.next_dataset_id or job.input_dataset_id
        if dataset_id:
            dataset = self.dataset_repo.get_by_id(dataset_id)
            if dataset and dataset.project_id:
                project = self.project_repo.get_by_id(dataset.project_id)
                if project:
                    project_number = project.number

        return {
            "id": job.id,
            "project_number": project_number,
            "status": job.status or "unknown",
            "user": job.user or "unknown",
            "input_dataset_id": job.input_dataset_id,
            "next_dataset_id": job.next_dataset_id,
            "created_at": job.created_at.isoformat() if job.created_at else None,
            "script_path": job.script_path,
            "stdout_path": job.stdout_path,
            "stderr_path": job.stderr_path,
            "submit_job_id": job.submit_job_id,
            "start_time": job.start_time.isoformat() if job.start_time else None,
            "end_time": job.end_time.isoformat() if job.end_time else None,
            "updated_at": job.updated_at.isoformat() if job.updated_at else None,
        }

    def get_script(self, job_id: int) -> str:
        """Get job script content from filesystem."""
        job = self.job_repo.get_by_id(job_id)
        if not job:
            raise NotFoundError("Job", job_id)

        if not job.script_path:
            return ""

        script_file = Path(job.script_path)
        if not script_file.exists():
            return f"# Script file not found: {job.script_path}"

        return script_file.read_text()

    def get_logs(self, job_id: int) -> dict:
        """Get job logs (stdout + stderr) from filesystem."""
        job = self.job_repo.get_by_id(job_id)
        if not job:
            raise NotFoundError("Job", job_id)

        stdout = ""
        stderr = ""

        # Read stdout
        if job.stdout_path:
            stdout_file = Path(job.stdout_path)
            if stdout_file.exists():
                stdout = stdout_file.read_text()
            else:
                stdout = f"File not found: {job.stdout_path}"
        else:
            stdout = "No stdout path configured"

        # Read stderr
        if job.stderr_path:
            stderr_file = Path(job.stderr_path)
            if stderr_file.exists():
                stderr = stderr_file.read_text()
            else:
                stderr = f"File not found: {job.stderr_path}"
        else:
            stderr = "No stderr path configured"

        return {"stdout": stdout, "stderr": stderr}

    def get_paginated(
        self,
        project_number: int,
        page: int,
        per: int,
        status: str | None = None,
        user: str | None = None,
        search: str | None = None,
        *,
        caller: "CurrentUser",
    ) -> dict:
        """Get paginated jobs for a project."""
        require_project_access(project_number, caller)
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
        dataset_names = {ds_id: name for ds_id, name in self.dataset_repo.get_id_name_pairs(job_dataset_ids)}

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
