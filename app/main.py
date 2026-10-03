from fastapi import FastAPI

from app.routers import health, items

app = FastAPI(title="CI/CD Learning Demo", version="0.1.0")

app.include_router(health.router)
app.include_router(items.router)


@app.get("/", tags=["root"])
def root() -> dict[str, str]:
    return {
        "message": "CI/CD Learning Demo is running",
        "docs": "/docs",
        "health": "/health",
        "items": "/items",
    }
