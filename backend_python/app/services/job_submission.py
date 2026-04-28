"""Job submission service - orchestrates app execution.

This service is responsible for:
- Loading input data (dataset, samples, project defaults)
- Configuring the SushiApp instance
- Running validation
- Generating job scripts (via SlurmService)
- Creating DB records (job, output dataset)
- Writing files to disk
- Submitting to SLURM (or mock mode)

The SushiApp itself is a pure domain model - this service handles all I/O.
"""

from app.core.exceptions import NotFoundError, ValidationError
from app.repositories.dataset import DatasetRepository
from app.repositories.job import JobRepository
from app.repositories.sample import SampleRepository
from app.services.slurm_service import SlurmService
from app.services.sushi_validators import validate_app

from sushi_apps import get_app


class JobSubmissionService:
    """Orchestrates job submission workflow."""

    def __init__(
        self,
        job_repo: JobRepository,
        dataset_repo: DatasetRepository,
        sample_repo: SampleRepository,
        slurm_service: SlurmService,
    ):
        self.job_repo = job_repo
        self.dataset_repo = dataset_repo
        self.sample_repo = sample_repo
        self.slurm_service = slurm_service

    def submit(
        self,
        # Identity: what and where
        dataset_id: int,
        project_number: int,
        user_login: str,
        # App configuration
        app_name: str,
        params: dict,
        next_dataset_name: str,
        next_dataset_comment: str | None = None,
        process_mode: str = "DATASET",
    ) -> dict:
        """Submit a job for execution.

        Workflow:
        1. Load app, dataset, samples
        2. Load project defaults
        3. Build paths (gstore_dir, result_dir, input_dataset_tsv_path)
        4. Configure app
        5. Run app hooks (set_default_parameters, adjust_requirements)
        6. Validate (columns, params)
        7. Create output dataset record in DB
        8. Write input dataset TSV
        9. Generate and write script(s):
           - DATASET mode: 1 script for all samples
           - SAMPLE mode: 1 script per sample (with job dependencies)
        10. Write parameters TSV
        11. Create job record(s) in DB
        12. Save parameters to DB
        13. Submit to SLURM:
            - DATASET mode: single submit
            - SAMPLE mode: submit_job_chain with dependencies

        Returns: {job_ids, status, script_paths, output_dataset_id, message}
        Raises: NotFoundError, ValidationError
        """
        # TODO: Implement full workflow
        raise NotImplementedError("JobSubmissionService.submit not yet implemented")

    def mock_submit(
        self,
        app_name: str,
        dataset_id: int,
        params: dict,
        project_number: int,
    ) -> dict:
        """Generate script preview without creating DB records or submitting.

        Used by frontend "Mock Run" button to show what would be executed.

        Returns: {script_preview, output_dataset}
        """
        # TODO: Implement mock submission
        raise NotImplementedError("JobSubmissionService.mock_submit not yet implemented")

    # === Private helpers (stubs) ===

    def _load_dataset(self, dataset_id: int):
        """Fetch dataset or raise NotFoundError."""
        # TODO: Implement
        raise NotImplementedError

    def _load_samples(self, dataset_id: int) -> list[dict]:
        """Fetch samples as list of dicts."""
        # TODO: Implement
        raise NotImplementedError

    def _load_project_defaults(self, project_number: int, app_name: str) -> dict:
        """Load project-specific parameter defaults.

        Reads from project_default_parametersets.tsv if it exists.
        Returns empty dict if no defaults found.
        """
        # TODO: Implement
        return {}

    def _build_paths(self, project_number: int, next_dataset_name: str) -> dict:
        """Build gstore_dir, result_dir, input_dataset_tsv_path.

        Returns: {gstore_dir, result_dir, input_dataset_tsv_path}
        """
        # TODO: Implement path building with timestamps, sanitization
        raise NotImplementedError

    def _write_input_dataset_tsv(self, path: str, samples: list[dict]) -> None:
        """Write input dataset TSV file for R apps to read."""
        # TODO: Implement TSV writing
        raise NotImplementedError

    def _write_parameters_tsv(self, path: str, app_name: str, params: dict) -> None:
        """Write parameters TSV file alongside the script.

        Ruby SUSHI saves params to parameters.tsv for reproducibility.
        Format: param_name<tab>value
        """
        # TODO: Implement
        raise NotImplementedError

    def _save_parameters_to_db(
        self,
        job_id: int,
        app_name: str,
        params: dict,
    ) -> None:
        """Save job parameters to database for reproducibility.

        Allows re-running jobs with same parameters later.
        """
        # TODO: Implement
        raise NotImplementedError

    def _create_output_dataset(
        self,
        project_number: int,
        name: str,
        comment: str | None,
        parent_id: int,
        app_name: str,
    ) -> int:
        """Create output dataset record in DB.

        Returns: dataset_id
        """
        # TODO: Implement
        raise NotImplementedError

    def _create_job_record(
        self,
        project_number: int,
        app_name: str,
        user_login: str,
        input_dataset_id: int,
        output_dataset_id: int,
        script_path: str,
    ) -> int:
        """Create job record in DB.

        Returns: job_id
        """
        # TODO: Implement
        raise NotImplementedError

    def _generate_scripts_for_mode(
        self,
        app,
        process_mode: str,
        base_script_path: str,
    ) -> list[str]:
        """Generate script(s) based on process mode.

        DATASET mode: Single script processing all samples
        SAMPLE mode: One script per sample (app.set_sample() called for each)
        BATCH mode: Single script with all samples (like DATASET but different R handling)

        Args:
            app: Configured SushiApp instance
            process_mode: DATASET, SAMPLE, or BATCH
            base_script_path: Base path for scripts (index appended for SAMPLE mode)

        Returns:
            List of script paths written
        """
        # TODO: Implement
        # if process_mode == "SAMPLE":
        #     for i, sample in enumerate(app.samples):
        #         app.set_sample(i, is_last=(i == len(app.samples) - 1))
        #         script = self.slurm_service.build_script(app)
        #         path = f"{base_script_path}_{i}.sh"
        #         self.slurm_service.write_script(path, script)
        #         paths.append(path)
        # else:
        #     script = self.slurm_service.build_script(app)
        #     self.slurm_service.write_script(base_script_path, script)
        #     paths.append(base_script_path)
        raise NotImplementedError
