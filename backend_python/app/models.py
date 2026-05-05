from datetime import datetime, timezone
from typing import Any

from sqlalchemy import Column, JSON
from sqlmodel import Field, SQLModel


class Project(SQLModel, table=True):
    """Maps to the existing projects table."""

    __tablename__ = "projects"

    id: int | None = Field(default=None, primary_key=True)
    number: int
    created_at: datetime | None = None
    updated_at: datetime | None = None


class User(SQLModel, table=True):
    """Maps to the existing users table."""

    __tablename__ = "users"

    id: int | None = Field(default=None, primary_key=True)
    login: str
    email: str


class DataSet(SQLModel, table=True):
    """Maps to the existing datasets table.

    Note: Some database columns are intentionally not mapped:
    - runnable_apps, refreshed_apps: We compute on demand instead of caching
    - child: Derived from (parent_id is not None)
    - order_id (singular): Use order_ids[0] via primary_order_id property
    """

    __tablename__ = "datasets"

    id: int | None = Field(default=None, primary_key=True)

    # Relationships
    project_id: int | None = Field(default=None, foreign_key="projects.id")
    parent_id: int | None = Field(default=None, foreign_key="datasets.id")
    user_id: int | None = Field(default=None, foreign_key="users.id")

    # Core fields
    name: str | None = None
    md5: str | None = None
    comment: str | None = None

    # Sample tracking
    num_samples: int | None = Field(default=0)
    completed_samples: int | None = Field(default=0)

    # App that created this dataset (null if imported directly)
    sushi_app_name: str | None = None

    # Job parameters used when app created this dataset (JSON)
    job_parameters: dict[str, Any] | None = Field(
        default=None, sa_column=Column(JSON)
    )

    # B-Fabric integration
    bfabric_id: int | None = None
    workunit_id: int | None = None
    order_ids: list[int] | None = Field(default=None, sa_column=Column(JSON))

    # Timestamps
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )

    @property
    def is_child(self) -> bool:
        """Whether this dataset was created by an app (has parent)."""
        return self.parent_id is not None

    @property
    def primary_order_id(self) -> int | None:
        """Get first order ID for B-Fabric registration."""
        if self.order_ids and len(self.order_ids) > 0:
            return self.order_ids[0]
        return None


class Job(SQLModel, table=True):
    """Maps to the existing jobs table."""

    __tablename__ = "jobs"

    id: int | None = Field(default=None, primary_key=True)
    submit_job_id: int | None = None
    input_dataset_id: int | None = None
    next_dataset_id: int | None = None
    created_at: datetime
    updated_at: datetime
    script_path: str | None = None
    stdout_path: str | None = None
    stderr_path: str | None = None
    submit_command: str | None = None
    status: str | None = None
    user: str | None = None
    start_time: datetime | None = None
    end_time: datetime | None = None


class Sample(SQLModel, table=True):
    """Maps to the existing samples table."""

    __tablename__ = "samples"

    id: int | None = Field(default=None, primary_key=True)
    key_value: str | None = None  # Serialized Ruby hash string
    data_set_id: int | None = Field(default=None, foreign_key="datasets.id")
    created_at: datetime | None = None
    updated_at: datetime | None = None


class RefreshToken(SQLModel, table=True):
    """Stores refresh tokens for JWT authentication."""

    __tablename__ = "refresh_tokens"

    id: int | None = Field(default=None, primary_key=True)
    token_hash: str = Field(index=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    expires_at: datetime
    revoked: bool = Field(default=False)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
