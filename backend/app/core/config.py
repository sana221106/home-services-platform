"""Application settings (§87, §109, §135).

Secrets are never committed: only placeholders live in ``.env.example``.
Every external integration is optional at boot time (§135) so the service
starts and serves the vertical slice without Supabase/Firebase/AI credentials.
"""

from __future__ import annotations

import functools
from typing import Annotated, Literal
from urllib.parse import urlsplit

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

Environment = Literal["development", "test", "staging", "production"]

#: Placeholder shipped in the source tree. It is not a secret and is rejected
#: outright when ``ENVIRONMENT=production``.
INSECURE_JWT_SECRET = "dev-only-insecure-secret-change-me"  # noqa: S105


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
    #: ``NoDecode`` is required: pydantic-settings JSON-decodes list-typed
    #: environment variables *before* any ``mode="before"`` validator runs, so
    #: without it a plain ``CORS_ALLOW_ORIGINS=*`` aborts startup with
    #: ``SettingsError`` instead of reaching :meth:`_split_origins`.
    cors_allow_origins: Annotated[list[str], NoDecode] = Field(
        default_factory=lambda: ["*"]
    )

    # ------------------------------------------------------------ database
    database_url: str = "postgresql+psycopg://postgres:postgres@localhost:5432/home_services"
    sql_echo: bool = False
    db_pool_size: int = 10
    db_max_overflow: int = 20
    db_pool_pre_ping: bool = True
    #: Recycle a pooled connection after N seconds. Supabase and most managed
    #: proxies drop idle sessions well before an hour, so this stays short of
    #: the usual 3600 to avoid handing out dead sockets.
    db_pool_recycle_seconds: int = 600
    #: Seconds to wait for a free pooled connection before raising.
    db_pool_timeout_seconds: int = 10
    #: Seconds to wait for a new TCP/TLS handshake.
    db_connect_timeout_seconds: int = 10
    #: Applied only when DATABASE_URL carries no ``sslmode`` of its own.
    #: ``require`` is correct for Supabase; leave empty for a local socket.
    db_sslmode: str = ""
    #: Reported to Postgres so operators can attribute connections in
    #: ``pg_stat_activity``.
    db_application_name: str = "home-services-api"
    #: Refuse to boot in production while these still hold their dev defaults.
    db_reject_insecure_production_url: bool = True

    # --------------------------------------------------------- seeding/demo
    #: Only consumed by ``python -m app.db.seed --demo``. An empty password
    #: makes the seeder generate a random one and print it once.
    seed_admin_phone: str = "+201000000000"
    seed_admin_password: str = ""

    # ------------------------------------------------------------ security
    jwt_secret: SecretStr = SecretStr(INSECURE_JWT_SECRET)
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
    #: ``NoDecode`` for the same reason as ``cors_allow_origins``: a plain
    #: comma-separated ``ALLOWED_IMAGE_MIMES=image/png,image/webp`` must reach
    #: :meth:`_wrap_mimes` rather than being JSON-decoded first.
    allowed_image_mimes: Annotated[frozenset[str], NoDecode] = frozenset(
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
    #: Supabase's current name for the anon key. Preferred over
    #: :attr:`supabase_anon_key`; both resolve through
    #: :attr:`supabase_publishable` so operators can use either spelling.
    supabase_publishable_key: SecretStr | None = None
    #: Legacy Supabase name for the same key, kept for older dashboards.
    supabase_anon_key: SecretStr | None = None
    supabase_service_role_key: SecretStr | None = None
    #: Fallback bucket for storage paths that carry no recognised logical
    #: prefix. Real paths are routed by the first path segment; see
    #: app.integrations.supabase.storage.BUCKET_BY_PREFIX.
    supabase_storage_bucket: str = "request-media"
    supabase_storage_timeout_seconds: float = 30.0
    #: Stays false: the platform owns its OTP/JWT flow, and enabling Supabase
    #: Auth would create a second, conflicting identity system (§135).
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

    # -------------------------------------------------------------- geocoding
    # Address search is proxied rather than called from the app so the OSM usage
    # policy is honoured in one place: a single identifying User-Agent, and one
    # request per second regardless of how many customers are searching (§135).
    geocoder_enabled: bool = True
    geocoder_provider: Literal["nominatim", "none"] = "nominatim"
    nominatim_base_url: str = "https://nominatim.openstreetmap.org"
    nominatim_user_agent: str = "HomeServicesPlatform/1.0 (ops@example.com)"
    nominatim_timeout_seconds: float = 8.0
    geocode_cache_ttl_seconds: int = 86_400
    geocode_min_query_length: int = 3
    geocode_max_results: int = 6
    # Biases every search to Egypt so a bare street name ranks local results.
    geocode_country_codes: str = "eg"

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
        # ``NoDecode`` hands the raw env string here, so it must be split; a
        # JSON list still arrives as a real collection from an explicit init.
        if isinstance(value, str):
            return frozenset(
                item.strip() for item in value.split(",") if item.strip()
            )
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
    def supabase_publishable(self) -> SecretStr | None:
        """The publishable/anon key, accepting either Supabase spelling."""
        return self.supabase_publishable_key or self.supabase_anon_key

    @property
    def firebase_configured(self) -> bool:
        return bool(self.firebase_enabled and self.firebase_project_id)

    @property
    def ai_configured(self) -> bool:
        return bool(self.ai_enabled and self.ai_api_key and self.ai_provider != "none")

    # ------------------------------------------------------------ validation

    def _production_problems(self) -> list[str]:
        """Insecure-by-default settings that must not survive a production boot."""
        problems: list[str] = []
        if self.jwt_secret.get_secret_value() == INSECURE_JWT_SECRET:
            problems.append("JWT_SECRET still holds its built-in development value")
        if self.supabase_auth_enabled:
            problems.append(
                "SUPABASE_AUTH_ENABLED must stay false: the platform owns its OTP/JWT flow"
            )
        problems.extend(self._database_url_problems())
        return problems

    def _database_url_problems(self) -> list[str]:
        if not self.db_reject_insecure_production_url:
            return []
        url = self.database_url
        if not url.startswith("postgresql+psycopg://"):
            return ["DATABASE_URL must use the postgresql+psycopg driver"]
        parsed = urlsplit(url.replace("postgresql+psycopg://", "postgresql://", 1))
        problems: list[str] = []
        if parsed.password is None:
            problems.append("DATABASE_URL is missing a password")
        if parsed.query.find("sslmode") < 0 and not self.db_sslmode:
            problems.append("DATABASE_URL must set sslmode for a managed database")
        return problems

    def assert_production_safe(self) -> None:
        """Fail fast at boot rather than serving with a known-bad secret."""
        if not self.is_production:
            return
        problems = self._production_problems()
        if problems:
            raise RuntimeError(
                "Refusing to start in production with unsafe configuration: "
                + "; ".join(problems)
            )


@functools.lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()