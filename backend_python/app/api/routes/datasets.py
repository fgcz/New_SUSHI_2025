"""Dataset routes - thin handlers delegating to services."""

from fastapi import APIRouter

from app.api.deps import CurrentUserDep, DatasetServiceDep

router = APIRouter()


@router.get("/")
def get_datasets_list(
    current_user: CurrentUserDep,
    service: DatasetServiceDep,
) -> dict:
    """Get list of user's datasets.

    Note: Currently returns summary for all datasets accessible to user.
    """
    # TODO: Filter by user's projects when project membership is implemented
    return {
        "datasets": [],
        "total_count": 0,
        "current_user": current_user.login,
    }


@router.get("/{dataset_id}")
def get_dataset(
    dataset_id: int,
    current_user: CurrentUserDep,
    service: DatasetServiceDep,
) -> dict:
    """Get full dataset details by ID.

    Returns dataset with samples, headers, and runnable applications.
    """
    return service.get_by_id(dataset_id)


@router.get("/{dataset_id}/tree")
def get_dataset_tree(
    dataset_id: int,
    current_user: CurrentUserDep,
    service: DatasetServiceDep,
) -> dict:
    """Get tree structure for a dataset.

    Returns ancestors, the dataset itself, and all descendants
    in jstree-compatible format.
    """
    tree_nodes = service.get_tree_for_dataset(dataset_id)
    return {"tree": tree_nodes}


@router.get("/{dataset_id}/runnable_apps")
def get_dataset_runnable_apps(
    dataset_id: int,
    current_user: CurrentUserDep,
    service: DatasetServiceDep,
) -> list[dict]:
    """Get runnable applications for a dataset.

    Returns applications grouped by category that can process
    this dataset based on its headers.
    """
    return service.get_runnable_apps(dataset_id)


@router.get("/{dataset_id}/samples")
def get_dataset_samples(
    dataset_id: int,
    current_user: CurrentUserDep,
    service: DatasetServiceDep,
) -> list[dict]:
    """Get all samples for a dataset.

    Returns array of sample objects with their key-value data.
    """
    return service.get_samples(dataset_id)
