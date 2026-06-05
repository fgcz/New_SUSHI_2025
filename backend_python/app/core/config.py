from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_ignore_empty=True,
        extra="ignore",
    )

    ENVIRONMENT: str = "local"
    DATABASE_PATH: str = "storage/development.sqlite3"

    # LDAP
    LDAP_HOST: str = "ldap://localhost:389"
    LDAP_BASE_DN: str = "dc=example,dc=com"
    LDAP_BIND_DN: str = "cn=admin,dc=example,dc=com"
    LDAP_BIND_PASSWORD: str = ""
    LDAP_USER_SEARCH_BASE: str = "ou=users,dc=example,dc=com"
    LDAP_GROUP_SEARCH_BASE: str = "ou=groups,dc=example,dc=com"

    # JWT
    JWT_SECRET_KEY: str = "change-this-secret-key-in-production"
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    JWT_REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # Auth bypass for development
    SKIP_AUTH: bool = True  # Skip LDAP, use mock user, allow all projects

    # CORS (comma-separated string)
    BACKEND_CORS_ORIGINS: str = ""

    # Infrastructure paths
    GSTORE_DIR: str = "/srv/gstore/projects"
    GSTORE_URL: str = "https://fgcz-gstore.uzh.ch"  # External URL for file downloads
    SCRATCH_DIR: str = "/scratch"
    MODULE_SOURCE: str = "/usr/local/ngseq/etc/lmod_profile"
    COPY_COMMAND: str = "g-req copynow"  # Dev: "cp -r"

    # Tool paths
    EZ_GLOBAL_VARIABLES: str = "/usr/local/ngseq/opt/EZ_GLOBAL_VARIABLES.txt"
    CONDA_PROFILE: str = "/usr/local/ngseq/miniforge3/etc/profile.d/conda.sh"
    MINICONDA_PROFILE: str = "/usr/local/ngseq/miniconda3/etc/profile.d/conda.sh"

    @property
    def cors_origins(self) -> list[str]:
        if not self.BACKEND_CORS_ORIGINS:
            return []
        return [origin.strip() for origin in self.BACKEND_CORS_ORIGINS.split(",")]

    # Legacy MariaDB (Ruby SUSHI database on fgcz-h-082)
    # Password intentionally separate — matches the SUSHI_DB_PASSWORD env var used by btools.
    # Leave SUSHI_DB_PASSWORD unset to disable legacy endpoints.
    SUSHI_DB_HOST: str = "fgcz-h-082"
    SUSHI_DB_PORT: int = 3306
    SUSHI_DB_USER: str = "sushilover"
    SUSHI_DB_PASSWORD: str = ""
    SUSHI_DB_NAME: str = "sushi"

    @property
    def DATABASE_URI(self) -> str:
        return f"sqlite:///{self.DATABASE_PATH}"

    @property
    def LEGACY_DATABASE_URI(self) -> str | None:
        if not self.SUSHI_DB_PASSWORD:
            return None
        return (
            f"mysql+pymysql://{self.SUSHI_DB_USER}:{self.SUSHI_DB_PASSWORD}"
            f"@{self.SUSHI_DB_HOST}:{self.SUSHI_DB_PORT}/{self.SUSHI_DB_NAME}"
        )


settings = Settings()
