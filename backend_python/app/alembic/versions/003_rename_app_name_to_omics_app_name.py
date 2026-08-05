"""rename app_name to omics_app_name in datasets

Revision ID: 003
Revises: 002
Create Date: 2026-06-03
"""

from alembic import op

revision = "003"
down_revision = "002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("datasets") as batch_op:
        batch_op.alter_column("app_name", new_column_name="omics_app_name")


def downgrade() -> None:
    with op.batch_alter_table("datasets") as batch_op:
        batch_op.alter_column("omics_app_name", new_column_name="app_name")
