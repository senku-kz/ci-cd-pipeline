# Scripts для CI/CD Pipeline

## setup-remote-server.sh

Скрипт для **одноразовой подготовки удаленного сервера** (Oracle Cloud VM или любой другой Ubuntu сервер).

### Что он делает:

1. **Установка Docker** (если еще не установлен)
2. **Добавление пользователя в группу docker** (для возможности запуска контейнеров без sudo)
3. **Включение и настройка ufw** (файрволл)
4. **Открытие портов:**
   - 22 (SSH)
   - 8000 (master окружение)
   - 8100 (test окружение)
   - 8200 (dev окружение)

### Использование:

На **удаленном сервере** выполните:

```bash
# Скопируйте скрипт на сервер или клонируйте репо
curl -o setup-remote-server.sh https://raw.githubusercontent.com/<user>/<repo>/master/scripts/setup-remote-server.sh

# Или если уже есть репо:
cd /path/to/repo/scripts

# Запустите скрипт с sudo
sudo bash setup-remote-server.sh
```

### Обязательно после запуска:

После выполнения скрипта требуется **переподключение SSH** для применения прав docker:

```bash
exit
ssh -i ~/.ssh/your-key ubuntu@server-ip
docker ps  # Проверьте, что Docker работает
```

---

## deploy.sh

Скрипт для **деплоя контейнера** на сервер. Вызывается автоматически GitHub Actions.

### Использование (ручной деплой):

```bash
export GHCR_IMAGE="ghcr.io/<user>/<repo>"
export IMAGE_TAG="master-abc123"
export ENV_NAME="master"
export APP_PORT="8000"

bash deploy.sh
```

### Что происходит:

1. Скачивает образ из GHCR
2. Останавливает старый контейнер (если был)
3. Запускает новый контейнер на указанном порту
4. Проверяет health-check (10 попыток с интервалом 2 сек)
5. Выходит с ошибкой, если health-check не пройден

### Переменные окружения:

| Переменная | Пример | Описание |
|-----------|--------|---------|
| `GHCR_IMAGE` | `ghcr.io/user/ci-cd-pipeline` | Адрес образа в GitHub Container Registry |
| `IMAGE_TAG` | `master-abc123def` | Тег образа (обычно `<env>-<git_sha>`) |
| `ENV_NAME` | `master`, `test`, `dev` | Имя окружения |
| `APP_PORT` | `8000`, `8100`, `8200` | Порт на хосте |

### Обязательные условия:

- Docker установлен и работает
- Пользователь в группе `docker` (может запускать контейнеры без sudo)
- Образ доступен для скачивания (публичный или logged in)
- Приложение имеет `/health` endpoint, возвращающий HTTP 200

---

## Общий workflow для студентов:

### 1️⃣ Подготовка сервера (один раз):

```bash
ssh -i ~/.ssh/your-key ubuntu@server-ip
sudo bash scripts/setup-remote-server.sh
exit
# Переподключиться
ssh -i ~/.ssh/your-key ubuntu@server-ip
```

### 2️⃣ Настройка GitHub (один раз):

- Settings → Secrets → `SSH_HOST`, `SSH_USER`, `SSH_PRIVATE_KEY`, `SSH_PORT`
- Settings → General → Make repository public

### 3️⃣ Разработка и деплой (регулярно):

```bash
git push origin master  # CI/CD запустится автоматически
```

GitHub Actions:
- Запустит тесты, линтер, SAST/SCA сканирование
- Соберет Docker образ
- Запушит в GitHub Container Registry
- Вызовет `deploy.sh` на сервере через SSH

---

## Возможные проблемы:

### "Docker: command not found" после переподключения

**Решение:** Вы еще не переподключились после запуска скрипта. Выполните:

```bash
exit
ssh -i ~/.ssh/your-key ubuntu@server-ip
```

### "Permission denied while trying to connect to the Docker daemon"

**Решение:** Пользователь не в группе docker. Убедитесь, что скрипт завершился успешно и вы переподключились.

### Port 8000 already in use

**Решение:** Старый контейнер все еще работает. Остановите его:

```bash
docker stop fastapi-demo-master
docker rm fastapi-demo-master
```

### Health check failed

**Решение:** Приложение не запустилось или не ответило на `/health`. Проверьте логи:

```bash
docker logs fastapi-demo-master
```
