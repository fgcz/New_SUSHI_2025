from fastapi import APIRouter
from sqlmodel import select

from app.api.deps import SessionDep
from app.models import DataSet

router = APIRouter()


@router.get("/")
def get_datasets(session: SessionDep, limit: int = 100, offset: int = 0) -> list[DataSet]:
    """Return all datasets.
    /api/datasets/?limit=10"""
    statement = select(DataSet).offset(offset).limit(limit)
    return list(session.exec(statement).all())


@router.get("/{dataset_id}")
def get_dataset(session: SessionDep, dataset_id: int) -> DataSet | None:
    """Return a single dataset by ID."""
    return session.get(DataSet, dataset_id)
