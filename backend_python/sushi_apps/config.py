"""Configuration constants for SUSHI apps."""

# Paths
EZ_GLOBAL_VARIABLES = "/usr/local/ngseq/opt/EZ_GLOBAL_VARIABLES.txt"
CONDA_PROFILE = "/usr/local/ngseq/miniforge3/etc/profile.d/conda.sh"
MINICONDA_PROFILE = "/usr/local/ngseq/miniconda3/etc/profile.d/conda.sh"
DEFAULT_GSTORE_DIR = "/srv/gstore/projects"
DEFAULT_SCRATCH_DIR = "/scratch"

# Process modes
PROCESS_MODE_SAMPLE = "SAMPLE"
PROCESS_MODE_DATASET = "DATASET"
PROCESS_MODE_BATCH = "BATCH"

# Default SLURM values
DEFAULT_CORES = 1
DEFAULT_RAM = 4  # GB
DEFAULT_SCRATCH = 10  # GB
DEFAULT_PARTITION = "normal"
