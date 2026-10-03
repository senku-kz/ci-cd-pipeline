.DEFAULT_GOAL := help
IMAGE_NAME := ci-cd-pipeline
VENV := .venv/bin

.PHONY: help venv install run test lint format format-check security bandit pip-audit \
        build up down restart logs sh clean

help:
	@echo "make venv           — создать .venv (python3.12)"
	@echo "make install        — установить зависимости (runtime + dev)"
	@echo "make run            — запустить приложение локально (uvicorn --reload)"
	@echo "make test           — прогнать pytest"
	@echo "make lint           — ruff check"
	@echo "make format         — black ."
	@echo "make format-check   — black --check ."
	@echo "make security       — bandit + pip-audit"
	@echo "make build          — docker build"
	@echo "make up             — docker compose up -d (собрать и запустить)"
	@echo "make down           — docker compose down"
	@echo "make restart        — down + up"
	@echo "make logs           — docker compose logs -f"
	@echo "make sh             — shell внутри работающего контейнера"
	@echo "make clean          — удалить кеши (__pycache__, .pytest_cache, .ruff_cache)"

venv:
	python3.12 -m venv .venv

install:
	$(VENV)/pip install -r requirements.txt -r requirements-dev.txt

run:
	$(VENV)/uvicorn app.main:app --reload

test:
	$(VENV)/pytest -v

lint:
	$(VENV)/ruff check .

format:
	$(VENV)/black .

format-check:
	$(VENV)/black --check .

bandit:
	$(VENV)/bandit -r app/ --severity-level high

pip-audit:
	$(VENV)/pip-audit -r requirements.txt

security: bandit pip-audit

build:
	docker build -t $(IMAGE_NAME):local .

up:
	docker compose up -d --build

down:
	docker compose down

restart: down up

logs:
	docker compose logs -f

sh:
	docker compose exec app /bin/bash

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} +
	rm -rf .pytest_cache .ruff_cache bandit-report.json
