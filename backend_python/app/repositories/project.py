"""Project repository for project-related database operations."""

from sqlmodel import Session, select

from app.models import DataSet, Project
from app.repositories.base import BaseRepository


class ProjectRepository(BaseRepository[Project]):
    """Repository for Project model operations."""

    def __init__(self, session: Session):
        super().__init__(session, Project)

    def get_dataset_ids_by_number(self, project_number: int) -> list[int]:
        """Get all dataset IDs belonging to a project by project number."""
        statement = (
            select(DataSet.id)
            .join(Project, DataSet.project_id == Project.id)
            .where(Project.number == project_number)
        )
        return list(self.session.exec(statement).all())
