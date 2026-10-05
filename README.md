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

Все рутинные команды собраны в `Makefile` — `make help` показывает список.

```bash
make venv       # python3.12 -m venv .venv
make install    # pip install -r requirements.txt -r requirements-dev.txt
make run        # uvicorn app.main:app --reload
# http://localhost:8000/health
# http://localhost:8000/items
```

Тесты и проверки:

```bash
make test       # pytest -v
make lint       # ruff check .
make format     # black .  (make format-check — только проверка, без изменений)
make security   # bandit --severity-level high + pip-audit
```

Эквивалентные "сырые" команды (если Makefile недоступен, например на Windows без make):

```bash
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
uvicorn app.main:app --reload
pytest -v && ruff check . && black --check .
bandit -r app/ --severity-level high && pip-audit -r requirements.txt
```

## Docker

```bash
make build      # docker build -t ci-cd-pipeline:local .
make up          # docker compose up -d --build
make logs        # docker compose logs -f
make down        # docker compose down
```

## Переменные окружения

Само приложение (`app/`) пока не требует переменных окружения — конфигурации нет.
`.env.example` документирует переменные, которые использует **деплой** (`scripts/deploy.sh`
и `cd.yml`): `GHCR_IMAGE`, `IMAGE_TAG`, `APP_PORT`, `ENV_NAME` (`master`/`test`/`dev` — определяет
имя контейнера `fastapi-demo-<env>`). В GitHub Actions они приходят из secrets, `github.sha`
и джоба `resolve-env`, на VM — передаются по SSH при вызове деплой-скрипта. `deploy.sh`
намеренно фейлится, если `ENV_NAME`/`APP_PORT` не заданы — на одной VM с тремя окружениями
тихий дефолт порта — ровно тот баг, из-за которого `test`/`dev` может случайно затереть `master`.
Если позже в приложение добавится конфигурация (например, URL базы данных), копируйте
`.env.example` → `.env` и подключите `python-dotenv` в `app/main.py`.

## Ветки и окружения

Три ветки, promotion-flow `dev → test → master` (через PR), каждая деплоится на **одну и ту же**
Oracle VM, но в свой контейнер на своём порту — все три окружения работают одновременно:

| Ветка    | Порт на VM | Контейнер              | Теги образа в GHCR                    |
|----------|------------|-------------------------|-----------------------------------------|
| `master` | `8000`     | `fastapi-demo-master`  | `:master`, `:master-<sha>`, `:latest`  |
| `test`   | `8100`     | `fastapi-demo-test`    | `:test`, `:test-<sha>`                 |
| `dev`    | `8200`     | `fastapi-demo-dev`     | `:dev`, `:dev-<sha>`                   |

`:latest` ставится только из `master`, чтобы push в `test`/`dev` не затирал "последний стабильный
прод". Деплоится всегда конкретный `<env>-<sha>`, а не "плывущий" тег ветки.

## Pipeline

### CI (`.github/workflows/ci.yml`) — на каждый PR и push в `master`/`test`/`dev`

```
lint-and-test (ruff + black + pytest)
   ├── bandit       (needs: lint-and-test)  — SAST, фейлит на --severity-level high
   ├── pip-audit    (needs: lint-and-test)  — SCA по requirements.txt
   └── codeql       (needs: lint-and-test)  — алерты попадают в таб Security, не фейлят job
```

### CD (`.github/workflows/cd.yml`) — после успешного CI на `master`/`test`/`dev`

```
resolve-env     — case по branch → env_name + app_port (8000/8100/8200)
   └── build-and-push  (needs: resolve-env) — multi-arch образ → ghcr.io, теги :<env>, :<env>-<sha> (+:latest на master)
         └── deploy    (needs: [resolve-env, build-and-push]) — SSH на Oracle VM, scripts/deploy.sh
```

Деплои разных окружений идут параллельно и независимо; `concurrency: group: deploy-<env_name>`
не даёт пересечься только двум деплоям в *одно и то же* окружение подряд.

## Подготовка окружения

### Удаленный сервер (один раз)

На сервере выполните **автоматизированную подготовку**:

```bash
# Клонируйте репо или скопируйте скрипт
curl -o setup-remote-server.sh https://raw.githubusercontent.com/<user>/<repo>/master/scripts/setup-remote-server.sh

# Запустите с sudo (требуется для Docker и firewall)
sudo bash setup-remote-server.sh

# Переподключитесь (для применения прав группы docker)
exit
ssh -i ~/.ssh/your-key ubuntu@server-ip
docker ps  # Проверьте
```

Подробнее: [scripts/README.md](scripts/README.md)

### GitHub (один раз)

Следующие шаги выполняются **один раз** на GitHub:

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
6. Settings → Branches → добавить правила защиты для `master` и `test`: требовать прохождение
   статус-чека `lint-and-test` (опционально `bandit`/`pip-audit`) перед merge. `dev` оставить
   без защиты для быстрой итерации — это формализует promotion-flow `dev → test → master`.

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
3. Сеть: открыть порты **22, 8000, 8100, 8200** в двух местах —
   - Security List / Network Security Group в VCN (на уровне Oracle Cloud);
   - firewall на самой машине (`ufw`): `sudo ufw allow 8000/tcp && sudo ufw allow 8100/tcp && sudo ufw allow 8200/tcp`
     — это частая причина "порт открыт в консоли, но всё равно не коннектится" (забыли второй уровень).
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
- **Dependabot целится только в default branch** (`master`) — `test`/`dev` не получают
  автоматические PR на обновление зависимостей, если явно не добавить `target-branch`
  в `dependabot.yml`.

## Идеи для расширения (stretch exercises)

- Жёстко гейтить CodeQL-алерты через GitHub API вместо просто отображения в Security tab.
- Автоматический rollback при неуспешном health-check после деплоя.
- Периодическая чистка старых тегов в GHCR отдельным workflow.
- SQLite вместо in-memory storage для реальной персистентности между деплоями.
