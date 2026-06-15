import json
from datetime import datetime, timezone
from typing import Any

import yaml
from sqlalchemy import Column, String
from sqlalchemy.types import TypeDecorator
from sqlmodel import Field, SQLModel


class RubySerializedJSON(TypeDecorator):
    """Handles columns that may contain JSON or Ruby YAML serialization."""

    impl = String
    cache_ok = True

    def process_result_value(self, value: Any, dialect: Any) -> Any:
        if value is None or value == "":
            return None
        try:
            return json.loads(value)
        except (json.JSONDecodeError, TypeError):
            try:
                return yaml.safe_load(value)
            except Exception:
                return None


class Project(SQLModel, table=True):
    """Maps to the production projects table."""

    __tablename__ = "projects"

    id: int | None = Field(default=None, primary_key=True)
    number: int = Field(index=True)
    data_set_tree: str | None = Field(default=None, sa_column=Column(String))
    created_at: datetime | None = None
    updated_at: datetime | None = None


class User(SQLModel, table=True):
    """Maps to the production users table.

    Devise/OTP columns are managed exclusively by the Rails app.
    The Python backend reads login/email and uses LDAP for auth.
    """

    __tablename__ = "users"

    id: int | None = Field(default=None, primary_key=True)
    login: str = Field(index=True)
    email: str | None = Field(default=None, index=True)

    # Devise session tracking (managed by Rails)
    sign_in_count: int | None = Field(default=0)
    current_sign_in_at: datetime | None = None
    last_sign_in_at: datetime | None = None
    current_sign_in_ip: str | None = None
    last_sign_in_ip: str | None = None
    remember_created_at: datetime | None = None
    selected_project: int | None = Field(default=-1)
    created_at: datetime | None = None
    updated_at: datetime | None = None

    # Devise password / OAuth / OTP (managed by Rails, never written by Python)
    encrypted_password: str | None = None
    reset_password_token: str | None = None
    reset_password_sent_at: datetime | None = None
    provider: str | None = None
    uid: str | None = None
    otp_secret_key: str | None = None
    otp_required_for_login: bool | None = Field(default=False)
    otp_backup_codes: str | None = None


class DataSet(SQLModel, table=True):
    """Maps to the production data_sets table."""

    __tablename__ = "data_sets"

    id: int | None = Field(default=None, primary_key=True)

    # Relationships
    project_id: int | None = Field(default=None, foreign_key="projects.id", index=True)
    parent_id: int | None = Field(default=None, foreign_key="data_sets.id", index=True)
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

    # Production columns managed by Rails
    child: bool = Field(default=False)
    runnable_apps: str | None = None
    refreshed_apps: bool | None = None
    run_name_order_id: str | None = None
    order_id: int | None = Field(default=None, index=True)

    # Job parameters used when app created this dataset (JSON or Ruby YAML)
    job_parameters: dict[str, Any] | None = Field(
        default=None, sa_column=Column(RubySerializedJSON)
    )

    # B-Fabric integration
    bfabric_id: int | None = None
    workunit_id: int | None = None
    order_ids: list[int] | None = Field(default=None, sa_column=Column(RubySerializedJSON))

    # Timestamps
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )

    @property
    def is_child(self) -> bool:
        return self.parent_id is not None

    @property
    def primary_order_id(self) -> int | None:
        if self.order_ids and len(self.order_ids) > 0:
            return self.order_ids[0]
        return None


class SushiApplication(SQLModel, table=True):
    """Maps to the production sushi_applications table."""

    __tablename__ = "sushi_applications"

    id: int | None = Field(default=None, primary_key=True)
    class_name: str | None = None
    analysis_category: str | None = None
    required_columns: str | None = None
    next_dataset_keys: str | None = None
    description: str | None = None
    employee: bool | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


class Job(SQLModel, table=True):
    """Maps to the production jobs table."""

    __tablename__ = "jobs"

    id: int | None = Field(default=None, primary_key=True)
    submit_job_id: int | None = None
    input_dataset_id: int | None = Field(default=None, index=True)
    next_dataset_id: int | None = Field(default=None, index=True)
    created_at: datetime
    updated_at: datetime
    script_path: str | None = None
    stdout_path: str | None = None
    stderr_path: str | None = None
    submit_command: str | None = None
    status: str | None = Field(default=None, index=True)
    user: str | None = None
    start_time: datetime | None = None
    end_time: datetime | None = None


class Sample(SQLModel, table=True):
    """Maps to the production samples table."""

    __tablename__ = "samples"

    id: int | None = Field(default=None, primary_key=True)
    key_value: str | None = None  # Serialized Ruby hash string
    data_set_id: int | None = Field(default=None, foreign_key="data_sets.id", index=True)
    created_at: datetime | None = None
    updated_at: datetime | None = None


class NotificationSetting(SQLModel, table=True):
    """Maps to the production notification_settings table."""

    __tablename__ = "notification_settings"

    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    notification_enabled: bool | None = None
    last_notification_date: datetime | None = None
    last_error_date: datetime | None = None
    last_warning_date: datetime | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


class Notification(SQLModel, table=True):
    """Maps to the production notifications table."""

    __tablename__ = "notifications"

    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    message: str | None = None
    notification_type: str | None = None
    read: bool | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


class RefreshToken(SQLModel, table=True):
    """Stores refresh tokens for JWT authentication (Python backend only)."""

    __tablename__ = "refresh_tokens"

    id: int | None = Field(default=None, primary_key=True)
    token_hash: str = Field(index=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    expires_at: datetime
    revoked: bool = Field(default=False)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
