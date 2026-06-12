"""Legacy dataset import service for the Ruby SUSHI MySQL schema.

Writes to data_sets / samples tables using Ruby Hash#inspect key_value format.
Used during the transition period while the Ruby SUSHI production database is
still the authoritative store. Accessed via POST /api/internal/legacy/datasets/register.

This service intentionally uses raw SQL because the SQLAlchemy models map to
the new schema (datasets table), not the Ruby schema (data_sets table).
"""

import logging
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import text
from sqlmodel import Session

from app.core.exceptions import ValidationError
from app.utils.sample_parser import serialize_sample_data_ruby
from app.utils.tsv_parser import parse_tsv

logger = logging.getLogger(__name__)


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
        user: str | None = None,
    ) -> LegacyImportResult:
        """Import a dataset from a server-side TSV path into the Ruby SUSHI schema."""
        logger.info("Legacy import started: path=%s project=%s user=%s parent_id=%s",
                    path, project_number, user, parent_id)
        try:
            with open(path, encoding="utf-8") as f:
                content = f.read()
        except OSError as e:
            logger.error("Cannot read dataset file: path=%s error=%s", path, e)
            raise ValidationError(f"Cannot read dataset file: {e}")

        return self._do_import(
            content=content,
            project_number=project_number,
            name_override=name_override,
            parent_id=parent_id,
            user=user,
        )

    def _do_import(
        self,
        content: str,
        project_number: int,
        *,
        name_override: str | None = None,
        parent_id: int | None = None,
        user: str | None = None,
    ) -> LegacyImportResult:
        try:
            parsed = parse_tsv(content)
        except ValueError as e:
            logger.error("TSV parse error: %s", e)
            raise ValidationError(f"Invalid TSV format: {e}")

        name = name_override or parsed.name
        if not name:
            raise ValidationError("Dataset name is required")
        if not parsed.samples:
            raise ValidationError("Dataset must have at least one sample")

        # Use system local time — the MariaDB server on h-082 stores timestamps
        # in Europe/Zurich local time, not UTC.
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        user_id = self._resolve_user_id(user)
        project_id = self._resolve_project_id(project_number, parent_id, now)
        dataset_id = self._insert_dataset(project_id, parent_id, name, user_id, now)
        self._insert_samples(dataset_id, parsed, now)
        self._update_num_samples(dataset_id, len(parsed.samples))

        self.session.commit()
        logger.info("Legacy import complete: dataset_id=%s name=%r project_id=%s user_id=%s samples=%d",
                    dataset_id, name, project_id, user_id, len(parsed.samples))
        return LegacyImportResult(id=dataset_id, name=name)

    def _resolve_user_id(self, user: str | None) -> int | None:
        if not user:
            logger.warning("No user login provided — dataset will be inserted without user_id")
            return None

        row = self.session.execute(
            text("SELECT id FROM users WHERE login = :login"),
            {"login": user},
        ).fetchone()

        if not row:
            logger.warning("User login %r not found in legacy users table — "
                           "dataset will be inserted without user_id. "
                           "Check that the login matches exactly what is stored in SUSHI.", user)
            return None

        logger.info("Resolved user: login=%r user_id=%s", user, row[0])
        return row[0]

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
                logger.debug("Inherited project_id=%s from parent dataset %s", row[0], parent_id)
                return row[0]

        row = self.session.execute(
            text("SELECT id FROM projects WHERE number = :num"),
            {"num": project_number},
        ).fetchone()
        if row:
            logger.debug("Resolved project_id=%s for project number %s", row[0], project_number)
            return row[0]

        result = self.session.execute(
            text("INSERT INTO projects (number, created_at, updated_at) VALUES (:num, :now, :now)"),
            {"num": project_number, "now": now},
        )
        logger.info("Created new project record: number=%s project_id=%s", project_number, result.lastrowid)
        return result.lastrowid

    def _insert_dataset(
        self, project_id: int, parent_id: int | None, name: str, user_id: int | None, now: str
    ) -> int:
        result = self.session.execute(
            text(
                "INSERT INTO data_sets (project_id, parent_id, name, child, user_id, created_at, updated_at)"
                " VALUES (:project_id, :parent_id, :name, 0, :user_id, :now, :now)"
            ),
            {
                "project_id": project_id,
                "parent_id": parent_id,
                "name": name,
                "user_id": user_id,
                "now": now,
            },
        )
        logger.debug("Inserted dataset row: id=%s name=%r user_id=%s", result.lastrowid, name, user_id)
        return result.lastrowid

    def _insert_samples(self, dataset_id: int, parsed, now: str) -> None:
        for i, sample_data in enumerate(parsed.samples):
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
        logger.debug("Inserted %d sample rows for dataset_id=%s", len(parsed.samples), dataset_id)

    def set_bfabric_id(self, dataset_id: int, bfabric_id: int) -> None:
        """Write the B-Fabric dataset ID back onto a legacy SUSHI dataset.

        Called by btools after B-Fabric registration completes, via the internal API.
        Replicates _sushi_db_set_bfabric_id from btools register_custom_analysis.py.
        """
        logger.info("Setting bfabric_id=%s on dataset_id=%s", bfabric_id, dataset_id)
        self.session.execute(
            text("UPDATE data_sets SET bfabric_id = :bfid WHERE id = :id"),
            {"bfid": bfabric_id, "id": dataset_id},
        )
        self.session.commit()
        logger.info("bfabric_id set: dataset_id=%s bfabric_id=%s", dataset_id, bfabric_id)

    def _update_num_samples(self, dataset_id: int, count: int) -> None:
        self.session.execute(
            text("UPDATE data_sets SET num_samples = :count WHERE id = :id"),
            {"count": count, "id": dataset_id},
        )
