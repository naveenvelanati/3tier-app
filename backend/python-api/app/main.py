"""
High Availability 3-Tier Application - Python API
FastAPI Backend with Production-Grade Features
"""
import logging
import time
from contextlib import asynccontextmanager
from typing import Any

import sentry_sdk
from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
from prometheus_client import Counter, Histogram, generate_latest
from sentry_sdk.integrations.fastapi import FastApiIntegration
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app.core.config import settings
from app.core.logging_config import setup_logging
from app.db.session import init_db, close_db
from app.middleware.request_id import RequestIDMiddleware
from app.middleware.security_headers import SecurityHeadersMiddleware
from app.api.v1.router import api_router

# Initialize logging
setup_logging()
logger = logging.getLogger(__name__)

# Initialize Sentry
if settings.SENTRY_DSN:
    sentry_sdk.init(
        dsn=settings.SENTRY_DSN,
        environment=settings.ENVIRONMENT,
        traces_sample_rate=1.0,
        integrations=[FastApiIntegration()],
    )

# Prometheus metrics
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)
REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint']
)

# Rate limiter
limiter = Limiter(key_func=get_remote_address)

# Application lifespan
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifecycle"""
    # Startup
    logger.info("Starting application...")
    await init_db()
    logger.info("Database initialized")
    
    yield
    
    # Shutdown
    logger.info("Shutting down application...")
    await close_db()
    logger.info("Application shutdown complete")

# Create FastAPI application
app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="High Availability 3-Tier Cloud Application API",
    docs_url="/api/docs" if settings.ENVIRONMENT != "production" else None,
    redoc_url="/api/redoc" if settings.ENVIRONMENT != "production" else None,
    openapi_url="/api/openapi.json",
    lifespan=lifespan,
)

# Add rate limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Middleware configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(GZipMiddleware, minimum_size=1000)

app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=settings.ALLOWED_HOSTS,
)

app.add_middleware(RequestIDMiddleware)
app.add_middleware(SecurityHeadersMiddleware)

# Request logging middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log all requests and track metrics"""
    start_time = time.time()
    
    # Log request
    logger.info(
        f"Request started: {request.method} {request.url.path}",
        extra={
            "request_id": request.state.request_id,
            "method": request.method,
            "path": request.url.path,
            "client_ip": request.client.host if request.client else None,
        }
    )
    
    # Process request
    try:
        response = await call_next(request)
    except Exception as exc:
        logger.error(
            f"Request failed: {request.method} {request.url.path}",
            extra={
                "request_id": request.state.request_id,
                "error": str(exc),
            },
            exc_info=True,
        )
        raise
    
    # Calculate duration
    duration = time.time() - start_time
    
    # Update metrics
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code,
    ).inc()
    
    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.url.path,
    ).observe(duration)
    
    # Log response
    logger.info(
        f"Request completed: {request.method} {request.url.path}",
        extra={
            "request_id": request.state.request_id,
            "status_code": response.status_code,
            "duration": duration,
        }
    )
    
    # Add timing header
    response.headers["X-Process-Time"] = str(duration)
    
    return response

# Exception handlers
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Handle all uncaught exceptions"""
    logger.error(
        "Unhandled exception",
        extra={
            "request_id": getattr(request.state, "request_id", None),
            "path": request.url.path,
            "error": str(exc),
        },
        exc_info=True,
    )
    
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "detail": "Internal server error",
            "request_id": getattr(request.state, "request_id", None),
        },
    )

# Health check endpoints
@app.get("/health", tags=["Health"])
async def health_check() -> dict[str, Any]:
    """Basic health check endpoint"""
    return {
        "status": "healthy",
        "version": settings.VERSION,
        "environment": settings.ENVIRONMENT,
    }

@app.get("/health/ready", tags=["Health"])
async def readiness_check() -> dict[str, Any]:
    """Readiness check - verify all dependencies are ready"""
    from app.db.session import engine
    
    try:
        # Check database connection
        async with engine.connect() as conn:
            await conn.execute("SELECT 1")
        
        return {
            "status": "ready",
            "checks": {
                "database": "ok",
            }
        }
    except Exception as exc:
        logger.error(f"Readiness check failed: {exc}")
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "status": "not_ready",
                "error": str(exc),
            },
        )

@app.get("/health/live", tags=["Health"])
async def liveness_check() -> dict[str, str]:
    """Liveness check - verify application is running"""
    return {"status": "alive"}

@app.get("/metrics", tags=["Metrics"])
async def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

# Include API routers
app.include_router(api_router, prefix="/api/v1")

# Root endpoint
@app.get("/", tags=["Root"])
async def root() -> dict[str, str]:
    """Root endpoint"""
    return {
        "message": "High Availability 3-Tier Application API",
        "version": settings.VERSION,
        "docs": "/api/docs",
    }

if __name__ == "__main__":
    import uvicorn
    
    uvicorn.run(
        "main:app",
        host=settings.API_HOST,
        port=settings.API_PORT,
        reload=settings.ENVIRONMENT == "development",
        log_level=settings.LOG_LEVEL.lower(),
        access_log=True,
        workers=settings.API_WORKERS if settings.ENVIRONMENT == "production" else 1,
    )
