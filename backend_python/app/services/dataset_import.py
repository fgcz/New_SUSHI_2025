"""Dataset import service for TSV file imports.

Handles importing datasets from TSV files (web upload or server-side path).
"""

import hashlib
from datetime import datetime, timezone
from typing import TYPE_CHECKING

from sqlmodel import Session

from app.core.auth import require_project_access
from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.models import DataSet, Project, Sample, User
from app.utils.sample_parser import serialize_sample_data
from app.utils.tsv_parser import ParsedDataset, parse_tsv

if TYPE_CHECKING:
    from app.api.deps import CurrentUser


class DatasetImportService:
    """Service for importing datasets from TSV files."""

    def __init__(self, session: Session):
        self.session = session

    def import_from_path(
        self,
        path: str,
        project_number: int,
        *,
        name_override: str | None = None,
        parent_id: int | None = None,
    ) -> DataSet:
        """Import a dataset by reading a TSV file from the server filesystem.

        The project is auto-created if it does not exist.
        """
        try:
            with open(path, encoding="utf-8") as f:
                content = f.read()
        except OSError as e:
            raise ValidationError(f"Cannot read dataset file: {e}")

        return self._do_import(
            content=content,
            project_number=project_number,
            user_id=None,
            parent_id=parent_id,
            name_override=name_override,
            auto_create_project=True,
        )

    def import_from_tsv(
        self,
        content: str,
        project_number: int,
        caller: "CurrentUser",
        *,
        parent_id: int | None = None,
        allow_duplicate: bool = True,
        name_override: str | None = None,
    ) -> DataSet:
        """Import a dataset from TSV content for an authenticated user.

        Raises:
            ForbiddenError: If caller does not have access to the project
            ValidationError: If TSV is invalid
            NotFoundError: If project doesn't exist
            ConflictError: If duplicate dataset exists (and allow_duplicate=False)
        """
        require_project_access(project_number, caller)
        db_user = self.session.query(User).filter(User.login == caller.login).first()
        user_id = db_user.id if db_user else None
        return self._do_import(
            content=content,
            project_number=project_number,
            user_id=user_id,
            parent_id=parent_id,
            allow_duplicate=allow_duplicate,
            name_override=name_override,
        )

    def _do_import(
        self,
        content: str,
        project_number: int,
        user_id: int | None,
        *,
        parent_id: int | None = None,
        allow_duplicate: bool = True,
        name_override: str | None = None,
        auto_create_project: bool = False,
    ) -> DataSet:
        """Perform the actual import with no authentication check.

        Called by import_from_tsv (after auth) and import_from_path (server-side, no user).
        """
        try:
            parsed = parse_tsv(content)
        except ValueError as e:
            raise ValidationError(f"Invalid TSV format: {e}")

        name = name_override or parsed.name
        if not name:
            raise ValidationError("Dataset name is required (Name field in TSV or name_override)")

        if not parsed.samples:
            raise ValidationError("Dataset must have at least one sample")

        project = self._get_project(project_number, auto_create=auto_create_project)
        md5 = self._compute_md5(content)

        if not allow_duplicate:
            existing = self._find_duplicate(project.id, md5)
            if existing:
                raise ConflictError(
                    f"Duplicate dataset exists: '{existing.name}' (ID: {existing.id})"
                )

        dataset = DataSet(
            project_id=project.id,
            parent_id=parent_id,
            user_id=user_id,
            name=name,
            comment=parsed.comment,
            md5=md5,
            order_ids=parsed.order_ids if parsed.order_ids else None,
            num_samples=len(parsed.samples),
            completed_samples=0,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        )

        self.session.add(dataset)
        self.session.flush()
        self._create_samples(dataset.id, parsed)
        self.session.commit()

        return dataset

    def validate_tsv(self, content: str) -> ParsedDataset:
        """Validate TSV content without importing.

        Args:
            content: TSV file content

        Returns:
            ParsedDataset with validation results

        Raises:
            ValidationError: If TSV is invalid
        """
        try:
            parsed = parse_tsv(content)
        except ValueError as e:
            raise ValidationError(f"Invalid TSV format: {e}")

        errors = []

        if not parsed.name:
            errors.append("Dataset name is required (Name field in TSV)")

        if not parsed.samples:
            errors.append("Dataset must have at least one sample")

        if not parsed.columns:
            errors.append("No columns defined in header row")

        if errors:
            raise ValidationError("; ".join(errors))

        return parsed

    def preview_import(
        self,
        content: str,
        project_number: int,
        caller: "CurrentUser",
    ) -> dict:
        """Preview what would be imported without actually importing.

        Args:
            content: TSV file content
            project_number: Target project

        Returns:
            Dict with preview information
        """
        require_project_access(project_number, caller)
        parsed = self.validate_tsv(content)
        project = self._get_project(project_number)
        md5 = self._compute_md5(content)

        # Check for existing duplicate
        existing = self._find_duplicate(project.id, md5)

        return {
            "name": parsed.name,
            "comment": parsed.comment,
            "order_ids": parsed.order_ids,
            "num_samples": len(parsed.samples),
            "columns": [
                {"name": c.name, "tag": c.tag} for c in parsed.columns
            ],
            "file_columns": parsed.file_columns,
            "sample_preview": parsed.samples[:5],  # First 5 samples
            "md5": md5,
            "duplicate_exists": existing is not None,
            "duplicate_id": existing.id if existing else None,
            "duplicate_name": existing.name if existing else None,
        }

    def _get_project(self, project_number: int, *, auto_create: bool = False) -> Project:
        """Get project by number, optionally creating it if absent."""
        project = (
            self.session.query(Project)
            .filter(Project.number == project_number)
            .first()
        )
        if not project:
            if auto_create:
                now = datetime.now(timezone.utc)
                project = Project(number=project_number, created_at=now, updated_at=now)
                self.session.add(project)
                self.session.flush()
            else:
                raise NotFoundError("Project", project_number)
        return project

    def _compute_md5(self, content: str) -> str:
        """Compute MD5 hash of content."""
        return hashlib.md5(content.encode("utf-8")).hexdigest()

    def _find_duplicate(self, project_id: int, md5: str) -> DataSet | None:
        """Find existing dataset with same MD5 in project."""
        return (
            self.session.query(DataSet)
            .filter(DataSet.project_id == project_id, DataSet.md5 == md5)
            .first()
        )

    def _create_samples(self, dataset_id: int, parsed: ParsedDataset) -> None:
        """Create sample records from parsed data."""
        now = datetime.now(timezone.utc)

        for sample_data in parsed.samples:
            # Build key_value dict with column tags preserved in keys
            key_value = {}
            for col in parsed.columns:
                value = sample_data.get(col.name, "")
                # Include tag in key name for [File], [Link], [Factor], [B-Fabric]
                if col.tag:
                    key = f"{col.name} [{col.tag}]"
                else:
                    key = col.name
                key_value[key] = value

            sample = Sample(
                data_set_id=dataset_id,
                key_value=serialize_sample_data(key_value),
                created_at=now,
                updated_at=now,
            )
            self.session.add(sample)
