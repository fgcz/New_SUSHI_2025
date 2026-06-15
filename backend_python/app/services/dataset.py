"""Dataset service for dataset-related business logic."""

from typing import TYPE_CHECKING

from app.core.auth import require_project_access
from app.core.config import settings
from app.core.exceptions import ForbiddenError, NotFoundError
from app.models import DataSet
from app.repositories.dataset import DatasetRepository
from app.repositories.sample import SampleRepository
from app.repositories.user import UserRepository
from app.utils.sample_parser import extract_data_paths, extract_headers, parse_sample_data
from omics_apps import get_runnable_apps

if TYPE_CHECKING:
    from app.api.deps import CurrentUser


class DatasetService:
    """Service for dataset operations."""

    def __init__(
        self,
        dataset_repo: DatasetRepository,
        user_repo: UserRepository,
        sample_repo: SampleRepository,
    ):
        self.dataset_repo = dataset_repo
        self.user_repo = user_repo
        self.sample_repo = sample_repo

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
        *,
        caller: "CurrentUser",
    ) -> dict:
        """Get paginated datasets for a project."""
        require_project_access(project_number, caller)
        # Clamp per to [1, 200]
        per = max(1, min(per, 200))

        # Get datasets from repository
        datasets, total_count, total_pages = self.dataset_repo.get_by_project_paginated(
            project_number, page, per, search
        )

        # Batch load users
        user_ids = {ds.user_id for ds in datasets if ds.user_id}
        users_map = {u.id: u.login for u in self.user_repo.get_by_ids(user_ids)}

        # Batch load children
        dataset_ids = [ds.id for ds in datasets]
        children_rows = self.dataset_repo.get_children_parent_rows(dataset_ids)
        children_map: dict[int, list[int]] = {ds_id: [] for ds_id in dataset_ids}
        for child_id, parent_id in children_rows:
            children_map[parent_id].append(child_id)

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
            users = self.user_repo.get_by_ids({dataset.user_id})
            user_login = users[0].login if users else None

        # Get project number
        project_number = self.dataset_repo.get_project_number(dataset)

        # Get children IDs
        children_ids = self.dataset_repo.get_children_ids(dataset.id)

        # Parse samples and derive headers/paths
        raw_samples = self.sample_repo.get_by_dataset_id(dataset.id)
        samples = [parse_sample_data(s.key_value) for s in raw_samples]
        headers = extract_headers(samples)
        data_paths = extract_data_paths(samples)

        # Get runnable applications
        applications = get_runnable_apps(headers)

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
            "order_ids": [int(x) for x in dataset.order_ids] if dataset.order_ids else [],
            "comment": dataset.comment,
            "sushi_app_name": dataset.sushi_app_name,
            "headers": headers,
            "samples": samples,
            "applications": applications,
            "data_paths": data_paths,
        }

    def get_tree(self, project_number: int, caller: "CurrentUser") -> dict:
        """Get datasets in tree structure for a project."""
        require_project_access(project_number, caller)
        rows = self.dataset_repo.get_tree_data_by_project(project_number)

        # Unpack tuples into a list of dicts
        datasets = [
            {"id": ds_id, "parent_id": parent_id, "name": name, "comment": comment}
            for ds_id, parent_id, name, comment in rows
        ]

        # Build lookup of existing dataset IDs
        dataset_ids = {ds["id"] for ds in datasets}

        # Batch load children counts
        count_rows = self.dataset_repo.count_children_per_parent(dataset_ids)
        children_counts = {parent_id: count for parent_id, count in count_rows}

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
        return self._build_tree_nodes(dataset)

    def _build_tree_nodes(self, dataset: DataSet) -> list[dict]:
        """Build jstree-compatible node list for a dataset and its full lineage."""
        nodes = []

        for ancestor in self.dataset_repo.get_ancestors(dataset):
            node = {"id": ancestor.id, "name": ancestor.name,
                    "parent": "#" if ancestor.parent_id is None else ancestor.parent_id}
            if ancestor.comment:
                node["comment"] = ancestor.comment
            nodes.append(node)

        node = {"id": dataset.id, "name": dataset.name,
                "parent": "#" if dataset.parent_id is None else dataset.parent_id}
        if dataset.comment:
            node["comment"] = dataset.comment
        nodes.append(node)

        for desc in self.dataset_repo.get_all_descendants(dataset.id):
            node = {"id": desc.id, "name": desc.name, "parent": desc.parent_id}
            if desc.comment:
                node["comment"] = desc.comment
            nodes.append(node)

        return nodes

    def get_suggested_name(self, dataset_id: int, app_name: str, user: "CurrentUser") -> dict:
        """Return the suggested output dataset name for a given app."""
        dataset = self._get_authorized_dataset(dataset_id, user)
        order_ids = [int(x) for x in dataset.order_ids] if dataset.order_ids else []
        if order_ids:
            prefix = '_'.join(f'o{oid}' for oid in order_ids)
            suggested = f"{prefix}_{app_name}"
        else:
            suggested = app_name
        return {"suggested_name": suggested}

    def get_runnable_apps(self, dataset_id: int, user: "CurrentUser") -> list[dict]:
        """Get runnable applications for a dataset."""
        dataset = self._get_authorized_dataset(dataset_id, user)

        raw_samples = self.sample_repo.get_by_dataset_id(dataset.id)
        samples = [parse_sample_data(s.key_value) for s in raw_samples]
        return get_runnable_apps(extract_headers(samples))

    def set_bfabric_id(self, dataset_id: int, bfabric_id: int, user: "CurrentUser") -> dict:
        """Set the B-Fabric ID for a dataset."""
        dataset = self._get_authorized_dataset(dataset_id, user)
        self.dataset_repo.set_bfabric_id(dataset, bfabric_id)
        return {"dataset_id": dataset_id, "bfabric_id": bfabric_id}

    def get_samples(self, dataset_id: int, user: "CurrentUser") -> list[dict]:
        """Get all samples for a dataset."""
        dataset = self._get_authorized_dataset(dataset_id, user)
        raw_samples = self.sample_repo.get_by_dataset_id(dataset.id)
        return [parse_sample_data(s.key_value) for s in raw_samples]

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
            "order_ids": [int(x) for x in ds.order_ids] if ds.order_ids else [],
            "project_number": project_number,
            "comment": ds.comment,
        }
