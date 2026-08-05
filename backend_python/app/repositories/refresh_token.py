"""Refresh token repository for token storage operations."""

import hashlib
from datetime import datetime, timezone

from sqlmodel import Session, select

from app.models import RefreshToken
from app.repositories.base import BaseRepository


class RefreshTokenRepository(BaseRepository[RefreshToken]):
    """Repository for RefreshToken model operations."""

    def __init__(self, session: Session):
        super().__init__(session, RefreshToken)

    @staticmethod
    def hash_token(token: str) -> str:
        """Hash a token for secure storage."""
        return hashlib.sha256(token.encode()).hexdigest()

    def create(self, token: str, user_id: int, expires_at: datetime) -> RefreshToken:
        """Create and store a new refresh token.

        Args:
            token: The raw refresh token string
            user_id: The user's database ID
            expires_at: When the token expires

        Returns:
            The created RefreshToken record
        """
        refresh_token = RefreshToken(
            token_hash=self.hash_token(token),
            user_id=user_id,
            expires_at=expires_at,
            revoked=False,
        )
        self.session.add(refresh_token)
        self.session.commit()
        self.session.refresh(refresh_token)
        return refresh_token

    def get_by_token(self, token: str) -> RefreshToken | None:
        """Find a refresh token by its raw value.

        Args:
            token: The raw refresh token string

        Returns:
            The RefreshToken record if found and valid, None otherwise
        """
        token_hash = self.hash_token(token)
        statement = select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.revoked == False,  # noqa: E712
            RefreshToken.expires_at > datetime.now(timezone.utc),
        )
        return self.session.exec(statement).first()

    def revoke(self, token: str) -> bool:
        """Revoke a refresh token.

        Args:
            token: The raw refresh token string

        Returns:
            True if token was found and revoked, False otherwise
        """
        token_hash = self.hash_token(token)
        statement = select(RefreshToken).where(RefreshToken.token_hash == token_hash)
        refresh_token = self.session.exec(statement).first()

        if refresh_token:
            refresh_token.revoked = True
            self.session.add(refresh_token)
            self.session.commit()
            return True
        return False

    def revoke_all_for_user(self, user_id: int) -> int:
        """Revoke all refresh tokens for a user.

        Args:
            user_id: The user's database ID

        Returns:
            Number of tokens revoked
        """
        statement = select(RefreshToken).where(
            RefreshToken.user_id == user_id,
            RefreshToken.revoked == False,  # noqa: E712
        )
        tokens = self.session.exec(statement).all()

        for token in tokens:
            token.revoked = True
            self.session.add(token)

        self.session.commit()
        return len(tokens)

    def cleanup_expired(self) -> int:
        """Delete expired and revoked tokens.

        Returns:
            Number of tokens deleted
        """
        statement = select(RefreshToken).where(
            (RefreshToken.expires_at < datetime.now(timezone.utc))
            | (RefreshToken.revoked == True)  # noqa: E712
        )
        tokens = self.session.exec(statement).all()

        for token in tokens:
            self.session.delete(token)

        self.session.commit()
        return len(tokens)
