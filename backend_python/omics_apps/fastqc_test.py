"""FastQC test application - exercises the full pipeline with dummy outputs.

Same schema as FastQC but commands() writes placeholder files instead of
running real FastQC/R. Useful for testing job submission, file copying,
and dataset registration without real FASTQ input or cluster dependencies.
"""

from omics_apps.base import MultiOmicsApp


def _strip_tags(key: str) -> str:
    return key.split("[")[0].strip()


class FastQCTestApp(MultiOmicsApp):
    """Pipeline smoke test mirroring FastQC output schema."""

    name = "FastQCTest"
    category = "QC"
    description = "Test app - creates dummy FastQC outputs to exercise the submission pipeline"
    required_columns = ["Name", "Read1"]

    modules = ["QC/FastQC", "Dev/R", "Tools/Picard", "Tools/samtools", "Dev/Python", "QC/fastp"]

    params_definition = [
        {"name": "cores", "type": "select", "default": 1, "options": [1, 2, 4, 8], "required": True, "description": "Number of CPU cores"},
        {"name": "ram", "type": "integer", "default": 4, "description": "RAM in GB"},
        {"name": "scratch", "type": "integer", "default": 10, "description": "Scratch space in GB"},
        {"name": "partition", "type": "select", "default": "employee", "options": ["employee", "normal"], "description": "Cluster partition"},
        {"name": "paired", "type": "boolean", "default": False, "required": True, "description": "Paired-end data"},
        {"name": "showNativeReports", "type": "boolean", "default": False, "description": "Include per-sample report links in output dataset"},
    ]

    def set_default_parameters(self) -> None:
        if self.dataset_has_column("Read2"):
            self.params["paired"] = True

    def adjust_requirements(self) -> None:
        if self.params.get("paired") and "Read2" not in self.required_columns:
            self.required_columns = [*self.required_columns, "Read2"]

    def commands(self) -> str:
        lines = []
        for row in self.samples:
            sample = {_strip_tags(k): v for k, v in row.items()}
            name = sample["Name"]
            lines += [
                "mkdir -p FastQC",
                f"echo 'FastQC data for {name}' > FastQC/{name}_fastqc_data.txt",
                f"echo '<html><body>FastQC report for {name}</body></html>' > FastQC/{name}_fastqc.html",
            ]

        lines += [
            "mkdir -p multi_FastQC",
            "echo '<html><body>MultiQC dummy report</body></html>' > multi_FastQC/multiqc_report.html",
        ]

        return "\n".join(lines)

    def next_dataset(self) -> dict:
        fastqc_dir = f"{self.result_dir}/FastQC"
        multiqc_dir = f"{self.result_dir}/multi_FastQC"

        result = {
            "Name": "FastQC",
            "MultiQC Report [Link]": f"{multiqc_dir}/multiqc_report.html",
            "MultiQC [File]": multiqc_dir,
            "FastQC [File]": fastqc_dir,
        }

        if self.params.get("showNativeReports"):
            result["FastQC Report [Link]"] = f"{fastqc_dir}/fastqc.html"

        return result

    def grandchild_datasets(self) -> list[dict]:
        result = []
        for row in self.samples:
            sample = {_strip_tags(k): v for k, v in row.items()}
            name = sample["Name"]
            result.append({
                "Name": f"FastQC_{name}",
                "FastQC Report [Link]": f"{self.result_dir}/FastQC/{name}_fastqc.html",
                "FastQC Data [File]": f"{self.result_dir}/FastQC/{name}_fastqc_data.txt",
            })
        return result
