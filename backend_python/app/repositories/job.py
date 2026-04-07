"""Job repository for job-related database operations."""

from math import ceil

from sqlmodel import Session, func, or_, select

from app.models import DataSet, Job
from app.repositories.base import BaseRepository


class JobRepository(BaseRepository[Job]):
    """Repository for Job model operations."""

    def __init__(self, session: Session):
        super().__init__(session, Job)

    def get_all_paginated(
        self,
        page: int,
        per: int,
        status: str | None = None,
        user: str | None = None,
        dataset_name: str | None = None,
    ) -> tuple[list[Job], int, int]:
        """Get all jobs paginated.

        Args:
            page: Page number (1-indexed)
            per: Items per page
            status: Optional status filter
            user: Optional user filter
            dataset_name: Optional dataset name filter (partial match)

        Returns:
            Tuple of (jobs, total_count, total_pages)
        """
        filter_conditions = []
        needs_dataset_join = bool(dataset_name)

        if status:
            filter_conditions.append(Job.status == status)
        if user:
            filter_conditions.append(Job.user == user)
        if dataset_name:
            filter_conditions.append(DataSet.name.icontains(dataset_name))

        # Count query
        count_statement = select(func.count()).select_from(Job)
        if needs_dataset_join:
            count_statement = count_statement.join(
                DataSet, Job.next_dataset_id == DataSet.id, isouter=True
            )
        if filter_conditions:
            count_statement = count_statement.where(*filter_conditions)
        total_count = self.session.exec(count_statement).one()
        total_pages = max(1, ceil(total_count / per))

        # Paginated data query
        statement = select(Job).order_by(Job.created_at.desc())
        if needs_dataset_join:
            statement = statement.join(
                DataSet, Job.next_dataset_id == DataSet.id, isouter=True
            )
        if filter_conditions:
            statement = statement.where(*filter_conditions)
        statement = statement.offset((page - 1) * per).limit(per)
        jobs = list(self.session.exec(statement).all())

        return jobs, total_count, total_pages

    def get_by_project_paginated(
        self,
        dataset_ids: list[int],
        page: int,
        per: int,
        status: str | None = None,
        user: str | None = None,
        search: str | None = None,
    ) -> tuple[list[Job], int, int]:
        """Get paginated jobs for datasets.

        Args:
            dataset_ids: List of dataset IDs belonging to the project
            page: Page number (1-indexed)
            per: Items per page
            status: Optional status filter
            user: Optional user filter
            search: Optional search query for dataset name

        Returns:
            Tuple of (jobs, total_count, total_pages)
        """
        if not dataset_ids:
            return [], 0, 1

        # Jobs belong to project if their input or output dataset is in this project
        filter_conditions = [
            or_(
                Job.next_dataset_id.in_(dataset_ids),
                Job.input_dataset_id.in_(dataset_ids),
            )
        ]

        if status:
            filter_conditions.append(Job.status == status)
        if user:
            filter_conditions.append(Job.user == user)
        if search:
            filter_conditions.append(DataSet.name.contains(search))

        # Count query
        count_statement = (
            select(func.count()).select_from(Job).where(*filter_conditions)
        )
        total_count = self.session.exec(count_statement).one()
        total_pages = max(1, ceil(total_count / per))

        # Paginated data query
        statement = (
            select(Job)
            .where(*filter_conditions)
            .order_by(Job.created_at.desc())
            .offset((page - 1) * per)
            .limit(per)
        )
        jobs = list(self.session.exec(statement).all())

        return jobs, total_count, total_pages
