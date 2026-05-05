"""Constants for SUSHI apps.

Infrastructure paths (GSTORE_DIR, SCRATCH_DIR, etc.) are in app/core/config.py
and can be overridden via environment variables.
"""

# Process modes
PROCESS_MODE_SAMPLE = "SAMPLE"
PROCESS_MODE_DATASET = "DATASET"
PROCESS_MODE_BATCH = "BATCH"

# Default SLURM values
DEFAULT_CORES = 1
DEFAULT_RAM = 4  # GB
DEFAULT_SCRATCH = 10  # GB
DEFAULT_PARTITION = "normal"
