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

    def get_children_parent_rows(self, parent_ids: list[int]) -> list[tuple[int, int]]:
        """Get (child_id, parent_id) pairs for the given parent IDs."""
        if not parent_ids:
            return []
        return list(self.session.exec(
            select(DataSet.id, DataSet.parent_id).where(DataSet.parent_id.in_(parent_ids))
        ).all())

    def count_children_per_parent(self, parent_ids: set[int]) -> list[tuple[int, int]]:
        """Get (parent_id, count) pairs for the given parent IDs."""
        if not parent_ids:
            return []
        return list(self.session.exec(
            select(DataSet.parent_id, func.count(DataSet.id))
            .where(DataSet.parent_id.in_(parent_ids))
            .group_by(DataSet.parent_id)
        ).all())

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

    def get_id_name_pairs(self, dataset_ids: set[int]) -> list[tuple[int, str]]:
        """Get (id, name) pairs for the given dataset IDs."""
        if not dataset_ids:
            return []
        return list(self.session.exec(
            select(DataSet.id, DataSet.name).where(DataSet.id.in_(dataset_ids))
        ).all())

    def get_children_ids(self, dataset_id: int) -> list[int]:
        """Get direct children IDs for a dataset."""
        statement = select(DataSet.id).where(DataSet.parent_id == dataset_id)
        return list(self.session.exec(statement).all())

    def get_all_descendants(self, dataset_id: int) -> list[DataSet]:
        """Get all descendants of a dataset (recursive)."""
        descendants = []
        to_process = [dataset_id]

        while to_process:
            current_id = to_process.pop(0)
            children = self.session.exec(
                select(DataSet).where(DataSet.parent_id == current_id)
            ).all()
            for child in children:
                descendants.append(child)
                to_process.append(child.id)

        return descendants

    def get_ancestors(self, dataset: DataSet) -> list[DataSet]:
        """Get all ancestors of a dataset (parent chain to root)."""
        ancestors = []
        current = dataset

        while current.parent_id is not None:
            parent = self.get_by_id(current.parent_id)
            if parent is None:
                break
            ancestors.append(parent)
            current = parent

        # Return in order from root to immediate parent
        return list(reversed(ancestors))

    def set_bfabric_id(self, dataset: DataSet, bfabric_id: int) -> DataSet:
        """Set the B-Fabric ID on a dataset."""
        dataset.bfabric_id = bfabric_id
        self.session.add(dataset)
        self.session.commit()
        self.session.refresh(dataset)
        return dataset

    def find_by_md5(self, project_id: int, md5: str) -> DataSet | None:
        """Find an existing dataset with the same MD5 hash in a project."""
        return self.session.exec(
            select(DataSet).where(DataSet.project_id == project_id, DataSet.md5 == md5)
        ).first()

    def get_project_number(self, dataset: DataSet) -> int | None:
        """Get the project number for a dataset."""
        if dataset.project_id is None:
            return None
        project = self.session.exec(
            select(Project).where(Project.id == dataset.project_id)
        ).first()
        return project.number if project else None
