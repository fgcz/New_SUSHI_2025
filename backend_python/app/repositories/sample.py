"""Sample repository for sample-related database operations."""

from sqlmodel import Session, select

from app.models import Sample
from app.repositories.base import BaseRepository


class SampleRepository(BaseRepository[Sample]):
    """Repository for Sample model operations."""

    def __init__(self, session: Session):
        super().__init__(session, Sample)

    def get_by_dataset_id(self, dataset_id: int) -> list[Sample]:
        """Get all samples for a dataset."""
        statement = select(Sample).where(Sample.data_set_id == dataset_id)
        return list(self.session.exec(statement).all())
