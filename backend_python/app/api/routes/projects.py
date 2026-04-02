from math import ceil

from fastapi import APIRouter
from sqlmodel import func, or_, select

from app.api.deps import SessionDep
from app.models import DataSet, Job, Project, User

router: APIRouter = APIRouter()


@router.get("/{user}")
def get_user_projects(user: str) -> dict[str, object]:
    projects: list[int] = []
    for i in range(100):
        projects.append(i)
    return {
        "projects": projects,
        "current_user": user,
    }


@router.get("/{project_number}/datasets")
def get_project_datasets(
    session: SessionDep,
    project_number: int,
    page: int = 1,
    per: int = 50,
    q: str = "",
) -> dict[str, object]:
    """Returns datasets under a project_number with pagination and search."""
    # Clamp per to [1, 200]
    per = max(1, min(per, 200))

    # Build base filter conditions
    base_conditions = [Project.number == project_number]
    if q:
        base_conditions.append(DataSet.name.contains(q))

    # Count query using SQL COUNT()
    count_statement = (
        select(func.count())
        .select_from(DataSet)
        .join(Project, DataSet.project_id == Project.id)
        .where(*base_conditions)
    )
    total_count = session.exec(count_statement).one()
    total_pages = max(1, ceil(total_count / per))


    # Paginated data query
    statement = (
        select(DataSet)
        .join(Project, DataSet.project_id == Project.id)
        .where(*base_conditions)
        .order_by(DataSet.created_at.desc())
        .offset((page - 1) * per)
        .limit(per)
    )
    datasets = session.exec(statement).all()

    # Load users
    user_ids = {ds.user_id for ds in datasets if ds.user_id}
    users_map: dict[int, str] = {}
    if user_ids:
        users = session.exec(select(User).where(User.id.in_(user_ids))).all()
        users_map = {u.id: u.login for u in users}

    # Load children IDs
    dataset_ids = [ds.id for ds in datasets]
    children_map: dict[int, list[int]] = {ds_id: [] for ds_id in dataset_ids}
    if dataset_ids:
        children_rows = session.exec(
            select(DataSet.id, DataSet.parent_id).where(
                DataSet.parent_id.in_(dataset_ids)
            )
        ).all()
        for child_id, parent_id in children_rows:
            children_map[parent_id].append(child_id)

    return {
        "datasets": [
            serialize_dataset(ds, project_number, users_map, children_map)
            for ds in datasets
        ],
        "pagination": {
            "total_count": total_count,
            "page": page,
            "per": per,
            "total_pages": total_pages,
        },
        "filters": {
            "q": q,
        },
        "project_number": project_number,
    }


@router.get("/{project_number}/jobs")
def get_project_jobs(
    session: SessionDep,
    project_number: int,
    page: int = 1,
    per: int = 50,
    status: str | None = None,
    user: str | None = None,
    q: str | None = None,
) -> dict[str, object]:
    """Returns jobs for a project with pagination and filtering."""
    per = max(1, min(per, 200))

    dataset_ids_statement = (
        select(DataSet.id)
        .join(Project, DataSet.project_id == Project.id)
        .where(Project.number == project_number)
    )
    dataset_ids = list(session.exec(dataset_ids_statement).all())

    # Build filter conditions
    # Jobs belong to project if their input or output dataset is in this project
    filter_conditions = [
        or_(
            Job.next_dataset_id.in_(dataset_ids),
            Job.input_dataset_id.in_(dataset_ids),
        )
    ]
    if status:
        filter_conditions.append(Job.status == status)
    if user:
        filter_conditions.append(Job.user == user)
    if q:
        filter_conditions.append(DataSet.name.contains(q))

    # Count query
    count_statement = (
        select(func.count()).select_from(Job).where(*filter_conditions)
    )
    total_count = session.exec(count_statement).one()
    total_pages = max(1, ceil(total_count / per))

    # Paginated data query
    statement = (
        select(Job)
        .where(*filter_conditions)
        .order_by(Job.created_at.desc())
        .offset((page - 1) * per)
        .limit(per)
    )
    jobs = session.exec(statement).all()

    # Batch load dataset names 
    job_dataset_ids = {j.next_dataset_id for j in jobs if j.next_dataset_id}
    dataset_names: dict[int, str] = {}
    if job_dataset_ids:
        rows = session.exec(
            select(DataSet.id, DataSet.name).where(DataSet.id.in_(job_dataset_ids))
        ).all()
        dataset_names = {ds_id: name for ds_id, name in rows}

    # Serialize jobs
    serialized_jobs = []
    for job in jobs:
        ds_id = job.next_dataset_id
        serialized_jobs.append({
            "id": job.id,
            "submit_job_id": job.submit_job_id,
            "status": job.status or "unknown",
            "user": job.user or "unknown",
            "dataset": {"id": ds_id, "name": dataset_names.get(ds_id)} if ds_id else None,
            "time": {
                "start_time": job.start_time.isoformat() if job.start_time else None,
                "end_time": job.end_time.isoformat() if job.end_time else None,
            },
            "created_at": job.created_at.isoformat() if job.created_at else None,
        })

    return {
        "jobs": serialized_jobs,
        "pagination": {
            "total_count": total_count,
            "page": page,
            "per": per,
            "total_pages": total_pages,
        },
        "filters": {
            "status": status,
            "user": user,
            "q": q,
        },
        "project_number": project_number,
    }


