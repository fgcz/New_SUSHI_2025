"""Dataset service for dataset-related business logic."""

from app.core.exceptions import NotFoundError
from app.models import DataSet
from app.repositories.dataset import DatasetRepository
from app.repositories.user import UserRepository


class DatasetService:
    """Service for dataset operations."""

    def __init__(self, dataset_repo: DatasetRepository, user_repo: UserRepository):
        self.dataset_repo = dataset_repo
        self.user_repo = user_repo

    def get_paginated(
        self,
        project_number: int,
        page: int,
        per: int,
        search: str = "",
    ) -> dict:
        """Get paginated datasets for a project."""
        # Clamp per to [1, 200]
        per = max(1, min(per, 200))

        # Get datasets from repository
        datasets, total_count, total_pages = self.dataset_repo.get_by_project_paginated(
            project_number, page, per, search
        )

        # Batch load users
        user_ids = {ds.user_id for ds in datasets if ds.user_id}
        users_map = self.user_repo.get_logins_by_ids(user_ids)

        # Batch load children
        dataset_ids = [ds.id for ds in datasets]
        children_map = self.dataset_repo.get_children_map(dataset_ids)

        return {
            "datasets": [
                self._serialize_dataset(ds, project_number, users_map, children_map)
                for ds in datasets
            ],
            "pagination": {
                "total_count": total_count,
                "page": page,
                "per": per,
                "total_pages": total_pages,
            },
            "filters": {
                "q": search,
            },
            "project_number": project_number,
        }

    def get_by_id(self, dataset_id: int) -> dict:
        """Get a single dataset by ID."""
        dataset = self.dataset_repo.get_by_id(dataset_id)
        if not dataset:
            raise NotFoundError("Dataset", dataset_id)

        return {
            "id": dataset.id,
            "name": dataset.name,
            "created_at": dataset.created_at.isoformat() if dataset.created_at else None,
            "comment": dataset.comment,
            "num_samples": dataset.num_samples,
            "completed_samples": dataset.completed_samples,
            "parent_id": dataset.parent_id,
            "bfabric_id": dataset.bfabric_id,
            "order_id": dataset.order_id,
            "sushi_app_name": dataset.sushi_app_name,
            "samples": [],
        }

    def get_tree(self, project_number: int) -> dict:
        """Get datasets in tree structure for a project."""
        rows = self.dataset_repo.get_tree_data_by_project(project_number)

        # Unpack tuples into a list of dicts
        datasets = [
            {"id": ds_id, "parent_id": parent_id, "name": name, "comment": comment}
            for ds_id, parent_id, name, comment in rows
        ]

        # Build lookup of existing dataset IDs
        dataset_ids = {ds["id"] for ds in datasets}

        # Batch load children counts
        children_counts = self.dataset_repo.get_children_counts(dataset_ids)

        # Build tree nodes
        tree_nodes = []
        for ds in datasets:
            ds_id = ds["id"]
            parent_id = ds["parent_id"]
            # Use "#" for root nodes (no parent or parent not in this project)
            parent = parent_id if parent_id and parent_id in dataset_ids else "#"

            tree_nodes.append({
                "id": ds_id,
                "name": ds["name"],
                "comment": ds["comment"],
                "parent": parent,
                "children_count": children_counts.get(ds_id, 0),
            })

        # Sort by id descending
        tree_nodes.sort(key=lambda node: -node["id"])

        return {"tree": tree_nodes, "project_number": project_number}

    def _serialize_dataset(
        self,
        ds: DataSet,
        project_number: int,
        users_map: dict[int, str],
        children_map: dict[int, list[int]],
    ) -> dict:
        """Serialize a dataset to a dictionary."""
        return {
            "id": ds.id,
            "name": ds.name,
            "sushi_app_name": ds.sushi_app_name,
            "completed_samples": ds.completed_samples,
            "samples_length": ds.num_samples,
            "parent_id": ds.parent_id,
            "children_ids": children_map.get(ds.id, []),
            "user_login": users_map.get(ds.user_id) if ds.user_id else None,
            "created_at": ds.created_at.isoformat() if ds.created_at else None,
            "bfabric_id": ds.bfabric_id,
            "order_id": ds.order_id,
            "project_number": project_number,
            "comment": ds.comment,
        }
