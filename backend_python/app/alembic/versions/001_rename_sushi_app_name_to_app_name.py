"""rename sushi_app_name to app_name

Revision ID: 001
Revises: 
Create Date: 2026-06-01

"""
from typing import Sequence, Union
from alembic import op

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("datasets") as batch_op:
        batch_op.alter_column("sushi_app_name", new_column_name="app_name")


def downgrade() -> None:
    with op.batch_alter_table("datasets") as batch_op:
        batch_op.alter_column("app_name", new_column_name="sushi_app_name")
