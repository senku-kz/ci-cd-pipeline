# Учебный CI/CD pipeline

Небольшой FastAPI-сервис, который используется как площадка для обучения полному CI/CD
pipeline: от коммита до работающего в облаке сервиса, с ИБ-сканированием на каждом шаге.

## Стек

- **Приложение**: Python 3.12, FastAPI
- **CI**: GitHub Actions — lint, тесты, Bandit (SAST), CodeQL, pip-audit (SCA)
- **Dependabot**: автоматические PR на обновление зависимостей (pip / github-actions / docker)
- **CD**: Docker-образ → GitHub Container Registry (ghcr.io) → деплой по SSH
- **Хостинг**: Oracle Cloud "Always Free" VM

## Локальная разработка

```bash
python3.12 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt -r requirements-dev.txt

uvicorn app.main:app --reload
# http://localhost:8000/health
# http://localhost:8000/items
```

Тесты и проверки:

```bash
pytest -v
ruff check .
black --check .
bandit -r app/ --severity-level high
pip-audit -r requirements.txt
```

## Docker

```bash
docker build -t ci-cd-pipeline:local .
docker run -p 8000:8000 ci-cd-pipeline:local
curl http://localhost:8000/health
```

Или через `docker-compose up`.

## Pipeline

### CI (`.github/workflows/ci.yml`) — на каждый PR и push

```
lint-and-test (ruff + black + pytest)
   ├── bandit       (needs: lint-and-test)  — SAST, фейлит на --severity-level high
   ├── pip-audit    (needs: lint-and-test)  — SCA по requirements.txt
   └── codeql       (needs: lint-and-test)  — алерты попадают в таб Security, не фейлят job
```

### CD (`.github/workflows/cd.yml`) — только после успешного CI на `main`

```
build-and-push  — multi-arch (amd64+arm64) образ → ghcr.io, теги :latest и :<sha>
   └── deploy    (needs: build-and-push) — SSH на Oracle VM, scripts/deploy.sh
```

## Ручная настройка (один раз)

### GitHub

1. Сделать репозиторий **публичным** — бесплатный CodeQL и безлимитные Actions minutes
   работают только для публичных репо.
2. Settings → Actions → General → Workflow permissions → **Read and write permissions**
   (нужно, чтобы `GITHUB_TOKEN` мог пушить в GHCR).
3. Settings → Secrets and variables → Actions → добавить:
   - `SSH_HOST` — публичный IP Oracle VM
   - `SSH_USER` — `ubuntu` (для Ubuntu-образа) или `opc` (для Oracle Linux)
   - `SSH_PRIVATE_KEY` — приватный ключ **отдельной** deploy-пары (не личный ключ!)
   - `SSH_PORT` — обычно `22`
4. После первого успешного push образа: Packages → `ci-cd-pipeline` → Package settings →
   **Change visibility → Public** (чтобы VM могла `docker pull` без логина в GHCR).
5. Settings → Code security and analysis → включить **Dependabot alerts**.

### Oracle Cloud

1. Завести Always Free аккаунт (при регистрации требуется карта для верификации личности —
   это не означает оплату Always Free ресурсов).
2. Создать Compute instance:
   - Предпочтительно `VM.Standard.A1.Flex` (ARM Ampere, до 4 OCPU/24GB бесплатно).
   - Если в регионе нет свободной ARM-ёмкости ("Out of capacity" — известная проблема),
     попробовать другую Availability Domain, затем другой регион, и только потом —
     fallback на `VM.Standard.E2.1.Micro` (x86). Образ в pipeline собирается под оба
     архитектуры (`linux/amd64,linux/arm64`), так что смена шейпа не требует правок CI.
   - Образ ОС: Ubuntu 22.04/24.04.
   - При создании сгенерировать **отдельную** SSH-пару для деплоя — приватный ключ пойдёт
     в секрет `SSH_PRIVATE_KEY`.
3. Сеть: открыть порты **22** и **80** в двух местах —
   - Security List / Network Security Group в VCN (на уровне Oracle Cloud);
   - firewall на самой машине (`iptables`/`ufw`) — это частая причина "порт открыт в
     консоли, но всё равно не коннектится".
4. Зайти на VM по SSH вручную один раз:
   ```bash
   curl -fsSL https://get.docker.com | sh
   sudo usermod -aG docker $USER
   # перелогиниться, чтобы группа применилась
   ```
5. (опционально) Закрепить Reserved Public IP, чтобы `SSH_HOST` не менялся при перезагрузке.

## Готчасы

- **GitHub Actions minutes** — безлимитны только для публичных репозиториев.
- **CodeQL** — бесплатен только для публичных репо (для приватных нужен платный GHAS).
- **GHCR** — у бесплатного tier есть квоты на storage/bandwidth; стоит периодически
  чистить старые теги образов.
- **Oracle ARM-ёмкость** — `VM.Standard.A1.Flex` иногда недоступен ("Out of capacity") в
  популярных регионах; пробовать другие AD/регионы перед fallback на x86.
- **Bandit/pip-audit false positives** — управляются явно: `--severity-level` у Bandit,
  `--ignore-vuln <ID>` у pip-audit (с комментарием, почему исключение принято).

## Идеи для расширения (stretch exercises)

- Жёстко гейтить CodeQL-алерты через GitHub API вместо просто отображения в Security tab.
- Автоматический rollback при неуспешном health-check после деплоя.
- Периодическая чистка старых тегов в GHCR отдельным workflow.
- SQLite вместо in-memory storage для реальной персистентности между деплоями.
