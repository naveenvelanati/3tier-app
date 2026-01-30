"""
Application Configuration
Centralized configuration management using Pydantic Settings
"""
import secrets
from typing import List, Optional

from pydantic import AnyHttpUrl, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings"""
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )
    
    # Application
    PROJECT_NAME: str = "High Availability 3-Tier App"
    VERSION: str = "1.0.0"
    ENVIRONMENT: str = Field(default="production", pattern="^(development|staging|production)$")
    DEBUG: bool = False
    
    # API Configuration
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8000
    API_WORKERS: int = 4
    API_TIMEOUT: int = 60
    
    # Security
    SECRET_KEY: str = Field(default_factory=lambda: secrets.token_urlsafe(32))
    JWT_SECRET_KEY: str = Field(default_factory=lambda: secrets.token_urlsafe(32))
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    JWT_REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    
    # CORS
    CORS_ORIGINS: List[str] = Field(
        default=["http://localhost:3000", "http://localhost:8080"]
    )
    ALLOWED_HOSTS: List[str] = Field(default=["*"])
    
    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def assemble_cors_origins(cls, v: str | List[str]) -> List[str]:
        if isinstance(v, str):
            return [i.strip() for i in v.split(",")]
        return v
    
    # MySQL/RDS Configuration
    MYSQL_HOST: str = Field(default="localhost")
    MYSQL_PORT: int = 3306
    MYSQL_USER: str = Field(default="admin")
    MYSQL_PASSWORD: str = Field(default="password")
    MYSQL_DATABASE: str = Field(default="production_db")
    MYSQL_POOL_SIZE: int = 20
    MYSQL_MAX_OVERFLOW: int = 30
    MYSQL_SSL_MODE: str = "REQUIRED"
    
    @property
    def MYSQL_DATABASE_URI(self) -> str:
        """Construct MySQL connection URI"""
        return (
            f"mysql+aiomysql://{self.MYSQL_USER}:{self.MYSQL_PASSWORD}"
            f"@{self.MYSQL_HOST}:{self.MYSQL_PORT}/{self.MYSQL_DATABASE}"
            f"?ssl=true" if self.MYSQL_SSL_MODE == "REQUIRED" else ""
        )
    
    # MongoDB Configuration
    MONGODB_HOST: str = Field(default="localhost")
    MONGODB_PORT: int = 27017
    MONGODB_USER: str = Field(default="admin")
    MONGODB_PASSWORD: str = Field(default="password")
    MONGODB_DATABASE: str = Field(default="production_db")
    MONGODB_REPLICA_SET: Optional[str] = "rs0"
    MONGODB_SSL: bool = True
    MONGODB_AUTH_SOURCE: str = "admin"
    
    @property
    def MONGODB_URI(self) -> str:
        """Construct MongoDB connection URI"""
        ssl_param = "?ssl=true&ssl_cert_reqs=CERT_NONE" if self.MONGODB_SSL else ""
        replica_param = f"&replicaSet={self.MONGODB_REPLICA_SET}" if self.MONGODB_REPLICA_SET else ""
        auth_param = f"&authSource={self.MONGODB_AUTH_SOURCE}"
        
        return (
            f"mongodb://{self.MONGODB_USER}:{self.MONGODB_PASSWORD}"
            f"@{self.MONGODB_HOST}:{self.MONGODB_PORT}/{self.MONGODB_DATABASE}"
            f"{ssl_param}{replica_param}{auth_param}"
        )
    
    # Redis/ElastiCache Configuration
    REDIS_HOST: str = Field(default="localhost")
    REDIS_PORT: int = 6379
    REDIS_PASSWORD: Optional[str] = None
    REDIS_DB: int = 0
    REDIS_SSL: bool = False
    REDIS_CLUSTER_MODE: bool = False
    
    @property
    def REDIS_URI(self) -> str:
        """Construct Redis connection URI"""
        protocol = "rediss" if self.REDIS_SSL else "redis"
        password = f":{self.REDIS_PASSWORD}@" if self.REDIS_PASSWORD else ""
        return f"{protocol}://{password}{self.REDIS_HOST}:{self.REDIS_PORT}/{self.REDIS_DB}"
    
    # AWS Configuration
    AWS_REGION: str = "us-east-1"
    AWS_ACCESS_KEY_ID: Optional[str] = None
    AWS_SECRET_ACCESS_KEY: Optional[str] = None
    
    # S3
    S3_BUCKET_NAME: str = "prod-app-assets"
    S3_REGION: str = "us-east-1"
    
    # SQS
    SQS_QUEUE_URL: Optional[str] = None
    SQS_DLQ_URL: Optional[str] = None
    
    # SNS
    SNS_TOPIC_ARN: Optional[str] = None
    
    # Secrets Manager
    SECRETS_MANAGER_PREFIX: str = "prod/app/"
    
    # Monitoring & Logging
    LOG_LEVEL: str = "INFO"
    SENTRY_DSN: Optional[str] = None
    
    # Prometheus
    PROMETHEUS_ENDPOINT: Optional[str] = None
    
    # Datadog
    DATADOG_ENABLED: bool = False
    DATADOG_API_KEY: Optional[str] = None
    DATADOG_APP_KEY: Optional[str] = None
    DATADOG_SITE: str = "datadoghq.com"
    
    # New Relic
    NEWRELIC_ENABLED: bool = False
    NEWRELIC_LICENSE_KEY: Optional[str] = None
    NEWRELIC_APP_NAME: Optional[str] = None
    
    # Jaeger Tracing
    JAEGER_AGENT_HOST: Optional[str] = None
    JAEGER_AGENT_PORT: int = 6831
    JAEGER_SAMPLER_TYPE: str = "probabilistic"
    JAEGER_SAMPLER_PARAM: float = 0.1
    
    # Rate Limiting
    RATE_LIMIT: str = "100/minute"
    ENABLE_RATE_LIMITING: bool = True
    
    # Feature Flags
    ENABLE_SWAGGER: bool = True
    ENABLE_PROFILING: bool = False
    VERBOSE_LOGGING: bool = False
    
    # Email Configuration
    SMTP_HOST: str = "email-smtp.us-east-1.amazonaws.com"
    SMTP_PORT: int = 587
    SMTP_USER: Optional[str] = None
    SMTP_PASSWORD: Optional[str] = None
    SMTP_FROM_EMAIL: str = "noreply@yourdomain.com"
    SMTP_USE_TLS: bool = True
    
    # Celery Configuration
    CELERY_BROKER_URL: Optional[str] = None
    CELERY_RESULT_BACKEND: Optional[str] = None
    
    @property
    def CELERY_BROKER_URL_DEFAULT(self) -> str:
        return self.CELERY_BROKER_URL or self.REDIS_URI
    
    @property
    def CELERY_RESULT_BACKEND_DEFAULT(self) -> str:
        return self.CELERY_RESULT_BACKEND or self.REDIS_URI
    
    # Pagination
    DEFAULT_PAGE_SIZE: int = 20
    MAX_PAGE_SIZE: int = 100
    
    # File Upload
    MAX_UPLOAD_SIZE: int = 10 * 1024 * 1024  # 10 MB
    ALLOWED_UPLOAD_EXTENSIONS: List[str] = Field(
        default=[".jpg", ".jpeg", ".png", ".pdf", ".doc", ".docx"]
    )


# Create settings instance
settings = Settings()


# Validate critical settings on startup
def validate_settings():
    """Validate critical configuration settings"""
    errors = []
    
    if settings.ENVIRONMENT == "production":
        if settings.DEBUG:
            errors.append("DEBUG should be False in production")
        
        if settings.SECRET_KEY == "changeme":
            errors.append("SECRET_KEY must be changed in production")
        
        if settings.MYSQL_PASSWORD == "password":
            errors.append("MYSQL_PASSWORD must be changed in production")
        
        if settings.MONGODB_PASSWORD == "password":
            errors.append("MONGODB_PASSWORD must be changed in production")
    
    if errors:
        raise ValueError(f"Configuration errors: {', '.join(errors)}")


# Validate on import
validate_settings()
