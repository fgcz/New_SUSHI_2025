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
    """Validate application configuration.

    TODO: Implement real validation logic.
    For now, returns the config unchanged.
    """
    try:
        # Verify app exists
        get_app(app_name)
        # Return config as-is (no-op validation)
        return config
    except ValueError:
        raise HTTPException(status_code=404, detail=f"Application '{app_name}' not found")
