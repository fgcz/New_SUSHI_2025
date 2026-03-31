from sqlmodel import Session, create_engine

from app.core.config import settings

engine = create_engine(
    settings.DATABASE_URI,
    echo=settings.ENVIRONMENT == "local",
    connect_args={"check_same_thread": False},  # SQLite specific
)


def get_session():
    with Session(engine) as session:
        yield session
