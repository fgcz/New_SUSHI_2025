"""Job submission service - orchestrates app execution.

This service is responsible for:
- Loading input data (dataset, samples, project defaults)
- Configuring the SushiApp instance
- Running validation
- Generating job scripts (via SlurmService)
- Creating DB records (job, output dataset)
- Writing files to disk (via FilesystemService)
- Submitting to SLURM (or mock mode)

The SushiApp itself is a pure domain model - this service handles all I/O.
"""

from datetime import datetime, timezone

from app.core.config import settings
from app.core.exceptions import NotFoundError
from app.models import Job
from app.repositories.dataset import DatasetRepository
from app.repositories.job import JobRepository
from app.repositories.sample import SampleRepository
from app.services.filesystem_service import FilesystemService
from app.services.slurm_service import SlurmService
from sushi_apps import get_app


class JobSubmissionService:
    """Orchestrates job submission workflow."""

    def __init__(
        self,
        job_repo: JobRepository,
        dataset_repo: DatasetRepository,
        sample_repo: SampleRepository,
        slurm_service: SlurmService,
        filesystem_service: FilesystemService,
    ):
        self.job_repo = job_repo
        self.dataset_repo = dataset_repo
        self.sample_repo = sample_repo
        self.slurm_service = slurm_service
        self.filesystem_service = filesystem_service

    def submit(
        self,
        dataset_id: int,
        project_number: int,
        user_login: str,
        app_name: str,
        params: dict,
        next_dataset_name: str,
        next_dataset_comment: str | None = None,
        process_mode: str = "DATASET",
        dry_run: bool = False,
    ) -> dict:
        """Submit a job for execution.

        Minimal implementation that:
        1. Loads app, dataset, samples
        2. Configures app with params
        3. Builds and writes script
        4. Creates job record in DB
        5. Submits to SLURM

        Returns: {job_id, slurm_job_id, script_path, status, message}
        """
        # 1. Load app
        app = get_app(app_name)
        if not app:
            raise NotFoundError("Application", app_name)

        # 2. Load dataset and samples
        dataset = self.dataset_repo.get_by_id(dataset_id)
        if not dataset:
            raise NotFoundError("Dataset", dataset_id)

        samples = self.sample_repo.get_samples_as_dicts(dataset_id)

        # 3. Build paths (via FilesystemService)
        result_dir = self.filesystem_service.generate_result_dir(
            project_number, next_dataset_name
        )
        input_dataset_tsv_path = self.filesystem_service.generate_input_dataset_path(
            result_dir
        )

        # 4. Configure app
        app.configure(
            user_params=params,
            dataset_rows=samples,
            project=f"p{project_number}",
            gstore_dir=settings.GSTORE_DIR,
            result_dir=result_dir,
            input_dataset_tsv_path=input_dataset_tsv_path,
            process_mode=process_mode,
        )

        # 5. Build script
        script_content = self.slurm_service.build_script(app)

        # 6. Write script (via FilesystemService)
        script_path = self.filesystem_service.generate_script_path(app.name)
        stdout_path, stderr_path = self.filesystem_service.generate_log_paths(script_path)
        self.filesystem_service.write_script(script_path, script_content)

        # 7. Dry run - return early without DB record or SLURM submission
        if dry_run:
            return {
                "dry_run": True,
                "script_path": script_path,
                "stdout_path": stdout_path,
                "stderr_path": stderr_path,
                "result_dir": result_dir,
                "input_dataset_tsv_path": input_dataset_tsv_path,
                "resources": {
                    "cores": params.get("cores", 1),
                    "ram": params.get("ram", 4),
                    "scratch": params.get("scratch", 10),
                    "partition": params.get("partition", "employee"),
                },
            }

        # 8. Create job record in DB (skipped in dry run)
        now = datetime.now(timezone.utc)
        job = Job(
            input_dataset_id=dataset_id,
            script_path=script_path,
            stdout_path=stdout_path,
            stderr_path=stderr_path,
            user=user_login,
            status="submitted",
            created_at=now,
            updated_at=now,
        )
        self.job_repo.create(job)

        # 9. Submit to SLURM
        cores = params.get("cores", 1)
        ram = params.get("ram", 4)
        scratch = params.get("scratch", 10)
        partition = params.get("partition", "employee")

        slurm_job_id = self.slurm_service.submit(
            script_path=script_path,
            stdout_path=stdout_path,
            stderr_path=stderr_path,
            cores=cores,
            ram=ram,
            scratch=scratch,
            partition=partition,
        )

        # 10. Update job with SLURM job ID
        job.submit_job_id = int(slurm_job_id)
        job.start_time = now
        self.job_repo.update(job)

        return {
            "job_id": job.id,
            "slurm_job_id": slurm_job_id,
            "script_path": script_path,
            "status": "submitted",
            "message": f"Job submitted successfully to SLURM (job ID: {slurm_job_id})",
        }

    def submit_hello_world(
        self,
        project_number: int,
        user_login: str,
    ) -> dict:
        """Submit a minimal hello world job for testing.

        Creates a simple R script that prints "Hello World" and submits to SLURM.
        No dataset or app configuration needed.

        Returns: {job_id, slurm_job_id, script_path, status, message}
        """
        # Build simple hello world script
        script_content = """#!/bin/bash
set -eux
set -o pipefail

echo "Job runs on $(hostname)"
echo "Starting Hello World test"

R --vanilla --slave << EOT
print("Hello World from SUSHI!")
print(paste("Running on:", Sys.info()["nodename"]))
print(paste("Time:", Sys.time()))
EOT

echo "Hello World test completed"
echo "__SCRIPT END__"
"""

        # Generate script path and write (via FilesystemService)
        script_path = self.filesystem_service.generate_script_path("hello_world")
        stdout_path, stderr_path = self.filesystem_service.generate_log_paths(script_path)
        self.filesystem_service.write_script(script_path, script_content)

        # Create job record
        now = datetime.now(timezone.utc)
        job = Job(
            script_path=script_path,
            stdout_path=stdout_path,
            stderr_path=stderr_path,
            user=user_login,
            status="submitted",
            created_at=now,
            updated_at=now,
        )
        self.job_repo.create(job)

        # Submit to SLURM (minimal resources)
        slurm_job_id = self.slurm_service.submit(
            script_path=script_path,
            stdout_path=stdout_path,
            stderr_path=stderr_path,
            cores=1,
            ram=1,
            scratch=1,
            partition="employee",
        )

        # Update job with SLURM job ID
        job.submit_job_id = int(slurm_job_id)
        job.start_time = now
        self.job_repo.update(job)

        return {
            "job_id": job.id,
            "slurm_job_id": slurm_job_id,
            "script_path": script_path,
            "status": "submitted",
            "message": f"Hello World job submitted (SLURM job ID: {slurm_job_id})",
        }
