"""Project repository for project-related database operations."""

from datetime import datetime, timezone

from sqlmodel import Session, select

from app.models import DataSet, Project
from app.repositories.base import BaseRepository


class ProjectRepository(BaseRepository[Project]):
    """Repository for Project model operations."""

    def __init__(self, session: Session):
        super().__init__(session, Project)

    def get_by_number(self, number: int) -> Project | None:
        """Get a project by its project number."""
        return self.session.exec(select(Project).where(Project.number == number)).first()

    def find_or_create(self, number: int) -> Project:
        """Return existing project or stage a new one. Does not commit."""
        project = self.get_by_number(number)
        if not project:
            now = datetime.now(timezone.utc)
            project = Project(number=number, created_at=now, updated_at=now)
            self.session.add(project)
            self.session.flush()
        return project

    def get_dataset_ids_by_number(self, project_number: int) -> list[int]:
        """Get all dataset IDs belonging to a project by project number."""
        statement = (
            select(DataSet.id)
            .join(Project, DataSet.project_id == Project.id)
            .where(Project.number == project_number)
        )
        return list(self.session.exec(statement).all())
