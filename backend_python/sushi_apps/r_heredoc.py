"""R heredoc generation for ezRun apps.

Generates bash script fragments containing R heredocs that invoke ezRun apps.
Mirrors Ruby SUSHI's run_RApp() from global_variables.rb.
"""

from typing import TYPE_CHECKING, Any

from app.core.config import settings

if TYPE_CHECKING:
    from sushi_apps.base import SushiApp


def generate_r_heredoc(
    app: "SushiApp",
    app_name: str | None = None,
    lib_path: str | None = None,
    conda_env: str | None = None,
) -> str:
    """Generate R heredoc command that invokes an ezRun app.

    This mirrors Ruby's run_RApp() from global_variables.rb.

    Args:
        app: Configured SushiApp instance
        app_name: R class name to invoke (e.g., "EzAppFastqc").
                  Defaults to "EzApp{app.name}"
        lib_path: Optional custom R library path
        conda_env: Optional conda environment to activate

    Returns:
        Bash script fragment containing the R heredoc
    """
    if app_name is None:
        app_name = f"EzApp{app.name}"

    lines = []

    # Optional conda activation
    if conda_env:
        lines.append(f". '{settings.CONDA_PROFILE}'")
        lines.append(f"set +e; conda activate {conda_env}; set -e")

    # Start R heredoc
    lines.append("R --vanilla --slave << EOT")

    # Set global variables path
    lines.append(f"EZ_GLOBAL_VARIABLES <<- '{settings.EZ_GLOBAL_VARIABLES}'")

    # Optional custom library path
    if lib_path:
        lines.append(f".libPaths('{lib_path}')")

    # Load ezRun with retry logic
    lines.append("if (!library(ezRun, logical.return = TRUE)){")
    lines.append("message('retry loading ezRun')")
    lines.append("Sys.sleep(120)")
    lines.append("library(ezRun)")
    lines.append("}")

    # Serialize parameters
    lines.append("param = list()")
    for key, value in app.params.items():
        r_value = _to_r_value(value)
        lines.append(f"param[['{key}']] = {r_value}")

    # Add runtime params that R apps expect
    lines.append(f"param[['dataRoot']] = '{app.gstore_dir}'")
    lines.append(f"param[['resultDir']] = '{app.result_dir}'")
    lines.append(f"param[['isLastJob']] = {_to_r_value(app.last_job)}")

    # Serialize output (next_dataset)
    lines.append("output = list()")
    output = app.next_dataset()
    for key, value in output.items():
        r_value = _to_r_value(value)
        lines.append(f"output[['{key}']] = {r_value}")

    # Serialize grandchild outputs (if any)
    grandchild_data = app.grandchild_datasets()
    if grandchild_data:
        lines.append("grandchild_output = list()")
        for i, dataset in enumerate(grandchild_data, start=1):
            lines.append(f"grandchild_output[[{i}]] = list()")
            for key, value in dataset.items():
                r_value = _to_r_value(value)
                lines.append(f"grandchild_output[[{i}]][['{key}']] = {r_value}")

        # Add names to the list for easier R access
        names = [ds.get("Name", "") for ds in grandchild_data if ds.get("Name")]
        if names:
            names_r = ", ".join(f"'{_escape_r_string(n)}'" for n in names)
            lines.append(f"names(grandchild_output) = c({names_r})")
    else:
        lines.append("grandchild_output = list()")

    # Serialize input
    if app.process_mode == "DATASET":
        # DATASET mode: pass path to input TSV
        lines.append(f"input = '{app.input_dataset_tsv_path}'")
    else:
        # SAMPLE mode: pass current row as list
        lines.append("input = list()")
        current_sample = _get_current_sample(app)
        for key, value in current_sample.items():
            r_value = _to_r_value(value)
            lines.append(f"input[['{key}']] = {r_value}")

    # Invoke the R app
    lines.append(f"{app_name}\\$new()\\$run(input=input, output=output, param=param)")

    # End heredoc
    lines.append("EOT")

    return "\n".join(lines)


# === Private Helpers ===


def _to_r_value(value: Any) -> str:
    """Convert a Python value to R syntax."""
    if value is None:
        return "''"
    elif isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    elif isinstance(value, list):
        if not value:
            return "c()"
        items = ", ".join(f"'{_escape_r_string(str(v))}'" for v in value)
        return f"c({items})"
    else:
        return f"'{_escape_r_string(str(value))}'"


def _escape_r_string(s: str) -> str:
    """Escape special characters for R string literals."""
    return s.replace("\\", "\\\\").replace("'", "\\'")


def _get_current_sample(app: "SushiApp") -> dict:
    """Get the current sample row for SAMPLE mode."""
    if isinstance(app.dataset, dict):
        return app.dataset
    elif app.samples and app.current_sample_index < len(app.samples):
        return app.samples[app.current_sample_index]
    return {}
