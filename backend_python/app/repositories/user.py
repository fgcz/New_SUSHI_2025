"""User repository for user-related database operations."""

from sqlmodel import Session, select

from app.models import User
from app.repositories.base import BaseRepository


class UserRepository(BaseRepository[User]):
    """Repository for User model operations."""

    def __init__(self, session: Session):
        super().__init__(session, User)

    def get_by_ids(self, ids: set[int]) -> list[User]:
        """Get users by a set of IDs."""
        if not ids:
            return []
        return list(self.session.exec(select(User).where(User.id.in_(ids))).all())

    def get_by_login(self, login: str) -> User | None:
        """Get a user by their login name."""
        statement = select(User).where(User.login == login)
        return self.session.exec(statement).first()

    def create(self, login: str, email: str) -> User:
        """Create a new user.

        Args:
            login: The user's login name
            email: The user's email address

        Returns:
            The created User record
        """
        user = User(login=login, email=email)
        self.session.add(user)
        self.session.commit()
        self.session.refresh(user)
        return user
