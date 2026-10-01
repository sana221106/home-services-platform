"""Application settings (§87, §109, §135).

Secrets are never committed: only placeholders live in ``.env.example``.
Every external integration is optional at boot time (§135) so the service
starts and serves the vertical slice without Supabase/Firebase/AI credentials.
"""

from __future__ import annotations

import functools
from typing import Literal

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

Environment = Literal["development", "test", "staging", "production"]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # ---------------------------------------------------------------- app
    app_name: str = "Home Services Platform API"
    app_version: str = "1.0.0"
    environment: Environment = "development"
    debug: bool = False
    api_v1_prefix: str = "/api/v1"
    cors_allow_origins: list[str] = Field(default_factory=lambda: ["*"])

    # ------------------------------------------------------------ database
    database_url: str = "postgresql+psycopg://postgres:postgres@localhost:5432/home_services"
    sql_echo: bool = False
    db_pool_size: int = 10
    db_max_overflow: int = 20
    db_pool_pre_ping: bool = True

    # --------------------------------------------------------- seeding/demo
    #: Only consumed by ``python -m app.db.seed --demo``. An empty password
    #: makes the seeder generate a random one and print it once.
    seed_admin_phone: str = "+201000000000"
    seed_admin_password: str = ""

    # ------------------------------------------------------------ security
    jwt_secret: SecretStr = SecretStr("dev-only-insecure-secret-change-me")
    jwt_algorithm: str = "HS256"
    access_token_ttl_minutes: int = 60 * 12
    refresh_token_ttl_days: int = 30
    otp_ttl_minutes: int = 5
    otp_max_attempts: int = 5
    argon2_time_cost: int = 3
    argon2_memory_cost: int = 65536
    argon2_parallelism: int = 4

    # -------------------------------------------------------- media/upload
    max_upload_bytes: int = 12 * 1024 * 1024
    max_image_dimension: int = 6000
    max_images_per_request: int = 8
    allowed_image_mimes: frozenset[str] = frozenset(
        {"image/jpeg", "image/png", "image/webp"}
    )
    storage_root: str = "./var/storage"
    storage_public_base_url: str = ""
    signed_url_ttl_seconds: int = 900

    # ------------------------------------------------------------ rate limit
    rate_limit_enabled: bool = True
    rate_limit_default: str = "300/minute"
    rate_limit_otp: str = "5/minute"
    rate_limit_login: str = "10/minute"
    rate_limit_media: str = "40/hour"
    rate_limit_chat: str = "60/minute"
    rate_limit_complaint: str = "5/hour"
    rate_limit_ai: str = "20/minute"
    rate_limit_payment_proof: str = "10/hour"

    # ---------------------------------------------------------- integrations
    # All optional (§135). Adapters degrade to an explicit "not configured" state.
    supabase_url: str | None = None
    supabase_anon_key: SecretStr | None = None
    supabase_service_role_key: SecretStr | None = None
    supabase_storage_bucket: str = "request-media"
    supabase_auth_enabled: bool = False

    firebase_credentials_json: str | None = None
    firebase_project_id: str | None = None
    firebase_enabled: bool = False

    ai_provider: Literal["openai", "anthropic", "gemini", "custom", "none"] = "none"
    ai_api_key: SecretStr | None = None
    ai_base_url: str | None = None
    ai_model: str = "gpt-4o-mini"
    ai_enabled: bool = False
    ai_classification_threshold: float = 0.55

    support_phone: str = "+201000000000"

    @field_validator("cors_allow_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @field_validator("allowed_image_mimes", mode="before")
    @classmethod
    def _wrap_mimes(cls, value: object) -> object:
        if isinstance(value, (set, frozenset, list, tuple)):
            return frozenset(str(item) for item in value)
        return value

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    @property
    def supabase_configured(self) -> bool:
        return bool(self.supabase_url and self.supabase_service_role_key)

    @property
    def firebase_configured(self) -> bool:
        return bool(self.firebase_enabled and self.firebase_project_id)

    @property
    def ai_configured(self) -> bool:
        return bool(self.ai_enabled and self.ai_api_key and self.ai_provider != "none")


@functools.lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()