"""Dataset import service for TSV file imports.

Handles importing datasets from TSV files (web upload or server-side path).
Writes to the new MultiOmicsStudio schema (datasets table, JSON key_value).
"""

import hashlib
from datetime import datetime, timezone
from typing import TYPE_CHECKING

from app.core.auth import require_project_access
from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.models import DataSet, Sample
from app.repositories.dataset import DatasetRepository
from app.repositories.project import ProjectRepository
from app.repositories.sample import SampleRepository
from app.repositories.user import UserRepository
from app.utils.sample_parser import serialize_sample_data
from app.utils.tsv_parser import ParsedDataset, parse_tsv

if TYPE_CHECKING:
    from app.api.deps import CurrentUser


class DatasetImportService:
    """Service for importing datasets from TSV files into the new schema."""

    def __init__(
        self,
        dataset_repo: DatasetRepository,
        sample_repo: SampleRepository,
        project_repo: ProjectRepository,
        user_repo: UserRepository,
    ):
        self.dataset_repo = dataset_repo
        self.sample_repo = sample_repo
        self.project_repo = project_repo
        self.user_repo = user_repo

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
        No auth check — intended for machine callers via /api/internal.
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
        """Import a dataset from TSV content for an authenticated user."""
        require_project_access(project_number, caller)
        db_user = self.user_repo.get_by_login(caller.login)
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
        """Perform the actual import. No auth check — callers must have already verified."""
        try:
            parsed = parse_tsv(content)
        except ValueError as e:
            raise ValidationError(f"Invalid TSV format: {e}")

        name = name_override or parsed.name
        if not name:
            raise ValidationError("Dataset name is required (Name field in TSV or name_override)")

        if not parsed.samples:
            raise ValidationError("Dataset must have at least one sample")

        if auto_create_project:
            project = self.project_repo.find_or_create(project_number)
        else:
            project = self.project_repo.get_by_number(project_number)
            if not project:
                raise NotFoundError("Project", project_number)

        md5 = hashlib.md5(content.encode("utf-8")).hexdigest()

        if not allow_duplicate:
            existing = self.dataset_repo.find_by_md5(project.id, md5)
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

        self.dataset_repo.persist(dataset)
        self._create_samples(dataset.id, parsed)
        self.dataset_repo.commit()

        return dataset

    def validate_tsv(self, content: str) -> ParsedDataset:
        """Validate TSV content without importing."""
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
        """Preview what would be imported without actually importing."""
        require_project_access(project_number, caller)
        parsed = self.validate_tsv(content)

        project = self.project_repo.get_by_number(project_number)
        if not project:
            raise NotFoundError("Project", project_number)

        md5 = hashlib.md5(content.encode("utf-8")).hexdigest()
        existing = self.dataset_repo.find_by_md5(project.id, md5)

        return {
            "name": parsed.name,
            "comment": parsed.comment,
            "order_ids": parsed.order_ids,
            "num_samples": len(parsed.samples),
            "columns": [{"name": c.name, "tag": c.tag} for c in parsed.columns],
            "file_columns": parsed.file_columns,
            "sample_preview": parsed.samples[:5],
            "md5": md5,
            "duplicate_exists": existing is not None,
            "duplicate_id": existing.id if existing else None,
            "duplicate_name": existing.name if existing else None,
        }

    def set_bfabric_id(self, dataset_id: int, bfabric_id: int) -> None:
        """Write the B-Fabric dataset ID back onto a SUSHI dataset.

        Called by btools after B-Fabric registration completes, via the internal API.
        """
        dataset = self.dataset_repo.get_by_id(dataset_id)
        if not dataset:
            raise NotFoundError("Dataset", dataset_id)
        self.dataset_repo.set_bfabric_id(dataset, bfabric_id)

    def _create_samples(self, dataset_id: int, parsed: ParsedDataset) -> None:
        now = datetime.now(timezone.utc)
        samples = []
        for sample_data in parsed.samples:
            key_value = {}
            for col in parsed.columns:
                key = f"{col.name} [{col.tag}]" if col.tag else col.name
                key_value[key] = sample_data.get(col.name, "")
            samples.append(Sample(
                data_set_id=dataset_id,
                key_value=serialize_sample_data(key_value),
                created_at=now,
                updated_at=now,
            ))
        self.sample_repo.bulk_persist(samples)
