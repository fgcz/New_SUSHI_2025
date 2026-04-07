"""Authentication service for login, refresh, and logout operations."""

from app.core.exceptions import AuthenticationError
from app.core.ldap import LDAPAuthError, LDAPService
from app.core.security import (
    create_access_token,
    create_refresh_token,
    get_refresh_token_expires_at,
)
from app.repositories.refresh_token import RefreshTokenRepository


class AuthService:
    """Service for authentication operations."""

    def __init__(
        self,
        refresh_token_repo: RefreshTokenRepository,
        ldap_service: LDAPService,
    ):
        self.refresh_token_repo = refresh_token_repo
        self.ldap_service = ldap_service

    def login(self, username: str, password: str) -> dict:
        """Authenticate user and return tokens.

        Args:
            username: The user's login name
            password: The user's password

        Returns:
            Dict with access_token, refresh_token, and user info

        Raises:
            AuthenticationError: If credentials are invalid
        """
        # Authenticate against LDAP (or mock in dev mode)
        try:
            ldap_user = self.ldap_service.authenticate(username, password)
        except LDAPAuthError as e:
            raise AuthenticationError(str(e))

        # Create access token with user info from LDAP
        # user_id=0 since we don't sync to local DB
        access_token = create_access_token(
            user_id=0,
            login=ldap_user["login"],
            projects=ldap_user["projects"],
        )

        # Create and store refresh token
        refresh_token = create_refresh_token()
        self.refresh_token_repo.create(
            token=refresh_token,
            user_id=0,  # No local user ID
            expires_at=get_refresh_token_expires_at(),
        )

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "user": {
                "id": 0,
                "login": ldap_user["login"],
                "email": ldap_user["email"],
            },
        }

    def refresh(self, refresh_token: str) -> dict:
        """Refresh an access token.

        Args:
            refresh_token: The refresh token string

        Returns:
            Dict with new access_token

        Raises:
            AuthenticationError: If refresh token is invalid
        """
        # Validate refresh token exists and is not revoked
        token_record = self.refresh_token_repo.get_by_token(refresh_token)
        if not token_record:
            raise AuthenticationError("Invalid or expired refresh token")

        # Create new access token
        # Note: We don't have user info stored, so projects will be empty
        # Frontend should re-login periodically to refresh project list
        access_token = create_access_token(
            user_id=0,
            login="user",  # Generic since we don't store user info with token
            projects=[],
        )

        return {
            "access_token": access_token,
            "token_type": "bearer",
        }

    def logout(self, refresh_token: str) -> bool:
        """Logout by revoking the refresh token.

        Args:
            refresh_token: The refresh token string

        Returns:
            True if token was revoked, False if not found
        """
        return self.refresh_token_repo.revoke(refresh_token)

    def logout_all(self, user_id: int) -> int:
        """Logout from all sessions by revoking all refresh tokens.

        Args:
            user_id: The user's ID

        Returns:
            Number of tokens revoked
        """
        return self.refresh_token_repo.revoke_all_for_user(user_id)
