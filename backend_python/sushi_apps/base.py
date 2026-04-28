from abc import ABC, abstractmethod
from typing import Any, Literal


class SushiApp(ABC):
    """Base class all SUSHI apps must inherit from.

    Apps must implement:
    - commands()
    - next_dataset()

    Optional hooks:
    - set_default_parameters()
    - adjust_requirements()
    - grandchild_datasets()
    """

    # === Class attributes (subclasses must/can define) ===

    name: str  # Required: app display name, used as registry key
    category: str  # Required: grouping (QC, Alignment, etc.)
    description: str = ""  # Optional: help text
    required_columns: list[str] = []  # Columns input dataset must have
    modules: list[str] = []  # HPC modules to load

    # Parameter definitions
    param_groups: list[dict] = []  # UI grouping for params
    params_definition: list[dict] = []  # Full param schema

    # === Auto-registration ===

    _registry: dict[str, type["SushiApp"]] = {}

    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)
        if hasattr(cls, "name") and cls.name:
            SushiApp._registry[cls.name] = cls

    # === Instance state ===

    def __init__(self):
        # Parameters (values set by configure())
        self.params: dict[str, Any] = {}

        # Dataset rows
        self.samples: list[dict] = []  # All rows from input dataset
        self.dataset: dict | list[dict] = {}  # Current row(s) for commands()

        # Paths (set by configure())
        self.project: str = ""
        self.gstore_dir: str = ""
        self.result_dir: str = ""
        self.input_dataset_tsv_path: str = ""

        # Process mode
        self.process_mode: Literal["SAMPLE", "DATASET", "BATCH"] = "DATASET"

        # Job state (for SAMPLE mode iteration)
        self.last_job: bool = True
        self.current_sample_index: int = 0

        # Initialize params with defaults
        for param_def in self.params_definition:
            self.params[param_def["name"]] = param_def.get("default")

    # === Configuration ===

    def configure(
        self,
        user_params: dict,
        dataset_rows: list[dict],
        project: str,
        gstore_dir: str,
        result_dir: str,
        input_dataset_tsv_path: str,
        process_mode: Literal["SAMPLE", "DATASET", "BATCH"] = "DATASET",
        project_defaults: dict | None = None,
    ) -> None:
        """Configure the app with runtime data.

        Parameter priority (lowest to highest):
        1. App defaults (from params_definition, set in __init__)
        2. Project defaults (passed in, loaded by service)
        3. User params (from frontend request)

        Args:
            user_params: Parameters from frontend request
            dataset_rows: Input dataset rows loaded from DB
            project: Project identifier (e.g., "p1001")
            gstore_dir: Base gstore path (e.g., "/srv/gstore/projects")
            result_dir: Output directory relative to gstore
            input_dataset_tsv_path: Path where input dataset TSV will be written
            process_mode: SAMPLE (per-row), DATASET (all), or BATCH
            project_defaults: Project-specific param defaults (loaded by service)
        """
        # Store paths and state
        self.project = project
        self.gstore_dir = gstore_dir
        self.result_dir = result_dir
        self.input_dataset_tsv_path = input_dataset_tsv_path
        self.process_mode = process_mode

        # Store dataset
        self.samples = dataset_rows
        if process_mode == "DATASET":
            self.dataset = dataset_rows
        elif dataset_rows:
            self.dataset = dataset_rows[0]

        # Apply project defaults (priority 2)
        if project_defaults:
            for key, value in project_defaults.items():
                if key in self.params:
                    self.params[key] = self._coerce_param_value(key, value)

        # Apply user params (priority 3 - highest)
        for key, value in user_params.items():
            if key in self.params:
                self.params[key] = value

    def set_sample(self, index: int, is_last: bool = False) -> None:
        """Set current sample for SAMPLE mode iteration.

        Called by the service when iterating over samples.
        """
        self.current_sample_index = index
        self.last_job = is_last
        if index < len(self.samples):
            self.dataset = self.samples[index]

    # === Abstract methods (apps must implement) ===

    @abstractmethod
    def commands(self) -> str:
        """Return shell commands to execute.

        For R apps, typically: return r_runner(self, "EzAppName")
        For direct commands: return the bash commands as string
        """
        pass

    @abstractmethod
    def next_dataset(self) -> dict:
        """Return output dataset row specification.

        Keys should include column names with optional tags:
        - "Name": sample/dataset name
        - "Report [Link]": path to HTML report
        - "Data [File]": path to output file
        """
        pass

    # === Optional hooks (apps can override) ===

    def set_default_parameters(self) -> None:
        """Set defaults based on input dataset.

        Called after configure(), before validation.
        Example: self.params["paired"] = self.dataset_has_column("Read2")
        """
        pass

    def adjust_requirements(self) -> None:
        """Adjust required_columns and modules based on final parameter values.

        Called by JobSubmissionService after set_default_parameters(),
        before validation runs.

        Examples:
            if self.params.get("paired"):
                self.required_columns = [*self.required_columns, "Read2"]
            if self.params.get("useGPU"):
                self.modules.append("CUDA/11.0")
        """
        pass

    def grandchild_datasets(self) -> list[dict]:
        """Return additional output datasets (optional).

        Some apps produce multiple output datasets.
        Override this to return a list of dataset row dicts.
        """
        return []

    # === Utilities ===

    @property
    def required_params(self) -> list[str]:
        """Get list of required parameter names. Used by validation."""
        return [p["name"] for p in self.params_definition if p.get("required")]

    def get_param_definition(self, name: str) -> dict | None:
        """Get parameter definition by name. Used by coerce_param_value."""
        for p in self.params_definition:
            if p["name"] == name:
                return p
        return None

    def dataset_has_column(self, column_name: str) -> bool:
        """Check if input dataset has a specific column.
        Matches column with tags like [File], [Factor], etc.
        Used by set_default_parameters()
        """
        if not self.samples:
            return False
        first_row = self.samples[0]
        for key in first_row.keys():
            base_name = key.split("[")[0].strip()
            if base_name == column_name:
                return True
        return False

    def _coerce_param_value(self, param_name: str, value: Any) -> Any:
        """Coerce a parameter value to the correct type.

        Project defaults come from TSV as strings.
        """
        param_def = self.get_param_definition(param_name)
        if not param_def:
            return value

        param_type = param_def.get("type", "text")

        if value is None:
            return None

        if param_type == "integer":
            return int(value) if value != "" else None
        elif param_type == "boolean":
            if isinstance(value, bool):
                return value
            return str(value).lower() in ("true", "1", "yes")
        elif param_type in ("float", "number"):
            return float(value) if value != "" else None
        else:
            return value
