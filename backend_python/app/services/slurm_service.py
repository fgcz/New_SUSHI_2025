"""SLURM service - script building and job submission.

Handles:
- Building complete SLURM job scripts (header + modules + commands + footer)
- Writing scripts to disk
- Submitting jobs to SLURM
- Checking job status
"""

from sushi_apps.base import SushiApp
from sushi_apps.config import (
    DEFAULT_CORES,
    DEFAULT_RAM,
    DEFAULT_SCRATCH,
    DEFAULT_PARTITION,
)


class SlurmService:
    """Builds SLURM scripts and manages job submission."""

    def build_script(self, app: SushiApp, job_name: str | None = None) -> str:
        """Build complete SLURM job script from configured app.

        Args:
            app: A configured SushiApp instance
            job_name: Optional job name for SLURM. Defaults to app.name

        Returns:
            Complete bash script as string
        """
        # TODO: Implement full script building
        raise NotImplementedError("SlurmService.build_script not yet implemented")

    def write_script(self, path: str, content: str) -> None:
        """Write job script to disk.

        Args:
            path: Absolute path to write script
            content: Script content
        """
        # TODO: Implement
        raise NotImplementedError("SlurmService.write_script not yet implemented")

    def submit(self, script_path: str, dependency_job_id: str | None = None) -> str:
        """Submit script to SLURM via sbatch.

        Args:
            script_path: Path to the job script
            dependency_job_id: Optional SLURM job ID to wait for (for SAMPLE mode chains)

        Returns:
            SLURM job ID
        """
        # TODO: Implement sbatch submission
        # If dependency_job_id provided, add: --dependency=afterok:{dependency_job_id}
        raise NotImplementedError("SlurmService.submit not yet implemented")

    def submit_job_chain(self, script_paths: list[str]) -> list[str]:
        """Submit multiple scripts as a dependency chain (for SAMPLE mode).

        Each job waits for the previous one to complete.
        Uses SLURM's --dependency=afterok:$PREV_JOB_ID

        Args:
            script_paths: List of script paths in execution order

        Returns:
            List of SLURM job IDs in same order
        """
        # TODO: Implement
        # for i, path in enumerate(script_paths):
        #     prev_job_id = job_ids[i-1] if i > 0 else None
        #     job_id = self.submit(path, dependency_job_id=prev_job_id)
        #     job_ids.append(job_id)
        raise NotImplementedError("SlurmService.submit_job_chain not yet implemented")

    def get_job_status(self, slurm_job_id: str) -> str:
        """Get status of a SLURM job.

        Args:
            slurm_job_id: SLURM job ID

        Returns:
            Job status (PENDING, RUNNING, COMPLETED, FAILED, etc.)
        """
        # TODO: Implement squeue/sacct check
        raise NotImplementedError("SlurmService.get_job_status not yet implemented")

    def cancel_job(self, slurm_job_id: str) -> None:
        """Cancel a SLURM job.

        Args:
            slurm_job_id: SLURM job ID
        """
        # TODO: Implement scancel
        raise NotImplementedError("SlurmService.cancel_job not yet implemented")

    # === Private helpers ===

    def _build_header(self, app: SushiApp, job_name: str) -> str:
        """Build SLURM header with #SBATCH directives."""
        # TODO: Implement
        raise NotImplementedError

    def _build_module_loads(self, app: SushiApp) -> str:
        """Build module load commands."""
        # TODO: Implement
        raise NotImplementedError

    def _build_setup(self, app: SushiApp) -> str:
        """Build working directory setup commands."""
        # TODO: Implement
        raise NotImplementedError

    def _build_footer(self) -> str:
        """Build cleanup/footer section."""
        # TODO: Implement
        raise NotImplementedError
