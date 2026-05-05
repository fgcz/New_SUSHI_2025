"""Application routes - application configs and form schemas."""

from fastapi import APIRouter, HTTPException

from app.api.deps import CurrentUserDep
from app.api.serializers.sushi import serialize_app_config
from sushi_apps import get_app, list_apps

router = APIRouter()


@router.get("/")
def get_applications_list(current_user: CurrentUserDep) -> dict:
    """Get list of available applications."""
    return {
        "sushi_apps": list_apps(),
    }


@router.get("/{app_name}")
def get_application_config(
    app_name: str,
    current_user: CurrentUserDep,
) -> dict:
    """Get application configuration/form schema."""
    try:
        app = get_app(app_name)
        return serialize_app_config(app)
    except ValueError:
        raise HTTPException(status_code=404, detail=f"Application '{app_name}' not found")


@router.post("/{app_name}/validate")
def validate_application_config(
    app_name: str,
    current_user: CurrentUserDep,
    config: dict,
) -> dict:
    """Validate and adjust application configuration based on current values.

    Apps can override adjust_params() to dynamically modify the form schema
    based on user input (e.g., show/hide fields, change options).
    """
    try:
        app = get_app(app_name)
        current_values = config.get("config", {})

        # Let app adjust params based on current form values
        adjusted_params = app.adjust_params(current_values)

        # Return updated schema
        return serialize_app_config(app, adjusted_params)
    except ValueError:
        raise HTTPException(status_code=404, detail=f"Application '{app_name}' not found")
