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

    # CORS (comma-separated string)
    BACKEND_CORS_ORIGINS: str = ""

    @property
    def cors_origins(self) -> list[str]:
        if not self.BACKEND_CORS_ORIGINS:
            return []
        return [origin.strip() for origin in self.BACKEND_CORS_ORIGINS.split(",")]

    @property
    def DATABASE_URI(self) -> str:
        return f"sqlite:///{self.DATABASE_PATH}"


settings = Settings()
