from datetime import datetime, timezone

from sqlmodel import Field, SQLModel


class Project(SQLModel, table=True):
    """Maps to the existing projects table"""

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
    """Maps to the existing data_sets table."""

    __tablename__ = "datasets"

    id: int | None = Field(default=None, primary_key=True)
    project_id: int | None = None
    parent_id: int | None = None
    name: str | None = None
    md5: str | None = None
    created_at: datetime
    updated_at: datetime
    comment: str | None = None
    num_samples: int | None = None
    completed_samples: int | None = None
    user_id: int | None = None
    child: bool = False
    bfabric_id: int | None = None
    sushi_app_name: str | None = None
    order_id: int | None = None


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


class SushiApplication(SQLModel, table=True):
    """Maps to the existing sushi_applications table."""

    __tablename__ = "sushi_applications"

    id: int | None = Field(default=None, primary_key=True)
    class_name: str | None = None
    analysis_category: str | None = None
    required_columns: str | None = None  # YAML serialized
    next_dataset_keys: str | None = None  # YAML serialized
    created_at: datetime | None = None
    updated_at: datetime | None = None
    description: str | None = None
    employee: bool | None = None


class RefreshToken(SQLModel, table=True):
    """Stores refresh tokens for JWT authentication."""

    __tablename__ = "refresh_tokens"

    id: int | None = Field(default=None, primary_key=True)
    token_hash: str = Field(index=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    expires_at: datetime
    revoked: bool = Field(default=False)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
