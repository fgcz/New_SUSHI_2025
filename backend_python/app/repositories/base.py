"""Base repository with common database operations."""

from typing import Generic, TypeVar

from sqlmodel import Session, func, select

T = TypeVar("T")


class BaseRepository(Generic[T]):
    """Base repository providing common CRUD operations."""

    def __init__(self, session: Session, model: type[T]):
        self.session = session
        self.model = model

    def get_by_id(self, id: int) -> T | None:
        """Get a single record by ID."""
        return self.session.get(self.model, id)

    def get_all(self, limit: int = 100, offset: int = 0) -> list[T]:
        """Get all records with pagination."""
        statement = select(self.model).offset(offset).limit(limit)
        return list(self.session.exec(statement).all())

    def count(self, *conditions) -> int:
        """Count records matching conditions."""
        statement = select(func.count()).select_from(self.model)
        if conditions:
            statement = statement.where(*conditions)
        return self.session.exec(statement).one()
