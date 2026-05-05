"""SLURM service - script building and job submission.

Handles:
- Building complete SLURM job scripts (header + modules + commands + footer)
- Writing scripts to disk
- Submitting jobs to SLURM
- Checking job status
"""

import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

from app.core.config import settings
from sushi_apps.base import SushiApp


class SlurmService:
    """Builds SLURM scripts and manages job submission."""

    def __init__(self):
        # Default script directory - can be overridden
        self.script_dir = Path.home() / "slurm_scripts"
        self.script_dir.mkdir(parents=True, exist_ok=True)

    def build_script(self, app: SushiApp) -> str:
        """Build complete SLURM job script from configured app.

        Structure:
        1. Header - bash setup, environment variables
        2. Module loading
        3. Main commands (from app.commands())
        4. Footer - copy results, cleanup

        Args:
            app: A configured SushiApp instance

        Returns:
            Complete bash script as string
        """
        parts = [
            self._build_header(app),
            self._build_module_loads(app),
            self._build_main(app),
            self._build_footer(app),
        ]
        return "\n".join(parts)

    def write_script(self, path: str, content: str) -> None:
        """Write job script to disk.

        Args:
            path: Absolute path to write script
            content: Script content
        """
        script_path = Path(path)
        script_path.parent.mkdir(parents=True, exist_ok=True)
        script_path.write_text(content)
        # Make executable
        script_path.chmod(0o755)

    def submit(
        self,
        script_path: str,
        stdout_path: str | None = None,
        stderr_path: str | None = None,
        cores: int = 1,
        ram: int = 4,
        scratch: int = 10,
        partition: str = "employee",
        dependency_job_id: str | None = None,
    ) -> str:
        """Submit script to SLURM via sbatch.

        Args:
            script_path: Path to the job script
            stdout_path: Path for stdout log (default: script_path + "_o.log")
            stderr_path: Path for stderr log (default: script_path + "_e.log")
            cores: Number of CPU cores
            ram: RAM in GB
            scratch: Scratch space in GB
            partition: SLURM partition
            dependency_job_id: Optional SLURM job ID to wait for

        Returns:
            SLURM job ID
        """
        if stdout_path is None:
            stdout_path = f"{script_path}_o.log"
        if stderr_path is None:
            stderr_path = f"{script_path}_e.log"

        # Build sbatch command
        cmd = [
            "sbatch",
            "-o", stdout_path,
            "-e", stderr_path,
            "-N", "1",
            f"--mem={ram}G",
            "-n", str(cores),
            f"--gres=scratch:{scratch}",
            "-p", partition,
        ]

        if dependency_job_id:
            cmd.append(f"--dependency=afterok:{dependency_job_id}")

        cmd.append(script_path)

        # Execute sbatch
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
        )

        # Parse job ID from output: "Submitted batch job 12345"
        match = re.search(r"Submitted batch job (\d+)", result.stdout)
        if match:
            return match.group(1)

        raise RuntimeError(f"Failed to parse job ID from sbatch output: {result.stdout}")

    def submit_job_chain(self, script_paths: list[str], **submit_kwargs) -> list[str]:
        """Submit multiple scripts as a dependency chain (for SAMPLE mode).

        Each job waits for the previous one to complete.

        Args:
            script_paths: List of script paths in execution order
            **submit_kwargs: Additional args passed to submit()

        Returns:
            List of SLURM job IDs in same order
        """
        job_ids = []
        for i, path in enumerate(script_paths):
            prev_job_id = job_ids[i - 1] if i > 0 else None
            job_id = self.submit(path, dependency_job_id=prev_job_id, **submit_kwargs)
            job_ids.append(job_id)
        return job_ids

    def get_job_status(self, slurm_job_id: str) -> str:
        """Get status of a SLURM job.

        Args:
            slurm_job_id: SLURM job ID

        Returns:
            Job status (PENDING, RUNNING, COMPLETED, FAILED, etc.)
        """
        # Try squeue first (for running/pending jobs)
        result = subprocess.run(
            ["squeue", "-j", slurm_job_id, "-h", "-o", "%T"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()

        # Job not in queue - check sacct for completed jobs
        result = subprocess.run(
            ["sacct", "-j", slurm_job_id, "-n", "-o", "State", "-X"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip().split()[0]

        return "UNKNOWN"

    def cancel_job(self, slurm_job_id: str) -> None:
        """Cancel a SLURM job.

        Args:
            slurm_job_id: SLURM job ID
        """
        subprocess.run(["scancel", slurm_job_id], check=True)

    def generate_script_path(self, app: SushiApp, suffix: str = "") -> str:
        """Generate a unique script path for a job.

        Args:
            app: The SushiApp instance
            suffix: Optional suffix (e.g., sample name for SAMPLE mode)

        Returns:
            Absolute path for the script file
        """
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        name = f"{app.name}_{timestamp}"
        if suffix:
            name = f"{name}_{suffix}"
        return str(self.script_dir / f"{name}.sh")

    # === Private helpers ===

    def _build_header(self, app: SushiApp) -> str:
        """Build bash header with environment setup."""
        scratch_dir = f"{settings.SCRATCH_DIR}/{app.name}_temp$$"

        return f"""#!/bin/bash
set -eux
set -o pipefail
umask 0002

#### SET THE STAGE
SCRATCH_DIR={scratch_dir}
GSTORE_DIR={app.gstore_dir}
INPUT_DATASET={app.input_dataset_tsv_path}
LAST_JOB={str(app.last_job).upper()}

echo "Job runs on $(hostname)"
echo "at $SCRATCH_DIR"
mkdir -p $SCRATCH_DIR || exit 1
cd $SCRATCH_DIR || exit 1
"""

    def _build_module_loads(self, app: SushiApp) -> str:
        """Build module load commands."""
        if not app.modules:
            return "# No modules to load\n"

        lines = [
            "#### LOAD MODULES",
            f"source {settings.MODULE_SOURCE}",
            f"module load {' '.join(app.modules)}",
            "",
        ]
        return "\n".join(lines)

    def _build_main(self, app: SushiApp) -> str:
        """Build main execution section with app commands."""
        return f"""#### NOW THE ACTUAL JOB STARTS
{app.commands()}
"""

    def _build_footer(self, app: SushiApp) -> str:
        """Build footer with result copying and cleanup."""
        lines = [
            "#### JOB IS DONE - COPY RESULTS AND CLEAN UP",
        ]

        # Copy output files from scratch to gstore
        for file_path in app.output_files:
            src_file = os.path.basename(file_path)
            dest_dir = os.path.dirname(os.path.join(app.gstore_dir, file_path))
            lines.append(f"mkdir -p {dest_dir}")
            lines.append(f"cp -r $SCRATCH_DIR/{src_file} {dest_dir}/ || true")

        # Copy grandchild dataset files
        for ds in app.grandchild_datasets():
            for key, path in ds.items():
                if "[File]" in key and path:
                    src_file = os.path.basename(path)
                    dest_dir = os.path.dirname(os.path.join(app.gstore_dir, path))
                    lines.append(f"mkdir -p {dest_dir}")
                    lines.append(f"cp -r $SCRATCH_DIR/{src_file} {dest_dir}/ || true")

        # Cleanup
        lines.extend([
            "",
            "# Cleanup scratch",
            "cd /",
            "rm -rf $SCRATCH_DIR || true",
            "",
            "echo '__SCRIPT END__'",
        ])

        return "\n".join(lines)
