"""Add missing production columns and indexes to existing tables

Revision ID: 005
Revises: 004
Create Date: 2026-06-15

Adds columns that exist in production but were not in the Python models,
and all missing indexes. Column additions are guarded so the migration is
safe on both fresh Python installs and production-seeded databases.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy import Inspector, text

revision: str = "005"
down_revision: Union[str, None] = "004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _existing_columns(table: str) -> set[str]:
    conn = op.get_bind()
    inspector = Inspector.from_engine(conn)
    return {c["name"] for c in inspector.get_columns(table)}


def _existing_indexes(table: str) -> set[str]:
    conn = op.get_bind()
    inspector = Inspector.from_engine(conn)
    return {i["name"] for i in inspector.get_indexes(table)}


def upgrade() -> None:
    # ── data_sets: add columns missing from Python model ─────────────
    ds_cols = _existing_columns("data_sets")
    with op.batch_alter_table("data_sets") as batch_op:
        if "child" not in ds_cols:
            batch_op.add_column(sa.Column("child", sa.Boolean, nullable=False, server_default="0"))
        if "runnable_apps" not in ds_cols:
            batch_op.add_column(sa.Column("runnable_apps", sa.Text))
        if "refreshed_apps" not in ds_cols:
            batch_op.add_column(sa.Column("refreshed_apps", sa.Boolean))
        if "run_name_order_id" not in ds_cols:
            batch_op.add_column(sa.Column("run_name_order_id", sa.String))
        if "order_id" not in ds_cols:
            batch_op.add_column(sa.Column("order_id", sa.Integer))

    # ── projects: add data_set_tree ───────────────────────────────────
    proj_cols = _existing_columns("projects")
    with op.batch_alter_table("projects") as batch_op:
        if "data_set_tree" not in proj_cols:
            batch_op.add_column(sa.Column("data_set_tree", sa.Text))

    # ── users: add all missing production columns ─────────────────────
    user_cols = _existing_columns("users")
    with op.batch_alter_table("users") as batch_op:
        if "sign_in_count" not in user_cols:
            batch_op.add_column(sa.Column("sign_in_count", sa.Integer, server_default="0"))
        if "current_sign_in_at" not in user_cols:
            batch_op.add_column(sa.Column("current_sign_in_at", sa.DateTime))
        if "last_sign_in_at" not in user_cols:
            batch_op.add_column(sa.Column("last_sign_in_at", sa.DateTime))
        if "current_sign_in_ip" not in user_cols:
            batch_op.add_column(sa.Column("current_sign_in_ip", sa.String))
        if "last_sign_in_ip" not in user_cols:
            batch_op.add_column(sa.Column("last_sign_in_ip", sa.String))
        if "selected_project" not in user_cols:
            batch_op.add_column(sa.Column("selected_project", sa.Integer, server_default="-1"))
        if "remember_created_at" not in user_cols:
            batch_op.add_column(sa.Column("remember_created_at", sa.DateTime))
        if "created_at" not in user_cols:
            batch_op.add_column(sa.Column("created_at", sa.DateTime))
        if "updated_at" not in user_cols:
            batch_op.add_column(sa.Column("updated_at", sa.DateTime))
        if "encrypted_password" not in user_cols:
            batch_op.add_column(sa.Column("encrypted_password", sa.String))
        if "reset_password_token" not in user_cols:
            batch_op.add_column(sa.Column("reset_password_token", sa.String))
        if "reset_password_sent_at" not in user_cols:
            batch_op.add_column(sa.Column("reset_password_sent_at", sa.DateTime))
        if "provider" not in user_cols:
            batch_op.add_column(sa.Column("provider", sa.String))
        if "uid" not in user_cols:
            batch_op.add_column(sa.Column("uid", sa.String))
        if "otp_secret_key" not in user_cols:
            batch_op.add_column(sa.Column("otp_secret_key", sa.String))
        if "otp_required_for_login" not in user_cols:
            batch_op.add_column(sa.Column("otp_required_for_login", sa.Boolean, server_default="0"))
        if "otp_backup_codes" not in user_cols:
            batch_op.add_column(sa.Column("otp_backup_codes", sa.Text))

    # ── indexes ───────────────────────────────────────────────────────
    ds_idx = _existing_indexes("data_sets")
    if "index_data_sets_on_project_id" not in ds_idx:
        op.create_index("index_data_sets_on_project_id", "data_sets", ["project_id"])
    if "index_data_sets_on_parent_id" not in ds_idx:
        op.create_index("index_data_sets_on_parent_id", "data_sets", ["parent_id"])

    job_idx = _existing_indexes("jobs")
    if "index_jobs_on_input_dataset_id" not in job_idx:
        op.create_index("index_jobs_on_input_dataset_id", "jobs", ["input_dataset_id"])
    if "index_jobs_on_next_dataset_id" not in job_idx:
        op.create_index("index_jobs_on_next_dataset_id", "jobs", ["next_dataset_id"])
    if "index_jobs_on_next_dataset_id_and_id" not in job_idx:
        op.create_index("index_jobs_on_next_dataset_id_and_id", "jobs", ["next_dataset_id", "id"])

    sample_idx = _existing_indexes("samples")
    if "index_samples_on_data_set_id" not in sample_idx:
        op.create_index("index_samples_on_data_set_id", "samples", ["data_set_id"])

    proj_idx = _existing_indexes("projects")
    if "index_projects_on_number" not in proj_idx:
        op.create_index("index_projects_on_number", "projects", ["number"])


def downgrade() -> None:
    op.drop_index("index_projects_on_number", "projects")
    op.drop_index("index_samples_on_data_set_id", "samples")
    op.drop_index("index_jobs_on_next_dataset_id_and_id", "jobs")
    op.drop_index("index_jobs_on_next_dataset_id", "jobs")
    op.drop_index("index_jobs_on_input_dataset_id", "jobs")
    op.drop_index("index_data_sets_on_parent_id", "data_sets")
    op.drop_index("index_data_sets_on_project_id", "data_sets")

    with op.batch_alter_table("users") as batch_op:
        for col in ["sign_in_count", "current_sign_in_at", "last_sign_in_at",
                    "current_sign_in_ip", "last_sign_in_ip", "selected_project",
                    "remember_created_at", "created_at", "updated_at",
                    "encrypted_password", "reset_password_token", "reset_password_sent_at",
                    "provider", "uid", "otp_secret_key", "otp_required_for_login",
                    "otp_backup_codes"]:
            batch_op.drop_column(col)

    with op.batch_alter_table("projects") as batch_op:
        batch_op.drop_column("data_set_tree")

    with op.batch_alter_table("data_sets") as batch_op:
        for col in ["child", "runnable_apps", "refreshed_apps", "run_name_order_id", "order_id"]:
            batch_op.drop_column(col)
