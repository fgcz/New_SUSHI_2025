"""Add notification_settings and notifications tables

Revision ID: 006
Revises: 005
Create Date: 2026-06-15

Adds the two notification tables from the production schema.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "006"
down_revision: Union[str, None] = "005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "notification_settings",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("notification_enabled", sa.Boolean),
        sa.Column("last_notification_date", sa.DateTime),
        sa.Column("last_error_date", sa.DateTime),
        sa.Column("last_warning_date", sa.DateTime),
        sa.Column("created_at", sa.DateTime, nullable=False),
        sa.Column("updated_at", sa.DateTime, nullable=False),
    )
    op.create_index("index_notification_settings_on_user_id", "notification_settings", ["user_id"])

    op.create_table(
        "notifications",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("message", sa.Text),
        sa.Column("notification_type", sa.String),
        sa.Column("read", sa.Boolean),
        sa.Column("created_at", sa.DateTime, nullable=False),
        sa.Column("updated_at", sa.DateTime, nullable=False),
    )
    op.create_index("index_notifications_on_user_id", "notifications", ["user_id"])


def downgrade() -> None:
    op.drop_index("index_notifications_on_user_id", "notifications")
    op.drop_table("notifications")
    op.drop_index("index_notification_settings_on_user_id", "notification_settings")
    op.drop_table("notification_settings")