@router.get("/{project_number}/datasets/tree")
def get_project_datasets_tree(
    session: SessionDep, project_number: int
) -> dict[str, object]:
    """Returns tree structure of datasets for a project (jstree format)."""
    datasets_statement = (
        select(DataSet.id, DataSet.parent_id, DataSet.name, DataSet.comment)
        .join(Project, DataSet.project_id == Project.id)
        .where(Project.number == project_number)
    )
    rows = session.exec(datasets_statement).all()

    # Unpack tuples into a list of dicts for easier handling
    datasets = [
        {"id": ds_id, "parent_id": parent_id, "name": name, "comment": comment}
        for ds_id, parent_id, name, comment in rows
    ]

    # Build lookup of existing dataset IDs (for valid parent check)
    dataset_ids = {ds["id"] for ds in datasets}

    # Batch load children counts
    children_counts: dict[int, int] = {ds_id: 0 for ds_id in dataset_ids}
    if dataset_ids:
        children_rows = session.exec(
            select(DataSet.parent_id, func.count(DataSet.id))
            .where(DataSet.parent_id.in_(dataset_ids))
            .group_by(DataSet.parent_id)
        ).all()
        for parent_id, count in children_rows:
            children_counts[parent_id] = count

    # Build tree nodes
    tree_nodes = []
    for ds in datasets:
        ds_id = ds["id"]
        parent_id = ds["parent_id"]
        # Use "#" for root nodes (no parent or parent not in this project)
        parent = parent_id if parent_id and parent_id in dataset_ids else "#"

        tree_nodes.append({
            "id": ds_id,
            "name": ds["name"],
            "comment": ds["comment"],
            "parent": parent,
            "children_count": children_counts.get(ds_id, 0),
        })

    # Sort by id descending
    tree_nodes.sort(key=lambda node: -node["id"])

    return {"tree": tree_nodes, "project_number": project_number}


def serialize_dataset(
    ds: DataSet,
    project_number: int,
    users_map: dict[int, str],
    children_map: dict[int, list[int]],
) -> dict[str, object]:
    """Serialize a dataset row."""
    return {
        "id": ds.id,
        "name": ds.name,
        "sushi_app_name": ds.sushi_app_name,
        "completed_samples": ds.completed_samples,
        "samples_length": ds.num_samples,
        "parent_id": ds.parent_id,
        "children_ids": children_map.get(ds.id, []),
        "user_login": users_map.get(ds.user_id) if ds.user_id else None,
        "created_at": ds.created_at.isoformat() if ds.created_at else None,
        "bfabric_id": ds.bfabric_id,
        "order_id": ds.order_id,
        "project_number": project_number,
        "comment": ds.comment,
    }
