from fastapi import APIRouter

from app.api.routes import auth, datasets, jobs, projects

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(datasets.router, prefix="/datasets", tags=["datasets"])
api_router.include_router(jobs.router, prefix="/jobs", tags=["jobs"])
api_router.include_router(projects.router, prefix="/projects", tags=["projects"])
