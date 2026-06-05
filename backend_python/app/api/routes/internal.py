"""Internal routes — machine API key required, no user context.

These routes are called by background services (job_manager, btools).
They are not reachable from the browser and do not use JWT authentication.

Routes:
  POST /internal/datasets/register         → new MultiOmicsStudio schema
  POST /internal/legacy/datasets/register  → legacy Ruby SUSHI schema (transition period)
"""

from fastapi import APIRouter
from pydantic import BaseModel

from app.api.deps import DatasetImportServiceDep, LegacyDatasetImportServiceDep, MachineCallerDep

router = APIRouter()


class RegisterDatasetRequest(BaseModel):
    path: str
    project_number: int
    name: str | None = None
    parent_id: int | None = None


class SetBFabricIdRequest(BaseModel):
    bfabric_id: int


@router.post("/datasets/register")
def register_dataset(
    body: RegisterDatasetRequest,
    caller: MachineCallerDep,
    service: DatasetImportServiceDep,
) -> dict:
    """Register a dataset from a server-side TSV path into the new schema.

    Called by btools targeting the MultiOmicsStudio production database.
    """
    dataset = service.import_from_path(
        path=body.path,
        project_number=body.project_number,
        name_override=body.name,
        parent_id=body.parent_id,
    )
    return {"message": "OK", "data_set_id": dataset.id}


@router.post("/legacy/datasets/register")
def register_dataset_legacy(
    body: RegisterDatasetRequest,
    caller: MachineCallerDep,
    service: LegacyDatasetImportServiceDep,
) -> dict:
    """Register a dataset from a server-side TSV path into the Ruby SUSHI schema.

    Called by btools targeting the legacy SUSHI production database during the
    transition period. Uses data_sets table and Ruby Hash#inspect key_value format.
    """
    result = service.import_from_path(
        path=body.path,
        project_number=body.project_number,
        name_override=body.name,
        parent_id=body.parent_id,
    )
    return {"message": "OK", "data_set_id": result.id}


@router.put("/datasets/{dataset_id}/bfabric-id")
def set_bfabric_id(
    dataset_id: int,
    body: SetBFabricIdRequest,
    caller: MachineCallerDep,
    service: DatasetImportServiceDep,
) -> dict:
    """Write B-Fabric dataset ID back onto a MultiOmicsStudio dataset.

    Called by btools after B-Fabric registration completes.
    """
    service.set_bfabric_id(dataset_id, body.bfabric_id)
    return {"dataset_id": dataset_id, "bfabric_id": body.bfabric_id}


@router.put("/legacy/datasets/{dataset_id}/bfabric-id")
def set_bfabric_id_legacy(
    dataset_id: int,
    body: SetBFabricIdRequest,
    caller: MachineCallerDep,
    service: LegacyDatasetImportServiceDep,
) -> dict:
    """Write B-Fabric dataset ID back onto a legacy SUSHI dataset.

    Called by btools after B-Fabric registration completes.
    Replicates _sushi_db_set_bfabric_id from register_custom_analysis.py.
    """
    service.set_bfabric_id(dataset_id, body.bfabric_id)
    return {"dataset_id": dataset_id, "bfabric_id": body.bfabric_id}
