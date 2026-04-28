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
    return service.get_by_id(dataset_id, current_user)


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
    tree_nodes = service.get_tree_for_dataset(dataset_id, current_user)
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
    return service.get_runnable_apps(dataset_id, current_user)


@router.get("/{dataset_id}/samples")
def get_dataset_samples(
    dataset_id: int,
    current_user: CurrentUserDep,
    service: DatasetServiceDep,
) -> list[dict]:
    """Get all samples for a dataset.

    Returns array of sample objects with their key-value data.
    """
    return service.get_samples(dataset_id, current_user)


# --------------------------------------------------------------------------
# Dataset Actions (mock implementations)
# --------------------------------------------------------------------------


@router.post("/{dataset_id}/comment")
def add_comment(
    dataset_id: int,
    comment: str,
    current_user: CurrentUserDep,
) -> dict:
    """Add a comment to a dataset."""
    # TODO: Implement actual comment storage
    return {"success": True, "dataset_id": dataset_id, "comment": comment}


@router.patch("/{dataset_id}/name")
def rename_dataset(
    dataset_id: int,
    new_name: str,
    current_user: CurrentUserDep,
) -> dict:
    """Rename a dataset."""
    # TODO: Implement actual rename
    return {"success": True, "dataset_id": dataset_id, "new_name": new_name}


@router.get("/{dataset_id}/download")
def download_dataset(
    dataset_id: int,
    current_user: CurrentUserDep,
) -> dict:
    """Get download URL/info for a dataset."""
    # TODO: Implement actual download logic
    return {
        "success": True,
        "dataset_id": dataset_id,
        "download_url": f"/files/datasets/{dataset_id}/archive.zip",
    }


@router.get("/{dataset_id}/scripts-path")
def get_scripts_path(
    dataset_id: int,
    current_user: CurrentUserDep,
) -> dict:
    """Get the path to job scripts for this dataset."""
    # TODO: Implement actual path lookup
    return {"path": f"p1001/dataset_{dataset_id}/scripts"}


@router.post("/{dataset_id}/merge")
def merge_dataset(
    dataset_id: int,
    target_dataset_id: int,
    current_user: CurrentUserDep,
) -> dict:
    """Merge this dataset with another dataset."""
    # TODO: Implement actual merge logic
    return {
        "success": True,
        "source_dataset_id": dataset_id,
        "target_dataset_id": target_dataset_id,
    }


@router.get("/{dataset_id}/parameters")
def get_dataset_parameters(
    dataset_id: int,
    current_user: CurrentUserDep,
) -> dict:
    """Get the parameters used to create this dataset."""
    # TODO: Implement actual parameter retrieval from job/sushi_app
    return {
        "cores": "8",
        "ram": "32",
        "scratch": "100",
        "partition": "normal",
        "ref": "hg38",
        "paired": "true",
        "strandMode": "sense",
        "featureLevel": "gene",
        "transcriptTypes": "protein_coding,lncRNA",
        "minReads": "10",
        "normMethod": "TMM",
        "runGO": "true",
        "backgroundExpression": "5",
    }


@router.post("/{dataset_id}/update-size")
def update_dataset_size(
    dataset_id: int,
    current_user: CurrentUserDep,
) -> dict:
    """Recalculate and update the dataset size."""
    # TODO: Implement actual size calculation
    return {"success": True, "dataset_id": dataset_id, "size_bytes": 1024000}


@router.patch("/{dataset_id}/bfabric-id")
def set_bfabric_id(
    dataset_id: int,
    bfabric_id: str,
    current_user: CurrentUserDep,
) -> dict:
    """Set the B-Fabric ID for a dataset."""
    # TODO: Implement actual bfabric_id update
    return {"success": True, "dataset_id": dataset_id, "bfabric_id": bfabric_id}


@router.post("/{dataset_id}/announce")
def announce_dataset(
    dataset_id: int,
    current_user: CurrentUserDep,
) -> dict:
    """Announce a dataset (send notifications)."""
    # TODO: Implement actual announcement logic
    return {"success": True, "dataset_id": dataset_id, "announced": True}


@router.delete("/{dataset_id}")
def delete_dataset(
    dataset_id: int,
    current_user: CurrentUserDep,
) -> dict:
    """Delete a dataset."""
    # TODO: Implement actual deletion
    return {"success": True, "dataset_id": dataset_id, "deleted": True}


@router.get("/{dataset_id}/resubmit-data")
def get_resubmit_data(
    dataset_id: int,
    current_user: CurrentUserDep,
) -> dict:
    """Get data needed to resubmit/re-run the application that created this dataset."""
    # TODO: Implement actual resubmit data retrieval from job history
    return {
        "app_name": "CountQC",
        "parameters": {
            "cores": 16,
            "ram": 64,
            "scratch": 200,
            "partition": "high",
            "ref": "mm10",
            "paired": False,
            "strandMode": "antisense",
            "featureLevel": "transcript",
            "transcriptTypes": "protein_coding",
            "minReads": 25,
            "normMethod": "RLE",
            "runGO": False,
            "backgroundExpression": 10,
        },
    }
