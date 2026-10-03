def test_list_items_empty(client):
    response = client.get("/items")
    assert response.status_code == 200
    assert response.json() == []


def test_create_and_get_item(client):
    create_resp = client.post("/items", json={"name": "Widget", "description": "A test widget"})
    assert create_resp.status_code == 201
    created = create_resp.json()
    assert created["name"] == "Widget"
    assert created["id"] == 1

    get_resp = client.get(f"/items/{created['id']}")
    assert get_resp.status_code == 200
    assert get_resp.json() == created


def test_get_missing_item_returns_404(client):
    response = client.get("/items/999")
    assert response.status_code == 404


def test_delete_item(client):
    created = client.post("/items", json={"name": "Temp"}).json()

    delete_resp = client.delete(f"/items/{created['id']}")
    assert delete_resp.status_code == 204

    get_resp = client.get(f"/items/{created['id']}")
    assert get_resp.status_code == 404


def test_delete_missing_item_returns_404(client):
    response = client.delete("/items/999")
    assert response.status_code == 404


def test_create_item_validates_empty_name(client):
    response = client.post("/items", json={"name": ""})
    assert response.status_code == 422
