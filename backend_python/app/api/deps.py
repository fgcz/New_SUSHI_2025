"""FastAPI dependencies for dependency injection."""

from collections.abc import Generator
from typing import Annotated

from fastapi import Cookie, Depends, Header
from sqlmodel import Session

from app.core.db import get_session
from app.core.exceptions import AuthenticationError, ForbiddenError
from app.core.ldap import LDAPService, get_ldap_service
from app.core.security import decode_access_token
from app.repositories import (
    DatasetRepository,
    JobRepository,
    ProjectRepository,
    RefreshTokenRepository,
    UserRepository,
)
from app.services import AuthService, DatasetService, JobService, ProjectService

# Session dependency
SessionDep = Annotated[Session, Depends(get_session)]


def get_db() -> Generator[Session, None, None]:
    yield from get_session()


# Repository dependencies
def get_dataset_repository(session: SessionDep) -> DatasetRepository:
    return DatasetRepository(session)


def get_job_repository(session: SessionDep) -> JobRepository:
    return JobRepository(session)


def get_project_repository(session: SessionDep) -> ProjectRepository:
    return ProjectRepository(session)


def get_user_repository(session: SessionDep) -> UserRepository:
    return UserRepository(session)


def get_refresh_token_repository(session: SessionDep) -> RefreshTokenRepository:
    return RefreshTokenRepository(session)


# Service dependencies
def get_dataset_service(
    dataset_repo: Annotated[DatasetRepository, Depends(get_dataset_repository)],
    user_repo: Annotated[UserRepository, Depends(get_user_repository)],
) -> DatasetService:
    return DatasetService(dataset_repo, user_repo)


def get_job_service(
    job_repo: Annotated[JobRepository, Depends(get_job_repository)],
    project_repo: Annotated[ProjectRepository, Depends(get_project_repository)],
    dataset_repo: Annotated[DatasetRepository, Depends(get_dataset_repository)],
) -> JobService:
    return JobService(job_repo, project_repo, dataset_repo)


def get_project_service() -> ProjectService:
    return ProjectService()


def get_auth_service(
    user_repo: Annotated[UserRepository, Depends(get_user_repository)],
    refresh_token_repo: Annotated[
        RefreshTokenRepository, Depends(get_refresh_token_repository)
    ],
    ldap_service: Annotated[LDAPService, Depends(get_ldap_service)],
) -> AuthService:
    return AuthService(user_repo, refresh_token_repo, ldap_service)


# Authentication dependencies
class CurrentUser:
    """Represents the currently authenticated user from JWT token."""

    def __init__(self, user_id: int, login: str, projects: list[int]):
        self.user_id = user_id
        self.login = login
        self.projects = projects


def get_current_user(
    authorization: Annotated[str | None, Header()] = None,
) -> CurrentUser:
    """Extract and validate the current user from JWT token.

    Args:
        authorization: The Authorization header value

    Returns:
        CurrentUser object with user info

    Raises:
        AuthenticationError: If token is missing or invalid
    """
    if not authorization:
        raise AuthenticationError("Missing authorization header")

    # Extract token from "Bearer <token>" format
    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise AuthenticationError("Invalid authorization header format")

    token = parts[1]
    payload = decode_access_token(token)

    if not payload:
        raise AuthenticationError("Invalid or expired token")

    return CurrentUser(
        user_id=int(payload["sub"]),
        login=payload["login"],
        projects=payload.get("projects", []),
    )


def get_optional_current_user(
    authorization: Annotated[str | None, Header()] = None,
) -> CurrentUser | None:
    """Get current user if authenticated, None otherwise.

    Use this for routes that work with or without authentication.
    """
    if not authorization:
        return None

    try:
        return get_current_user(authorization)
    except AuthenticationError:
        return None


def require_project_access(project_number: int, user: CurrentUser) -> None:
    """Check if user has access to a project.

    Args:
        project_number: The project number to check access for
        user: The current authenticated user

    Raises:
        ForbiddenError: If user doesn't have access to the project
    """
    if project_number not in user.projects:
        raise ForbiddenError(f"You don't have access to project {project_number}")


def get_refresh_token_from_cookie(
    refresh_token: Annotated[str | None, Cookie()] = None,
) -> str:
    """Extract refresh token from cookie.

    Args:
        refresh_token: The refresh token from cookie

    Returns:
        The refresh token string

    Raises:
        AuthenticationError: If refresh token is missing
    """
    if not refresh_token:
        raise AuthenticationError("Missing refresh token")
    return refresh_token


# Type aliases for cleaner route signatures
DatasetRepoDep = Annotated[DatasetRepository, Depends(get_dataset_repository)]
JobRepoDep = Annotated[JobRepository, Depends(get_job_repository)]
ProjectRepoDep = Annotated[ProjectRepository, Depends(get_project_repository)]
UserRepoDep = Annotated[UserRepository, Depends(get_user_repository)]
RefreshTokenRepoDep = Annotated[
    RefreshTokenRepository, Depends(get_refresh_token_repository)
]

DatasetServiceDep = Annotated[DatasetService, Depends(get_dataset_service)]
JobServiceDep = Annotated[JobService, Depends(get_job_service)]
ProjectServiceDep = Annotated[ProjectService, Depends(get_project_service)]
AuthServiceDep = Annotated[AuthService, Depends(get_auth_service)]

CurrentUserDep = Annotated[CurrentUser, Depends(get_current_user)]
OptionalCurrentUserDep = Annotated[CurrentUser | None, Depends(get_optional_current_user)]
RefreshTokenDep = Annotated[str, Depends(get_refresh_token_from_cookie)]
