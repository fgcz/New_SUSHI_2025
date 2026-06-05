"""Internal routes — machine API key required, no user context.

These routes are called by background services (job_manager, btools).
They are not reachable from the browser and do not use JWT authentication.

Routes:
  GET   /internal/legacy/jobs                    → poll jobs by status (job_manager → legacy MariaDB)
  GET   /internal/legacy/datasets/{id}/jobs      → parent jobs for dependency resolution (job_manager)
  PATCH /internal/legacy/jobs/{id}              → partial job update (job_manager → legacy MariaDB)
  GET   /internal/legacy/projects/{n}/datasets         → datasets for a project (GeoUploader)
  GET   /internal/legacy/datasets/{id}/project         → project number for a dataset (GeoUploader)
  GET   /internal/legacy/datasets/{id}/samples         → parsed sample rows (GeoUploader)
  GET   /internal/legacy/datasets/by-bfabric/{bfid}   → dataset id from bfabric id (GeoUploader)
  POST  /internal/datasets/register             → new MultiOmicsStudio schema
  POST  /internal/legacy/datasets/register      → legacy Ruby SUSHI schema (transition period)
"""

from datetime import datetime

from fastapi import APIRouter, Query
from pydantic import BaseModel
from sqlalchemy import text

from app.api.deps import DatasetImportServiceDep, LegacyDatasetImportServiceDep, LegacyJobRepoDep, LegacySessionDep
from app.core.exceptions import NotFoundError
from app.utils.sample_parser import parse_sample_data

router = APIRouter()


class JobResponse(BaseModel):
    id: int
    submit_job_id: int | None
    input_dataset_id: int | None
    next_dataset_id: int | None
    script_path: str | None
    stdout_path: str | None
    stderr_path: str | None
    submit_command: str | None
    status: str | None
    user: str | None
    start_time: datetime | None
    end_time: datetime | None


@router.get("/legacy/jobs")
def get_jobs_by_status(

    job_repo: LegacyJobRepoDep,
    status: str = Query(description="Comma-separated list of statuses to filter by"),
) -> list[JobResponse]:
    """Return all jobs matching any of the given statuses.

    Called by job_manager each daemon iteration to find jobs to submit or update.
    Example: ?status=CREATED,WAITING_FOR_DEPENDENCY
    """
    statuses = [s.strip() for s in status.split(",") if s.strip()]
    jobs = job_repo.get_by_statuses(statuses)
    return [JobResponse.model_validate(job, from_attributes=True) for job in jobs]


class ParentJobResponse(BaseModel):
    id: int
    submit_job_id: int | None
    status: str | None


@router.get("/legacy/datasets/{dataset_id}/jobs")
def get_jobs_by_dataset(
    dataset_id: int,

    job_repo: LegacyJobRepoDep,
) -> list[ParentJobResponse]:
    """Return jobs that produce a given dataset (next_dataset_id = dataset_id).

    Called by job_manager to resolve SLURM dependencies before submitting a job:
    if any returned job is still active and has no submit_job_id yet, the caller
    must wait; if all active jobs have a submit_job_id, it builds
    --dependency=afterany:id1:id2 for sbatch.
    """
    jobs = job_repo.get_by_next_dataset_id(dataset_id)
    return [ParentJobResponse.model_validate(job, from_attributes=True) for job in jobs]


class PatchJobRequest(BaseModel):
    status: str | None = None
    submit_job_id: int | None = None
    submit_command: str | None = None
    stdout_path: str | None = None
    stderr_path: str | None = None
    start_time: datetime | None = None
    end_time: datetime | None = None


@router.patch("/legacy/jobs/{job_id}")
def patch_job(
    job_id: int,
    body: PatchJobRequest,

    job_repo: LegacyJobRepoDep,
) -> JobResponse:
    """Partially update a job row.

    Called by job_manager on every state transition. Only fields present in the
    request body are written — omitted fields are left unchanged. Sending null
    explicitly clears the field (e.g. stdout_path=null when a pending job is
    cancelled before logs are created).
    """
    fields = body.model_dump(exclude_unset=True)
    job = job_repo.update_fields(job_id, fields)
    if not job:
        from app.core.exceptions import NotFoundError
        raise NotFoundError("Job", job_id)
    return JobResponse.model_validate(job, from_attributes=True)


