from collections.abc import Generator

from sqlmodel import Session, create_engine

from app.core.config import settings

engine = create_engine(
    settings.DATABASE_URI,
    echo=settings.ENVIRONMENT == "local",
    connect_args={"check_same_thread": False},  # SQLite-specific
)

legacy_engine = (
    create_engine(settings.LEGACY_DATABASE_URI, echo=settings.ENVIRONMENT == "local")
    if settings.LEGACY_DATABASE_URI
    else None
)


def get_session() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session


def get_legacy_session() -> Generator[Session, None, None]:
    if legacy_engine is None:
        raise RuntimeError(
            "Legacy database not configured — set SUSHI_DB_PASSWORD to enable"
        )
    with Session(legacy_engine) as session:
        yield session
