"""SushiApplication repository for application-related database operations."""

import re

import yaml
from sqlmodel import Session, select

from app.models import SushiApplication
from app.repositories.base import BaseRepository


class SushiApplicationRepository(BaseRepository[SushiApplication]):
    """Repository for SushiApplication model operations."""

    def __init__(self, session: Session):
        super().__init__(session, SushiApplication)

    def get_all_applications(self) -> list[SushiApplication]:
        """Get all sushi applications."""
        statement = select(SushiApplication)
        return list(self.session.exec(statement).all())

    def parse_required_columns(self, required_columns: str | None) -> list:
        """Parse YAML-serialized required_columns field.

        The required_columns can be:
        - A simple list: ["Name", "Read1"]
        - A list with XOR options: [["Read1", "Read2"]] meaning one of them
        - A nested structure with AND/OR logic

        Args:
            required_columns: YAML string

        Returns:
            Parsed list structure
        """
        if not required_columns:
            return []

        try:
            return yaml.safe_load(required_columns) or []
        except yaml.YAMLError:
            return []

    def normalize_header(self, header: str) -> str:
        """Normalize header by removing bracket annotations.

        e.g., "Read1 [File]" -> "Read1"
        """
        return re.sub(r'\s*\[.*?\]\s*', '', header).strip()

    def check_required_columns_satisfied(
        self, required_columns: list, dataset_headers: set[str]
    ) -> bool:
        """Check if dataset headers satisfy required columns.

        Args:
            required_columns: Parsed required_columns list
            dataset_headers: Set of normalized dataset headers

        Returns:
            True if requirements are satisfied
        """
        if not required_columns:
            return True

        for requirement in required_columns:
            if isinstance(requirement, list):
                # XOR mode: at least one of these must be present
                if not any(col in dataset_headers for col in requirement):
                    return False
            else:
                # AND mode: this specific column must be present
                if requirement not in dataset_headers:
                    return False

        return True

    def get_runnable_apps_for_headers(
        self, headers: list[str]
    ) -> list[dict]:
        """Get applications that can run on a dataset with given headers.

        Args:
            headers: List of dataset headers

        Returns:
            List of dicts grouped by category:
            [{"category": "QC", "applications": ["FastqcApp", ...]}]
        """
        # Normalize headers
        normalized_headers = {self.normalize_header(h) for h in headers}

        apps = self.get_all_applications()
        matching_apps: dict[str, list[str]] = {}

        for app in apps:
            required = self.parse_required_columns(app.required_columns)

            if self.check_required_columns_satisfied(required, normalized_headers):
                category = app.analysis_category or "Other"
                if category not in matching_apps:
                    matching_apps[category] = []
                if app.class_name:
                    matching_apps[category].append(app.class_name)

        # Convert to list format
        result = []
        for category in sorted(matching_apps.keys()):
            result.append({
                "category": category,
                "applications": sorted(matching_apps[category]),
            })

        return result

    def get_runnable_apps_detailed(
        self, headers: list[str]
    ) -> list[dict]:
        """Get applications with full details for dataset show endpoint.

        Args:
            headers: List of dataset headers

        Returns:
            List of dicts grouped by category with app details:
            [{"category": "QC", "apps": [{"class_name": "...", "description": "..."}]}]
        """
        normalized_headers = {self.normalize_header(h) for h in headers}

        apps = self.get_all_applications()
        matching_apps: dict[str, list[dict]] = {}

        for app in apps:
            required = self.parse_required_columns(app.required_columns)

            if self.check_required_columns_satisfied(required, normalized_headers):
                category = app.analysis_category or "Other"
                if category not in matching_apps:
                    matching_apps[category] = []
                matching_apps[category].append({
                    "class_name": app.class_name,
                    "description": app.description,
                })

        # Convert to list format
        result = []
        for category in sorted(matching_apps.keys()):
            result.append({
                "category": category,
                "apps": sorted(matching_apps[category], key=lambda x: x["class_name"] or ""),
            })

        return result
