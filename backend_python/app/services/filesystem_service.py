"""Filesystem service - centralized file and directory operations.

This service handles ALL file system operations for job submission and execution:

PRE-SUBMISSION (at job submit time):
- Create result directory in gstore (p{project}/{dataset}_{timestamp}/)
- Write input_dataset.tsv to result directory
- Write parameters.tsv to result directory
- Write job script to script directory
- Write any app-specific input files

POST-SUBMISSION (after job completes):
- Copy output files from scratch to gstore
- Copy grandchild dataset files
- Handle dataset registration files
- Cleanup temporary files

DRY RUN SUPPORT:
- Track what operations WOULD happen without executing them
- Optionally write to mock/temp locations for inspection
- Return summary of all planned file operations

This service abstracts away the actual paths (gstore, scratch, scripts) making it
easy to swap between production paths and local development paths.
"""

from datetime import datetime
from pathlib import Path

from app.core.config import settings


class FilesystemService:
    """Centralized file and directory operations for job lifecycle."""

    def __init__(self):
        self.gstore_dir = Path(settings.GSTORE_DIR)
        self.scratch_dir = Path(settings.SCRATCH_DIR)
        self.script_dir = Path.home() / "slurm_scripts"
        self._ensure_script_dir()

    def _ensure_script_dir(self) -> None:
        """Ensure the script directory exists."""
        self.script_dir.mkdir(parents=True, exist_ok=True)

    # === Path generation ===

    def generate_result_dir(self, project_number: int, dataset_name: str) -> str:
        """Generate the result directory path (relative to gstore).

        Returns: e.g. "p1234/MyDataset_2026-05-19--10-30-00"
        """
        timestamp = datetime.now().strftime("%Y-%m-%d--%H-%M-%S")
        return f"p{project_number}/{dataset_name}_{timestamp}"

    def generate_input_dataset_path(self, result_dir: str) -> str:
        """Generate the full path for input_dataset.tsv.

        Returns: e.g. "/srv/gstore/projects/p1234/MyDataset_.../input_dataset.tsv"
        """
        return f"{self.gstore_dir}/{result_dir}/input_dataset.tsv"

    def generate_script_path(self, app_name: str) -> str:
        """Generate a unique script path for a job.

        Returns: e.g. "/Users/me/slurm_scripts/FastQC_20260519103000.sh"
        """
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        return str(self.script_dir / f"{app_name}_{timestamp}.sh")

    def generate_log_paths(self, script_path: str) -> tuple[str, str]:
        """Generate stdout and stderr log paths from script path.

        Returns: (stdout_path, stderr_path)
        """
        return (f"{script_path}_o.log", f"{script_path}_e.log")

    # === Pre-submission file operations ===

    def write_script(self, script_path: str, content: str) -> None:
        """Write job script to disk and make executable.

        Args:
            script_path: Absolute path to write script
            content: Script content
        """
        path = Path(script_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(0o755)

    def create_result_dir(self, result_dir: str) -> Path:
        """Create the result directory in gstore for job outputs."""
        raise NotImplementedError

    def write_input_dataset_tsv(self, result_dir: str, samples: list[dict]) -> Path:
        """Write input_dataset.tsv to the result directory."""
        raise NotImplementedError

    def write_parameters_tsv(self, result_dir: str, params: dict) -> Path:
        """Write parameters.tsv to the result directory."""
        raise NotImplementedError

    # === Post-submission operations ===

    def copy_outputs_to_gstore(self, scratch_path: str, gstore_path: str) -> None:
        """Copy output files from scratch to gstore after job completion."""
        raise NotImplementedError

    def cleanup_scratch(self, scratch_path: str) -> None:
        """Remove temporary scratch directory after job completion."""
        raise NotImplementedError

    # === Script generation for runtime file operations ===

    def build_output_copy_commands(
        self, output_files: list[str], gstore_dir: str
    ) -> list[str]:
        """Generate bash commands to copy output files from scratch to gstore.

        Args:
            output_files: List of output file paths (relative to result dir)
            gstore_dir: The gstore directory path

        Returns:
            List of bash command lines
        """
        import os

        lines = []
        for file_path in output_files:
            src_file = os.path.basename(file_path)
            dest_dir = os.path.dirname(os.path.join(gstore_dir, file_path))
            lines.append(f"mkdir -p {dest_dir}")
            lines.append(f"cp -r $SCRATCH_DIR/{src_file} {dest_dir}/ || true")
        return lines

    def build_grandchild_copy_commands(
        self, grandchild_datasets: list[dict], gstore_dir: str
    ) -> list[str]:
        """Generate bash commands to copy grandchild dataset files.

        Args:
            grandchild_datasets: List of grandchild dataset dicts with file paths
            gstore_dir: The gstore directory path

        Returns:
            List of bash command lines
        """
        import os

        lines = []
        for ds in grandchild_datasets:
            for key, path in ds.items():
                if "[File]" in key and path:
                    src_file = os.path.basename(path)
                    dest_dir = os.path.dirname(os.path.join(gstore_dir, path))
                    lines.append(f"mkdir -p {dest_dir}")
                    lines.append(f"cp -r $SCRATCH_DIR/{src_file} {dest_dir}/ || true")
        return lines

    def build_cleanup_commands(self) -> list[str]:
        """Generate bash commands for scratch cleanup.

        Returns:
            List of bash command lines
        """
        return [
            "",
            "# Cleanup scratch",
            "cd /",
            "rm -rf $SCRATCH_DIR || true",
            "",
            "echo '__SCRIPT END__'",
        ]

    # === Dry run support ===

    def dry_run_summary(self) -> dict:
        """Return summary of all file operations that would be performed."""
        raise NotImplementedError
