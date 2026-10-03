from fastapi import APIRouter, HTTPException

from app.models import Item, ItemCreate
from app.storage import store

router = APIRouter(prefix="/items", tags=["items"])


@router.get("", response_model=list[Item])
def list_items() -> list[Item]:
    return store.list()


@router.post("", response_model=Item, status_code=201)
def create_item(payload: ItemCreate) -> Item:
    return store.create(payload)


@router.get("/{item_id}", response_model=Item)
def get_item(item_id: int) -> Item:
    item = store.get(item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    return item


@router.delete("/{item_id}", status_code=204)
def delete_item(item_id: int) -> None:
    if not store.delete(item_id):
        raise HTTPException(status_code=404, detail="Item not found")
