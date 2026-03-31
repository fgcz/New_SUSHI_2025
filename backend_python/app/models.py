from datetime import datetime

from sqlmodel import Field, SQLModel


class DataSet(SQLModel, table=True):
    """Maps to the existing data_sets table from Ruby backend."""

    __tablename__ = "data_sets"

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
