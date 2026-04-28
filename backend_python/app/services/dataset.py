"""Dataset service for dataset-related business logic."""

from typing import TYPE_CHECKING

from app.core.config import settings
from app.core.exceptions import ForbiddenError, NotFoundError
from app.models import DataSet
from app.repositories.dataset import DatasetRepository
from app.repositories.sample import SampleRepository
from app.repositories.sushi_application import SushiApplicationRepository
from app.repositories.user import UserRepository

if TYPE_CHECKING:
    from app.api.deps import CurrentUser


class DatasetService:
    """Service for dataset operations."""

    def __init__(
        self,
        dataset_repo: DatasetRepository,
        user_repo: UserRepository,
        sample_repo: SampleRepository,
        sushi_app_repo: SushiApplicationRepository,
    ):
        self.dataset_repo = dataset_repo
        self.user_repo = user_repo
        self.sample_repo = sample_repo
        self.sushi_app_repo = sushi_app_repo

    def _get_authorized_dataset(self, dataset_id: int, user: "CurrentUser") -> DataSet:
        """Fetch dataset and verify project access.

        Raises: NotFoundError, ForbiddenError
        """
        dataset = self.dataset_repo.get_by_id(dataset_id)
        if not dataset:
            raise NotFoundError("Dataset", dataset_id)

        if settings.SKIP_AUTH:
            return dataset

        project_number = self.dataset_repo.get_project_number(dataset)

        # Future: Employee bypass
        # if hasattr(user, 'is_employee') and user.is_employee:
        #     return dataset

        if project_number is None or project_number not in user.projects:
            raise ForbiddenError(f"No access to dataset {dataset.id}")

        return dataset

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
                self._serialize_dataset_list(ds, project_number, users_map, children_map)
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

    def get_by_id(self, dataset_id: int, user: "CurrentUser") -> dict:
        """Get full dataset details by ID including samples and applications."""
        dataset = self._get_authorized_dataset(dataset_id, user)

        # Get user login
        user_login = None
        if dataset.user_id:
            users_map = self.user_repo.get_logins_by_ids({dataset.user_id})
            user_login = users_map.get(dataset.user_id)

        # Get project number
        project_number = self.dataset_repo.get_project_number(dataset)

        # Get children IDs
        children_ids = self.dataset_repo.get_children_ids(dataset.id)

        # Get samples
        samples = self.sample_repo.get_samples_as_dicts(dataset.id)

        # Get headers
        headers = self.sample_repo.get_headers(dataset.id)

        # Get runnable applications with full details
        applications = self.sushi_app_repo.get_runnable_apps_detailed(headers)

        # Get data folder paths from sample file paths
        data_paths = self.sample_repo.get_data_paths(dataset.id)

        return {
            "id": dataset.id,
            "name": dataset.name,
            "created_at": dataset.created_at.isoformat() if dataset.created_at else None,
            "user": user_login,
            "project_number": project_number,
            "samples_count": dataset.num_samples or len(samples),
            "completed_samples": dataset.completed_samples,
            "parent_id": dataset.parent_id,
            "children_ids": children_ids,
            "bfabric_id": dataset.bfabric_id,
            "order_id": dataset.order_id,
            "comment": dataset.comment,
            "sushi_app_name": dataset.sushi_app_name,
            "headers": headers,
            "samples": samples,
            "applications": applications,
            "data_paths": data_paths,
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

            node = {
                "id": ds_id,
                "name": ds["name"],
                "parent": parent,
                "children_count": children_counts.get(ds_id, 0),
            }
            if ds["comment"]:
                node["comment"] = ds["comment"]
            tree_nodes.append(node)

        # Sort by id descending
        tree_nodes.sort(key=lambda node: -node["id"])

        return {"tree": tree_nodes, "project_number": project_number}

    def get_tree_for_dataset(self, dataset_id: int, user: "CurrentUser") -> list[dict]:
        """Get tree structure for a specific dataset (ancestors + self + descendants)."""
        dataset = self._get_authorized_dataset(dataset_id, user)
        return self.dataset_repo.get_tree_for_dataset(dataset)

    def get_runnable_apps(self, dataset_id: int, user: "CurrentUser") -> list[dict]:
        """Get runnable applications for a dataset."""
        dataset = self._get_authorized_dataset(dataset_id, user)

        # Get headers from samples
        headers = self.sample_repo.get_headers(dataset.id)

        # Get matching applications
        return self.sushi_app_repo.get_runnable_apps_for_headers(headers)

    def get_samples(self, dataset_id: int, user: "CurrentUser") -> list[dict]:
        """Get all samples for a dataset."""
        dataset = self._get_authorized_dataset(dataset_id, user)
        return self.sample_repo.get_samples_as_dicts(dataset.id)

    def _serialize_dataset_list(
        self,
        ds: DataSet,
        project_number: int,
        users_map: dict[int, str],
        children_map: dict[int, list[int]],
    ) -> dict:
        """Serialize a dataset for list view."""
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
