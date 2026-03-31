from fastapi import APIRouter
from pydantic import BaseModel

from app.core.config import settings

router = APIRouter()


class LoginOptions(BaseModel):
    ldap_auth: bool
    authentication_skipped: bool
    current_user: str | None


@router.get("/login_options")
def login_options() -> LoginOptions:
    """Return available authentication methods.

    If authentication_skipped is True, frontend skips authentication.
    """
    # For now, skip auth in local environment
    skip_auth = settings.ENVIRONMENT == "local"

    return LoginOptions(
        ldap_auth=not skip_auth,
        authentication_skipped=skip_auth,
        current_user=None,
    )
