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

    def create(self, entity: T) -> T:
        """Create a new record."""
        self.session.add(entity)
        self.session.commit()
        self.session.refresh(entity)
        return entity

    def update(self, entity: T) -> T:
        """Update an existing record."""
        self.session.add(entity)
        self.session.commit()
        self.session.refresh(entity)
        return entity

    def delete(self, entity: T) -> None:
        """Delete a record."""
        self.session.delete(entity)
        self.session.commit()

    def persist(self, entity: T) -> T:
        """Stage entity for write and flush to DB, but do not commit.

        Use instead of create() when multiple writes must succeed or fail
        together. The caller is responsible for calling commit() once all
        related entities have been persisted.
        """
        self.session.add(entity)
        self.session.flush()
        self.session.refresh(entity)
        return entity

    def commit(self) -> None:
        """Commit the current unit of work."""
        self.session.commit()
