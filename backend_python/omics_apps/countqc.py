"""CountQC application - quality control for count data."""

from omics_apps.base import MultiOmicsApp


class CountQCApp(MultiOmicsApp):
    """Quality control analysis for count data (RNA-seq, etc.)."""

    name = "CountQC"
    category = "Development"
    description = "Quality control analysis for count data"
    required_columns = ["Name", "Count"]

    param_groups = [
        {"id": "analysis", "title": "Analysis Parameters", "description": "CountQC-specific settings"},
        {"id": "resources", "title": "Resource Parameters", "description": "Compute resources for the job"},
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
            "default": 32,
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
            "name": "refBuild",
            "type": "select",
            "default": "hg38",
            "options": ["hg38", "hg19", "mm10", "mm39"],
            "group": "analysis",
            "required": True,
            "description": "Reference genome build",
        },
        {
            "name": "paired",
            "type": "boolean",
            "default": True,
            "group": "analysis",
            "description": "Paired-end data",
        },
        {
            "name": "strandMode",
            "type": "select",
            "default": "sense",
            "options": ["sense", "antisense", "both"],
            "group": "analysis",
            "description": "Strand mode for counting",
        },
        {
            "name": "featureLevel",
            "type": "select",
            "default": "gene",
            "options": ["gene", "transcript", "exon"],
            "group": "analysis",
            "description": "Feature level for counting",
        },
        {
            "name": "transcriptTypes",
            "type": "text",
            "default": "protein_coding,lncRNA",
            "group": "analysis",
            "description": "Transcript types (comma-separated)",
        },
        {
            "name": "minReads",
            "type": "integer",
            "default": 10,
            "group": "analysis",
            "description": "Minimum read count threshold",
        },
        {
            "name": "normMethod",
            "type": "select",
            "default": "TMM",
            "options": ["TMM", "RLE", "upperquartile", "none"],
            "group": "analysis",
            "description": "Normalization method",
        },
        {
            "name": "runGO",
            "type": "boolean",
            "default": True,
            "group": "analysis",
            "description": "Run GO enrichment analysis",
        },
        {
            "name": "backgroundExpression",
            "type": "integer",
            "default": 5,
            "group": "analysis",
            "description": "Background expression threshold",
        },
    ]

    def commands(self) -> str:
        cmd = f"""
# CountQC Analysis
Rscript /opt/sushi/scripts/countqc.R \\
  --input {self.gstore_dir}/{self.dataset['Count']} \\
  --output {self.result_dir} \\
  --cores {self.params['cores']} \\
  --ref {self.params['refBuild']} \\
  --strand {self.params['strandMode']} \\
  --feature {self.params['featureLevel']} \\
  --minReads {self.params['minReads']} \\
  --norm {self.params['normMethod']}
"""
        if self.params.get("runGO"):
            cmd += "  --runGO\n"

        return cmd.strip()

    def next_dataset(self) -> dict:
        name = self.dataset["Name"]
        return {
            "Name": name,
            "QC Report [Link]": f"{self.result_dir}/{name}_countqc_report.html",
            "Normalized Counts [File]": f"{self.result_dir}/{name}_normalized_counts.tsv",
            "Stats [File]": f"{self.result_dir}/{name}_stats.json",
        }
