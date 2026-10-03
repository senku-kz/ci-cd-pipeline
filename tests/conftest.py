import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.storage import store


@pytest.fixture
def client() -> TestClient:
    store._items.clear()
    store._next_id = 1
    return TestClient(app)
