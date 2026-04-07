"""Dataset repository for dataset-related database operations."""

from math import ceil

from sqlmodel import Session, func, select

from app.models import DataSet, Project
from app.repositories.base import BaseRepository


class DatasetRepository(BaseRepository[DataSet]):
    """Repository for DataSet model operations."""

    def __init__(self, session: Session):
        super().__init__(session, DataSet)

    def get_by_project_paginated(
        self,
        project_number: int,
        page: int,
        per: int,
        search: str = "",
    ) -> tuple[list[DataSet], int, int]:
        """Get paginated datasets for a project.

        Returns:
            Tuple of (datasets, total_count, total_pages)
        """
        # Build base filter conditions
        base_conditions = [Project.number == project_number]
        if search:
            base_conditions.append(DataSet.name.contains(search))

        # Count query
        count_statement = (
            select(func.count())
            .select_from(DataSet)
            .join(Project, DataSet.project_id == Project.id)
            .where(*base_conditions)
        )
        total_count = self.session.exec(count_statement).one()
        total_pages = max(1, ceil(total_count / per))

        # Paginated data query
        statement = (
            select(DataSet)
            .join(Project, DataSet.project_id == Project.id)
            .where(*base_conditions)
            .order_by(DataSet.created_at.desc())
            .offset((page - 1) * per)
            .limit(per)
        )
        datasets = list(self.session.exec(statement).all())

        return datasets, total_count, total_pages

    def get_children_map(self, dataset_ids: list[int]) -> dict[int, list[int]]:
        """Get a mapping of parent dataset IDs to their children IDs."""
        if not dataset_ids:
            return {}

        children_map: dict[int, list[int]] = {ds_id: [] for ds_id in dataset_ids}
        children_rows = self.session.exec(
            select(DataSet.id, DataSet.parent_id).where(
                DataSet.parent_id.in_(dataset_ids)
            )
        ).all()

        for child_id, parent_id in children_rows:
            children_map[parent_id].append(child_id)

        return children_map

    def get_children_counts(self, dataset_ids: set[int]) -> dict[int, int]:
        """Get count of children for each dataset ID."""
        if not dataset_ids:
            return {}

        children_counts: dict[int, int] = {ds_id: 0 for ds_id in dataset_ids}
        children_rows = self.session.exec(
            select(DataSet.parent_id, func.count(DataSet.id))
            .where(DataSet.parent_id.in_(dataset_ids))
            .group_by(DataSet.parent_id)
        ).all()

        for parent_id, count in children_rows:
            children_counts[parent_id] = count

        return children_counts

    def get_tree_data_by_project(
        self, project_number: int
    ) -> list[tuple[int, int | None, str | None, str | None]]:
        """Get raw tree data for a project.

        Returns:
            List of tuples (id, parent_id, name, comment)
        """
        statement = (
            select(DataSet.id, DataSet.parent_id, DataSet.name, DataSet.comment)
            .join(Project, DataSet.project_id == Project.id)
            .where(Project.number == project_number)
        )
        return list(self.session.exec(statement).all())

    def get_names_by_ids(self, dataset_ids: set[int]) -> dict[int, str]:
        """Get a mapping of dataset IDs to names."""
        if not dataset_ids:
            return {}
        rows = self.session.exec(
            select(DataSet.id, DataSet.name).where(DataSet.id.in_(dataset_ids))
        ).all()
        return {ds_id: name for ds_id, name in rows}
