"""FastQC application - quality control for sequencing data.

Mirrors Ruby's FastqcApp.rb - uses ezRun's EzAppFastqc for the actual analysis.
"""

from sushi_apps.base import SushiApp
from sushi_apps.r_heredoc import generate_r_heredoc


class FastQCApp(SushiApp):
    """Quality control analysis for FASTQ files."""

    name = "FastQC"
    category = "QC"
    description = "Quality control analysis for high throughput sequence data"
    required_columns = ["Name", "Read1"]

    modules = ["QC/FastQC", "Dev/R", "Tools/Picard", "Tools/samtools", "Dev/Python", "QC/fastp"]

    param_groups = [
        {"id": "resources", "title": "Resource Parameters", "description": "Compute resources for the job"},
        {"id": "analysis", "title": "Analysis Parameters", "description": "FastQC-specific settings"},
    ]

    params_definition = [
        # Resource parameters
        {
            "name": "cores",
            "type": "select",
            "default": 8,
            "options": [1, 2, 4, 8],
            "group": "resources",
            "required": True,
            "description": "Number of CPU cores",
        },
        {
            "name": "ram",
            "type": "integer",
            "default": 15,
            "group": "resources",
            "description": "RAM in GB",
        },
        {
            "name": "scratch",
            "type": "integer",
            "default": 100,
            "group": "resources",
            "description": "Scratch space in GB",
        },
        {
            "name": "partition",
            "type": "select",
            "default": "normal",
            "options": ["normal", "high", "low"],
            "group": "resources",
            "description": "Cluster partition",
        },
        # Analysis parameters
        {
            "name": "paired",
            "type": "boolean",
            "default": False,
            "group": "analysis",
            "required": True,
            "description": "Paired-end data (will also process Read2)",
        },
        {
            "name": "showNativeReports",
            "type": "boolean",
            "default": False,
            "group": "analysis",
            "description": "Show native FastQC reports (uses MultiQC summary as primary)",
        },
        {
            "name": "cmdOptions",
            "type": "text",
            "default": "",
            "group": "analysis",
            "description": "Additional FastQC command line options",
            "placeholder": "--noextract --nogroup",
        },
    ]

    def set_default_parameters(self) -> None:
        """Auto-detect paired status from dataset."""
        if self.dataset_has_column("Read2"):
            self.params["paired"] = True

    def adjust_requirements(self) -> None:
        """Add Read2 to required columns if paired."""
        if self.params.get("paired") and "Read2" not in self.required_columns:
            self.required_columns = [*self.required_columns, "Read2"]

    def commands(self) -> str:
        """Generate R heredoc that invokes EzAppFastqc."""
        return generate_r_heredoc(self, app_name="EzAppFastqc")

    def next_dataset(self) -> dict:
        """Define output dataset structure.

        Matches Ruby FastqcApp#next_dataset - outputs go to result_dir.
        """
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
