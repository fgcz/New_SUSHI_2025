"""Application routes - application configs and form schemas."""

from fastapi import APIRouter

from app.api.deps import CurrentUserDep
from app.api.serializers.omics_app import serialize_app_config
from app.core.exceptions import NotFoundError
from omics_apps import get_app, list_apps

router = APIRouter()


@router.get("/")
def get_applications_list(current_user: CurrentUserDep) -> dict:
    """Get list of available applications."""
    return {
        "omics_apps": list_apps(),
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
        raise NotFoundError("Application", app_name)


@router.post("/{app_name}/validate")
def validate_application_config(
    app_name: str,
    current_user: CurrentUserDep,
    config: dict,
) -> dict:
    """Validate and adjust application configuration based on current values."""
    try:
        app = get_app(app_name)
        current_values = config.get("config", {})
        adjusted_params = app.adjust_params(current_values)
        return serialize_app_config(app, adjusted_params)
    except ValueError:
        raise NotFoundError("Application", app_name)
