"""Validators for SUSHI app execution.

Validates that:
- Input dataset has required columns
- Required parameters are provided
- Parameter values are valid types/ranges
"""

from sushi_apps.base import SushiApp


class SushiValidationError(Exception):
    """Raised when validation fails."""

    def __init__(self, message: str, errors: list[str] | None = None):
        super().__init__(message)
        self.message = message
        self.errors = errors or []


def validate_columns(app: SushiApp, sample_columns: list[str]) -> None:
    """Check that samples have all required columns.

    Args:
        app: Configured SushiApp instance
        sample_columns: List of column names from input dataset

    Raises:
        SushiValidationError: If required columns are missing
    """
    # TODO: Implement column validation
    # - Handle column tags like [File], [Factor]
    # - Check app.required_columns against sample_columns
    raise NotImplementedError("validate_columns not yet implemented")


def validate_params(app: SushiApp, params: dict) -> None:
    """Check that required parameters are provided and valid.

    Args:
        app: SushiApp instance (uses params_definition)
        params: User-provided parameters

    Raises:
        SushiValidationError: If required params missing or invalid
    """
    # TODO: Implement parameter validation
    # - Check required params are present
    # - Validate types match params_definition
    # - Validate ranges/options where specified
    raise NotImplementedError("validate_params not yet implemented")


def validate_app(app: SushiApp) -> None:
    """Run all validations on a configured app.

    Args:
        app: Fully configured SushiApp instance

    Raises:
        SushiValidationError: If any validation fails
    """
    # TODO: Implement full validation
    # - validate_columns
    # - validate_params
    # - app-specific validation hooks
    raise NotImplementedError("validate_app not yet implemented")
