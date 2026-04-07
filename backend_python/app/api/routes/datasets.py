"""Dataset routes - thin handlers delegating to services."""

from fastapi import APIRouter

from app.api.deps import CurrentUserDep, DatasetRepoDep, DatasetServiceDep

router = APIRouter()


@router.get("/")
def get_datasets(
    current_user: CurrentUserDep,
    repo: DatasetRepoDep,
    limit: int = 100,
    offset: int = 0,
) -> list:
    """Get all datasets with pagination.

    Note: Returns all datasets. Consider filtering by user's projects in production.
    """
    return repo.get_all(limit, offset)


@router.get("/{dataset_id}")
def get_dataset(
    dataset_id: int,
    current_user: CurrentUserDep,
    service: DatasetServiceDep,
) -> dict:
    """Get a single dataset by ID."""
    return service.get_by_id(dataset_id)
