"""Revert rebranding: restore production table/column names and sushi_applications

Revision ID: 004
Revises: 003
Create Date: 2026-06-15

Undoes migrations 001-003. Aligns the Python schema back to production:
  - Renames omics_app_name -> sushi_app_name in datasets
  - Renames table datasets -> data_sets
  - Restores sushi_applications table (dropped in 002)
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "004"
down_revision: Union[str, None] = "003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Rename column omics_app_name -> sushi_app_name
    with op.batch_alter_table("datasets") as batch_op:
        batch_op.alter_column("omics_app_name", new_column_name="sushi_app_name")

    # 2. Rename table datasets -> data_sets
    op.rename_table("datasets", "data_sets")

    # 3. Restore sushi_applications (dropped in migration 002)
    op.create_table(
        "sushi_applications",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True, nullable=False),
        sa.Column("class_name", sa.String),
        sa.Column("analysis_category", sa.String),
        sa.Column("required_columns", sa.Text),
        sa.Column("next_dataset_keys", sa.Text),
        sa.Column("created_at", sa.DateTime, nullable=False),
        sa.Column("updated_at", sa.DateTime, nullable=False),
        sa.Column("description", sa.Text),
        sa.Column("employee", sa.Boolean),
    )


def downgrade() -> None:
    op.drop_table("sushi_applications")
    op.rename_table("data_sets", "datasets")
    with op.batch_alter_table("datasets") as batch_op:
        batch_op.alter_column("sushi_app_name", new_column_name="omics_app_name")
