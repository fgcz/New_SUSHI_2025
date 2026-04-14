"""Application routes - application configs and form schemas."""

from fastapi import APIRouter, HTTPException

from app.api.deps import CurrentUserDep

router = APIRouter()


# Mock applications list
MOCK_SUSHI_APPS = [
    "FastQC", "STAR", "Bowtie2", "BWA", "Salmon", "Kallisto",
    "DESeq2", "EdgeR", "Cufflinks", "HTSeq",
]
MOCK_RETIRED_APPS = [
    "TopHat", "Cuffquant", "Cuffdiff", "Cuffmerge", "Cuffcompare",
    "CuffnormApp", "SoapAligner", "MAQ", "ELAND", "Novoalign",
]


@router.get("/")
def get_applications_list(current_user: CurrentUserDep) -> dict:
    """Get list of available and retired applications.

    MOCK: Returns hardcoded application lists.
    Real implementation would query SushiApplication table.
    """
    return {
        "sushi_apps": MOCK_SUSHI_APPS,
        "retired_apps": MOCK_RETIRED_APPS,
    }


# Mock CountQC application config
COUNTQC_CONFIG = {
    "application": {
        "name": "CountQC",
        "class_name": "CountQC",
        "category": "QC",
        "description": "Quality control analysis for count data",
        "required_columns": ["Name", "Count"],
        "required_params": ["cores", "ram"],
        "modules": ["Tools/QC"],
        "param_groups": [
            {
                "id": "resources",
                "title": "Resource Parameters",
                "description": "Configure compute resources for the job",
                "fields": [
                    {"name": "cores", "type": "integer", "default_value": 8, "description": "Number of CPU cores"},
                    {"name": "ram", "type": "integer", "default_value": 32, "description": "RAM in GB"},
                    {"name": "scratch", "type": "integer", "default_value": 400, "description": "Scratch space in GB"},
                    {"name": "partition", "type": "select", "default_value": "normal", "options": ["normal", "high", "low"], "description": "Cluster partition"},
                ],
            },
            {
                "id": "analysis",
                "title": "Tool Parameters",
                "description": "Configure analysis parameters",
                "fields": [
                    {"name": "ref", "type": "select", "default_value": "hg38", "options": ["hg38", "hg19", "mm10", "mm39"], "description": "Reference genome"},
                    {"name": "paired", "type": "boolean", "default_value": True, "description": "Paired-end data"},
                    {"name": "strandMode", "type": "select", "default_value": "sense", "options": ["sense", "antisense", "both"], "description": "Strand mode"},
                    {"name": "featureLevel", "type": "select", "default_value": "gene", "options": ["gene", "transcript", "exon"], "description": "Feature level"},
                    {"name": "transcriptTypes", "type": "text", "default_value": "protein_coding,lncRNA", "description": "Transcript types (comma-separated)"},
                    {"name": "minReads", "type": "integer", "default_value": 10, "description": "Minimum read count"},
                    {"name": "normMethod", "type": "select", "default_value": "TMM", "options": ["TMM", "RLE", "upperquartile", "none"], "description": "Normalization method"},
                    {"name": "runGO", "type": "boolean", "default_value": True, "description": "Run GO enrichment analysis"},
                    {"name": "backgroundExpression", "type": "integer", "default_value": 5, "description": "Background expression threshold"},
                ],
            },
        ],
    },
}


@router.get("/{app_name}")
def get_application_config(
    app_name: str,
    current_user: CurrentUserDep,
) -> dict:
    """Get application configuration/form schema.

    Currently returns mock data for CountQC. Real implementation
    will load configs from the sushi application registry.
    """
    if app_name == "CountQC":
        return COUNTQC_CONFIG

    raise HTTPException(status_code=404, detail=f"Application '{app_name}' not found")


@router.post("/{app_name}/validate")
def validate_application_config(
    app_name: str,
    current_user: CurrentUserDep,
    config: dict,
) -> dict:
    """Validate application configuration.

    Returns updated config with validation results. Mock implementation
    sets integer fields to 0 and disables ram field for demonstration.
    """
    if app_name == "CountQC":
        # Return modified config to demonstrate server-side validation
        validated_config = {
            "application": {
                **COUNTQC_CONFIG["application"],
                "param_groups": [
                    {
                        "id": "resources",
                        "title": "Resource Parameters",
                        "description": "Configure compute resources for the job",
                        "fields": [
                            {"name": "cores", "type": "integer", "default_value": 0, "description": "Number of CPU cores"},
                            {"name": "ram", "type": "integer", "default_value": 0, "description": "RAM in GB", "disabled": True},
                            {"name": "scratch", "type": "integer", "default_value": 0, "description": "Scratch space in GB"},
                            {"name": "partition", "type": "select", "default_value": "normal", "options": ["normal", "high", "low"], "description": "Cluster partition"},
                        ],
                    },
                    {
                        "id": "analysis",
                        "title": "Tool Parameters",
                        "description": "Configure analysis parameters",
                        "fields": [
                            {"name": "ref", "type": "select", "default_value": "hg38", "options": ["hg38", "hg19", "mm10", "mm39"], "description": "Reference genome"},
                            {"name": "paired", "type": "boolean", "default_value": True, "description": "Paired-end data"},
                            {"name": "strandMode", "type": "select", "default_value": "sense", "options": ["sense", "antisense", "both"], "description": "Strand mode"},
                            {"name": "featureLevel", "type": "select", "default_value": "gene", "options": ["gene", "transcript", "exon"], "description": "Feature level"},
                            {"name": "transcriptTypes", "type": "text", "default_value": "protein_coding,lncRNA", "description": "Transcript types (comma-separated)"},
                            {"name": "minReads", "type": "integer", "default_value": 0, "description": "Minimum read count"},
                            {"name": "normMethod", "type": "select", "default_value": "TMM", "options": ["TMM", "RLE", "upperquartile", "none"], "description": "Normalization method"},
                            {"name": "runGO", "type": "boolean", "default_value": True, "description": "Run GO enrichment analysis"},
                            {"name": "backgroundExpression", "type": "integer", "default_value": 0, "description": "Background expression threshold"},
                        ],
                    },
                ],
            },
        }
        return validated_config

    raise HTTPException(status_code=404, detail=f"Application '{app_name}' not found")
