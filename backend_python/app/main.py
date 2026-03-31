from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.main import api_router
from app.core.config import settings

app = FastAPI(title="SUSHI Backend")

# CORS middleware - must be added before routes
if settings.cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

app.include_router(api_router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
