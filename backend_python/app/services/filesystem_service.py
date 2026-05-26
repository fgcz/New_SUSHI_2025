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

import subprocess
from datetime import datetime
from pathlib import Path

from app.core.config import settings


class FilesystemService:
    """Centralized file and directory operations for job lifecycle."""

    def __init__(self):
        self.gstore_dir = Path(settings.GSTORE_DIR)
        self.scratch_dir = Path(settings.SCRATCH_DIR)

    # === Path generation ===

    def generate_result_dir(self, project_number: int, dataset_name: str) -> str:
        """Generate the result directory path (relative to gstore).

        Returns: e.g. "p1234/MyDataset_2026-05-19--10-30-00"
        """
        timestamp = datetime.now().strftime("%Y-%m-%d--%H-%M-%S")
        return f"p{project_number}/{dataset_name}_{timestamp}"

    def generate_scratch_result_dir(self, result_dir: str) -> str:
        """Generate the scratch working directory path for a job.

        Mirrors Ruby's @scratch_result_dir: uses only the base name (no project prefix)
        so that /scratch/DatasetName_timestamp/ is created on the submission server.

        Returns: e.g. "/scratch/MyDataset_2026-05-19--10-30-00"
        """
        base = Path(result_dir).name
        return str(self.scratch_dir / base)

    def generate_input_dataset_path(self, result_dir: str) -> str:
        """Generate the full path for input_dataset.tsv.

        Returns: e.g. "/srv/gstore/projects/p1234/MyDataset_.../input_dataset.tsv"
        """
        return f"{self.gstore_dir}/{result_dir}/input_dataset.tsv"

    def generate_script_path(self, app_name: str, scratch_result_dir: str) -> str:
        """Generate the script path inside the scratch scripts/ subdirectory.

        Returns: e.g. "/scratch/MyDataset_ts/scripts/FastQC_20260519103000.sh"
        """
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        return str(Path(scratch_result_dir) / "scripts" / f"{app_name}_{timestamp}.sh")

    def gstore_script_path(self, scratch_script_path: str, scratch_result_dir: str, result_dir: str) -> str:
        """Translate a scratch script path to its gstore equivalent after copy.

        Returns: e.g. "/srv/gstore/projects/p1234/MyDataset_ts/scripts/FastQC_ts.sh"
        """
        rel = Path(scratch_script_path).relative_to(scratch_result_dir)
        return str(self.gstore_dir / result_dir / rel)

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

    def create_result_dir(self, scratch_result_dir: str) -> Path:
        """Create the scratch working directory and scripts/ subdirectory for a job.

        Returns: Path to the created scratch result directory.
        """
        path = Path(scratch_result_dir)
        path.mkdir(parents=True, exist_ok=True)
        (path / "scripts").mkdir(exist_ok=True)
        return path

    def write_input_dataset_tsv(self, scratch_result_dir: str, samples: list[dict]) -> Path:
        """Write input_dataset.tsv to the scratch working directory.

        Preserves column tags (e.g. [File], [Factor]) in headers as-is.
        Name column always first, then all others alphabetically.
        """
        import csv

        if not samples:
            raise ValueError("No samples to write input_dataset.tsv")

        all_keys: set[str] = set()
        for sample in samples:
            all_keys.update(sample.keys())

        name_headers = sorted(k for k in all_keys if k.lower() == "name")
        other_headers = sorted(k for k in all_keys if k.lower() != "name")
        headers = name_headers + other_headers

        path = Path(scratch_result_dir) / "input_dataset.tsv"
        with path.open("w", newline="") as f:
            writer = csv.DictWriter(
                f, fieldnames=headers, delimiter="\t", extrasaction="ignore"
            )
            writer.writeheader()
            writer.writerows(samples)

        return path

    def write_parameters_tsv(self, scratch_result_dir: str, params: dict) -> Path:
        """Write parameters.tsv to the scratch working directory.

        Format mirrors Ruby SUSHI: two-column TSV with headers
        'parameterId' and 'value', one row per parameter.
        """
        path = Path(scratch_result_dir) / "parameters.tsv"
        lines = ["parameterId\tvalue"]
        for key, value in params.items():
            lines.append(f"{key}\t{value}")
        path.write_text("\n".join(lines) + "\n")
        return path

    def copy_scratch_to_gstore(self, scratch_result_dir: str, result_dir: str) -> None:
        """Copy the scratch working directory to gstore using the configured COPY_COMMAND.

        The scratch dir is copied into the gstore project dir so the result is:
          {gstore_dir}/{result_dir}/  (with all pre-submission files inside)
        """
        gstore_project_dir = self.gstore_dir / Path(result_dir).parent
        gstore_project_dir.mkdir(parents=True, exist_ok=True)
        cmd = settings.COPY_COMMAND.split() + [scratch_result_dir, str(gstore_project_dir)]
        subprocess.run(cmd, check=True)

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
