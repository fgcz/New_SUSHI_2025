"""drop sushi_applications table

Revision ID: 002
Revises: 001
Create Date: 2026-06-02

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_table("sushi_applications")


def downgrade() -> None:
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
