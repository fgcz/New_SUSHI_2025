"""Authentication service for login, refresh, and logout operations."""

from app.core.exceptions import AuthenticationError, NotFoundError
from app.core.ldap import LDAPAuthError, LDAPService
from app.core.security import (
    create_access_token,
    create_refresh_token,
    get_refresh_token_expires_at,
)
from app.models import User
from app.repositories.refresh_token import RefreshTokenRepository
from app.repositories.user import UserRepository


class AuthService:
    """Service for authentication operations."""

    def __init__(
        self,
        user_repo: UserRepository,
        refresh_token_repo: RefreshTokenRepository,
        ldap_service: LDAPService,
    ):
        self.user_repo = user_repo
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
        # Authenticate against LDAP
        try:
            ldap_user = self.ldap_service.authenticate(username, password)
        except LDAPAuthError as e:
            raise AuthenticationError(str(e))

        # Sync user to local database (create or update)
        user = self._sync_user(ldap_user["login"], ldap_user["email"])

        # Create tokens
        access_token = create_access_token(
            user_id=user.id,
            login=user.login,
            projects=ldap_user["projects"],
        )
        refresh_token = create_refresh_token()

        # Store refresh token
        self.refresh_token_repo.create(
            token=refresh_token,
            user_id=user.id,
            expires_at=get_refresh_token_expires_at(),
        )

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "user": {
                "id": user.id,
                "login": user.login,
                "email": user.email,
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
        # Validate refresh token
        token_record = self.refresh_token_repo.get_by_token(refresh_token)
        if not token_record:
            raise AuthenticationError("Invalid or expired refresh token")

        # Get user
        user = self.user_repo.get_by_id(token_record.user_id)
        if not user:
            raise NotFoundError("User", token_record.user_id)

        # Create new access token
        # Note: In production, you might want to re-fetch projects from LDAP
        access_token = create_access_token(
            user_id=user.id,
            login=user.login,
            projects=[],  # Projects will be empty on refresh; frontend should re-login periodically
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
            user_id: The user's database ID

        Returns:
            Number of sessions logged out
        """
        return self.refresh_token_repo.revoke_all_for_user(user_id)

    def _sync_user(self, login: str, email: str) -> User:
        """Sync user from LDAP to local database.

        Creates user if not exists, updates email if changed.

        Args:
            login: The user's login name
            email: The user's email address

        Returns:
            The User record
        """
        user = self.user_repo.get_by_login(login)

        if user:
            # Update email if changed
            if user.email != email:
                user.email = email
                self.user_repo.session.add(user)
                self.user_repo.session.commit()
                self.user_repo.session.refresh(user)
            return user

        # Create new user
        return self.user_repo.create(login=login, email=email)
