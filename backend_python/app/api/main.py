from fastapi import APIRouter

from app.api.routes import auth, datasets

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(datasets.router, prefix="/api/v1/datasets", tags=["datasets"])
