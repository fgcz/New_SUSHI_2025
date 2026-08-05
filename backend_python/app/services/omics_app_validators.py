"""Validators for OmicsApp execution.

Validates that:
- Input dataset has required columns
- Required parameters are provided
- Parameter values are valid types/ranges
"""

from omics_apps.base import MultiOmicsApp


class OmicsAppValidationError(Exception):
    """Raised when validation fails."""

    def __init__(self, message: str, errors: list[str] | None = None):
        super().__init__(message)
        self.message = message
        self.errors = errors or []


def validate_columns(app: MultiOmicsApp, sample_columns: list[str]) -> None:
    """Check that samples have all required columns.

    Args:
        app: Configured MultiOmicsApp instance
        sample_columns: List of column names from input dataset

    Raises:
        OmicsAppValidationError: If required columns are missing
    """
    # TODO: Implement column validation
    # - Handle column tags like [File], [Factor]
    # - Check app.required_columns against sample_columns
    raise NotImplementedError("validate_columns not yet implemented")


def validate_params(app: MultiOmicsApp, params: dict) -> None:
    """Check that required parameters are provided and valid.

    Args:
        app: MultiOmicsApp instance (uses params_definition)
        params: User-provided parameters

    Raises:
        OmicsAppValidationError: If required params missing or invalid
    """
    # TODO: Implement parameter validation
    # - Check required params are present
    # - Validate types match params_definition
    # - Validate ranges/options where specified
    raise NotImplementedError("validate_params not yet implemented")


def validate_app(app: MultiOmicsApp) -> None:
    """Run all validations on a configured app.

    Args:
        app: Fully configured MultiOmicsApp instance

    Raises:
        OmicsAppValidationError: If any validation fails
    """
    # TODO: Implement full validation
    # - validate_columns
    # - validate_params
    # - app-specific validation hooks
    raise NotImplementedError("validate_app not yet implemented")
