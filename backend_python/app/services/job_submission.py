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

import json
from datetime import datetime, timezone

from app.core.config import settings
from app.core.exceptions import NotFoundError
from app.models import DataSet, Job, Sample
from app.repositories.dataset import DatasetRepository
from app.repositories.job import JobRepository
from app.repositories.sample import SampleRepository
from app.repositories.user import UserRepository
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
        user_repo: UserRepository,
        slurm_service: SlurmService,
        filesystem_service: FilesystemService,
    ):
        self.job_repo = job_repo
        self.dataset_repo = dataset_repo
        self.sample_repo = sample_repo
        self.user_repo = user_repo
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

        # 3. Build paths and create scratch working directory (via FilesystemService)
        result_dir = self.filesystem_service.generate_result_dir(
            project_number, next_dataset_name
        )
        scratch_result_dir = self.filesystem_service.generate_scratch_result_dir(result_dir)
        self.filesystem_service.create_result_dir(scratch_result_dir)

        input_dataset_tsv_path = self.filesystem_service.generate_input_dataset_path(result_dir)
        self.filesystem_service.write_input_dataset_tsv(scratch_result_dir, samples)
        self.filesystem_service.write_parameters_tsv(scratch_result_dir, params)

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

        # 5. Build and write script to scratch/scripts/ (via FilesystemService)
        script_content = self.slurm_service.build_script(app)
        scratch_script_path = self.filesystem_service.generate_script_path(app.name, scratch_result_dir)
        self.filesystem_service.write_script(scratch_script_path, script_content)

        # 6. Copy entire scratch dir to gstore, then derive stable gstore paths
        self.filesystem_service.copy_scratch_to_gstore(scratch_result_dir, result_dir)
        script_path = self.filesystem_service.gstore_script_path(scratch_script_path, scratch_result_dir, result_dir)
        stdout_path, stderr_path = self.filesystem_service.generate_log_paths(script_path)

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

        # 8. Create output DataSet and Job records in DB (skipped in dry run)
        now = datetime.now(timezone.utc)

        user = self.user_repo.get_by_login(user_login)
        output_dataset = DataSet(
            name=next_dataset_name,
            project_id=dataset.project_id,
            parent_id=dataset_id,
            sushi_app_name=app.name,
            job_parameters=json.dumps(params),
            comment=next_dataset_comment,
            num_samples=len(samples),
            user_id=user.id if user else None,
            created_at=now,
            updated_at=now,
        )
        self.dataset_repo.create(output_dataset)

        # 8a. Write output dataset sample row from app.next_dataset()
        next_ds_row = app.next_dataset()
        if next_ds_row:
            self.sample_repo.create(Sample(
                data_set_id=output_dataset.id,
                key_value=json.dumps(next_ds_row),
                created_at=now,
                updated_at=now,
            ))

        # 8b. Create grandchild datasets and their sample rows
        for grandchild_row in app.grandchild_datasets():
            grandchild_name = grandchild_row.get("Name", "")
            grandchild_dataset = DataSet(
                name=grandchild_name,
                project_id=dataset.project_id,
                parent_id=output_dataset.id,
                sushi_app_name=app.name,
                num_samples=1,
                user_id=user.id if user else None,
                created_at=now,
                updated_at=now,
            )
            self.dataset_repo.create(grandchild_dataset)
            self.sample_repo.create(Sample(
                data_set_id=grandchild_dataset.id,
                key_value=json.dumps(grandchild_row),
                created_at=now,
                updated_at=now,
            ))

        job = Job(
            input_dataset_id=dataset_id,
            next_dataset_id=output_dataset.id,
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
            "output_dataset_id": output_dataset.id,
            "slurm_job_id": slurm_job_id,
            "script_path": script_path,
            "status": "submitted",
            "message": f"Job submitted successfully to SLURM (job ID: {slurm_job_id})",
        }