class LegacyDatasetItem(BaseModel):
    id: int
    name: str | None
    parent_id: int | None


@router.get("/legacy/projects/{project_number}/datasets")
def get_legacy_project_datasets(
    project_number: int,

    session: LegacySessionDep,
) -> list[LegacyDatasetItem]:
    """Return all datasets for a project from the legacy SUSHI schema.

    Replaces GeoUploader SushiService.get_project_datasets() direct DB call.
    Used to render the jsTree dataset selector in the GeoUploader upload flow.
    """
    rows = session.execute(
        text(
            "SELECT data_sets.id, data_sets.name, data_sets.parent_id"
            " FROM data_sets"
            " JOIN projects ON data_sets.project_id = projects.id"
            " WHERE projects.number = :num"
        ),
        {"num": project_number},
    ).fetchall()
    return [LegacyDatasetItem(id=r[0], name=r[1], parent_id=r[2]) for r in rows]


@router.get("/legacy/datasets/by-bfabric/{bfabric_id}")
def get_legacy_dataset_by_bfabric(
    bfabric_id: int,

    session: LegacySessionDep,
) -> dict:
    """Return the SUSHI dataset id for a given B-Fabric dataset id.

    Replaces GeoUploader SushiService.get_dataset_id_from_bfabric_dataset_id().
    Called at login when a B-Fabric token carries a bfabric dataset id.
    """
    row = session.execute(
        text("SELECT id FROM data_sets WHERE bfabric_id = :bfid"),
        {"bfid": bfabric_id},
    ).fetchone()
    if not row:
        raise NotFoundError("Dataset", bfabric_id)
    return {"dataset_id": row[0]}


@router.get("/legacy/datasets/{dataset_id}/project")
def get_legacy_dataset_project(
    dataset_id: int,

    session: LegacySessionDep,
) -> dict:
    """Return the project number that owns a dataset.

    Replaces GeoUploader SushiService.get_project_from_dataset_id().
    Called when GeoUploader receives a dataset_id redirect from SUSHI and
    needs the parent project number to pre-select it in the UI.
    """
    row = session.execute(
        text(
            "SELECT projects.number"
            " FROM data_sets"
            " JOIN projects ON data_sets.project_id = projects.id"
            " WHERE data_sets.id = :id"
        ),
        {"id": dataset_id},
    ).fetchone()
    if not row:
        raise NotFoundError("Dataset", dataset_id)
    return {"project_number": row[0]}


@router.get("/legacy/datasets/{dataset_id}/samples")
def get_legacy_dataset_samples(
    dataset_id: int,

    session: LegacySessionDep,
) -> list[dict]:
    """Return parsed sample rows for a dataset.

    Replaces GeoUploader SushiService.query_key_value_from_dataset_id() and
    get_dataset_column_names() — both derived the same key_value rows.
    Ruby Hash#inspect strings are parsed to plain dicts; the caller can derive
    column names from the keys of the first item.
    """
    rows = session.execute(
        text("SELECT key_value FROM samples WHERE data_set_id = :id"),
        {"id": dataset_id},
    ).fetchall()
    return [parse_sample_data(r[0]) for r in rows]


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

    service: LegacyDatasetImportServiceDep,
) -> dict:
    """Write B-Fabric dataset ID back onto a legacy SUSHI dataset.

    Called by btools after B-Fabric registration completes.
    Replicates _sushi_db_set_bfabric_id from register_custom_analysis.py.
    """
    service.set_bfabric_id(dataset_id, body.bfabric_id)
    return {"dataset_id": dataset_id, "bfabric_id": body.bfabric_id}
