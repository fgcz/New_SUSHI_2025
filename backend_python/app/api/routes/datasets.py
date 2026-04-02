from fastapi import APIRouter
from sqlmodel import select

from app.api.deps import SessionDep
from app.models import DataSet

router = APIRouter()


@router.get("/")
def get_datasets(
    session: SessionDep, limit: int = 100, offset: int = 0
) -> list[DataSet]:
    """Return all datasets.
    /api/datasets/?limit=10"""
    statement = select(DataSet).offset(offset).limit(limit)
    return list(session.exec(statement).all())


@router.get("/{dataset_id}")
def get_dataset(session: SessionDep, dataset_id: int) -> object:
    """Return a single dataset by ID."""
    # id: number;
    # name: string;
    # created_at: string;
    # user_login?: string | null;
    # project_number: number;
    # samples_count?: number;
    # completed_samples?: number;
    # parent_id?: number | null;
    # children_ids?: number[];
    # bfabric_id?: number | null;
    # order_id?: number | null;
    # comment?: string;
    # sushi_app_name?: string;
    # samples: DatasetSample[];
    # applications: DatasetAppCategory[];
    res = session.get(DataSet, dataset_id)
    res["samples"] = []
    return res
