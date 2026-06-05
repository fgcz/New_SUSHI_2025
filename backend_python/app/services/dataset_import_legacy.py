"""Legacy dataset import service for the Ruby SUSHI MySQL schema.

Writes to data_sets / samples tables using Ruby Hash#inspect key_value format.
Used during the transition period while the Ruby SUSHI production database is
still the authoritative store. Accessed via POST /api/internal/legacy/datasets/register.

This service intentionally uses raw SQL because the SQLAlchemy models map to
the new schema (datasets table), not the Ruby schema (data_sets table).
"""

from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import text
from sqlmodel import Session

from app.core.exceptions import ValidationError
from app.utils.sample_parser import serialize_sample_data_ruby
from app.utils.tsv_parser import parse_tsv


@dataclass
class LegacyImportResult:
    """Minimal result from a legacy import — only the ID is reliably available."""
    id: int
    name: str


class LegacyDatasetImportService:
    """Dataset import for the legacy Ruby SUSHI MySQL schema.

    Replicates what btools _sushi_db_insert_dataset does via direct MySQL CLI,
    but through SQLAlchemy so the API is the sole database gateway.
    """

    def __init__(self, session: Session):
        self.session = session

    def import_from_path(
        self,
        path: str,
        project_number: int,
        *,
        name_override: str | None = None,
        parent_id: int | None = None,
    ) -> LegacyImportResult:
        """Import a dataset from a server-side TSV path into the Ruby SUSHI schema."""
        try:
            with open(path, encoding="utf-8") as f:
                content = f.read()
        except OSError as e:
            raise ValidationError(f"Cannot read dataset file: {e}")

        return self._do_import(
            content=content,
            project_number=project_number,
            name_override=name_override,
            parent_id=parent_id,
        )

    def _do_import(
        self,
        content: str,
        project_number: int,
        *,
        name_override: str | None = None,
        parent_id: int | None = None,
    ) -> LegacyImportResult:
        try:
            parsed = parse_tsv(content)
        except ValueError as e:
            raise ValidationError(f"Invalid TSV format: {e}")

        name = name_override or parsed.name
        if not name:
            raise ValidationError("Dataset name is required")
        if not parsed.samples:
            raise ValidationError("Dataset must have at least one sample")

        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

        project_id = self._resolve_project_id(project_number, parent_id, now)
        dataset_id = self._insert_dataset(project_id, parent_id, name, now)
        self._insert_samples(dataset_id, parsed, now)
        self._update_num_samples(dataset_id, len(parsed.samples))

        self.session.commit()
        return LegacyImportResult(id=dataset_id, name=name)

    def _resolve_project_id(
        self, project_number: int, parent_id: int | None, now: str
    ) -> int:
        """Resolve project_id, inheriting from parent when parent_id is given.

        Replicates the Ruby SUSHI tree nesting rule: a child dataset must share
        its parent's project_id so make_whole_tree nests it correctly.
        """
        if parent_id is not None:
            row = self.session.execute(
                text("SELECT project_id FROM data_sets WHERE id = :pid"),
                {"pid": parent_id},
            ).fetchone()
            if row and row[0]:
                return row[0]

        # Fall back to project number lookup / creation
        row = self.session.execute(
            text("SELECT id FROM projects WHERE number = :num"),
            {"num": project_number},
        ).fetchone()
        if row:
            return row[0]

        result = self.session.execute(
            text("INSERT INTO projects (number, created_at, updated_at) VALUES (:num, :now, :now)"),
            {"num": project_number, "now": now},
        )
        return result.lastrowid

    def _insert_dataset(
        self, project_id: int, parent_id: int | None, name: str, now: str
    ) -> int:
        result = self.session.execute(
            text(
                "INSERT INTO data_sets (project_id, parent_id, name, child, created_at, updated_at)"
                " VALUES (:project_id, :parent_id, :name, 0, :now, :now)"
            ),
            {
                "project_id": project_id,
                "parent_id": parent_id,
                "name": name,
                "now": now,
            },
        )
        return result.lastrowid

    def _insert_samples(self, dataset_id: int, parsed, now: str) -> None:
        for sample_data in parsed.samples:
            key_value = {}
            for col in parsed.columns:
                key = f"{col.name} [{col.tag}]" if col.tag else col.name
                key_value[key] = sample_data.get(col.name, "")

            self.session.execute(
                text(
                    "INSERT INTO samples (data_set_id, key_value, created_at, updated_at)"
                    " VALUES (:ds_id, :kv, :now, :now)"
                ),
                {
                    "ds_id": dataset_id,
                    "kv": serialize_sample_data_ruby(key_value),
                    "now": now,
                },
            )

    def set_bfabric_id(self, dataset_id: int, bfabric_id: int) -> None:
        """Write the B-Fabric dataset ID back onto a legacy SUSHI dataset.

        Called by btools after B-Fabric registration completes, via the internal API.
        Replicates _sushi_db_set_bfabric_id from btools register_custom_analysis.py.
        """
        self.session.execute(
            text("UPDATE data_sets SET bfabric_id = :bfid WHERE id = :id"),
            {"bfid": bfabric_id, "id": dataset_id},
        )
        self.session.commit()

    def _update_num_samples(self, dataset_id: int, count: int) -> None:
        self.session.execute(
            text("UPDATE data_sets SET num_samples = :count WHERE id = :id"),
            {"count": count, "id": dataset_id},
        )
