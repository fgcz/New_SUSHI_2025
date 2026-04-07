"""Authentication routes for login, refresh, and logout."""

from fastapi import APIRouter, Response
from pydantic import BaseModel

from typing import Annotated

from fastapi import Cookie

from app.api.deps import (
    AuthServiceDep,
    CurrentUserDep,
    RefreshTokenDep,
)
from app.core.config import settings

router = APIRouter()


class LoginOptions(BaseModel):
    ldap_auth: bool
    authentication_skipped: bool


class LoginRequest(BaseModel):
    username: str
    password: str


@router.get("/login_options")
def login_options() -> LoginOptions:
    """Return available authentication methods.

    If authentication_skipped is True, LDAP is bypassed and any request works.
    """
    return LoginOptions(
        ldap_auth=not settings.SKIP_AUTH,
        authentication_skipped=settings.SKIP_AUTH,
    )


@router.post("/login")
def login(request: LoginRequest, response: Response, service: AuthServiceDep) -> dict:
    """Authenticate user with LDAP and return tokens.

    Returns access token in response body and sets refresh token as HttpOnly cookie.
    """
    result = service.login(request.username, request.password)

    # Set refresh token as HttpOnly cookie
    response.set_cookie(
        key="refresh_token",
        value=result["refresh_token"],
        httponly=True,
        secure=settings.ENVIRONMENT != "local",  # HTTPS only in production
        samesite="strict",
        max_age=settings.JWT_REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60 * 60,
    )

    # Return access token in body (don't include refresh token)
    return {
        "access_token": result["access_token"],
        "token_type": result["token_type"],
        "user": result["user"],
    }


@router.post("/refresh")
def refresh(refresh_token: RefreshTokenDep, service: AuthServiceDep) -> dict:
    """Refresh the access token using the refresh token from cookie.

    Returns a new access token.
    """
    return service.refresh(refresh_token)


@router.post("/logout")
def logout(
    response: Response,
    service: AuthServiceDep,
    refresh_token: Annotated[str | None, Cookie()] = None,
) -> dict:
    """Logout by revoking the refresh token and clearing the cookie."""
    if refresh_token:
        service.logout(refresh_token)

    # Clear the refresh token cookie
    response.delete_cookie(key="refresh_token")

    return {"message": "Logged out successfully"}


@router.post("/logout-all")
def logout_all(
    user: CurrentUserDep,
    response: Response,
    service: AuthServiceDep,
) -> dict:
    """Logout from all sessions by revoking all refresh tokens."""
    count = service.logout_all(user.user_id)

    # Clear the refresh token cookie
    response.delete_cookie(key="refresh_token")

    return {"message": f"Logged out from {count} session(s)"}


@router.get("/me")
def get_current_user_info(user: CurrentUserDep) -> dict:
    """Get current authenticated user info from token."""
    return {
        "user_id": user.user_id,
        "login": user.login,
        "projects": user.projects,
    }
