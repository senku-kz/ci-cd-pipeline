#!/usr/bin/env bash
set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Вспомогательные функции
info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

error() {
    echo -e "${RED}✗${NC} $*" >&2
    exit 1
}

# Проверка прав
if [ "$EUID" -ne 0 ]; then
    error "Этот скрипт требует прав sudo. Запустите: sudo bash $0"
fi

info "Подготовка удаленного сервера для CI/CD pipeline"
echo ""

# === Установка Docker ===
info "Проверка Docker..."

if command -v docker &>/dev/null; then
    success "Docker уже установлен"
    docker --version
else
    info "Установка Docker..."
    curl -fsSL https://get.docker.com | sh
    success "Docker установлен"
fi

# Добавление текущего пользователя в группу docker
CURRENT_USER="${SUDO_USER:-${USER}}"
if id -nG "$CURRENT_USER" | grep -qw docker; then
    success "Пользователь $CURRENT_USER уже в группе docker"
else
    info "Добавление пользователя $CURRENT_USER в группу docker..."
    usermod -aG docker "$CURRENT_USER"
    success "Пользователь добавлен в группу docker"
    warn "Требуется переподключение SSH для применения прав"
fi

echo ""

# === Настройка файрволла ===
info "Настройка файрволла (ufw)..."

# Проверяем, установлен ли ufw
if ! command -v ufw &>/dev/null; then
    info "Установка ufw..."
    apt-get update -qq
    apt-get install -y -qq ufw >/dev/null
    success "ufw установлен"
fi

# Включаем ufw (без интерактивного запроса)
if ufw status | grep -q "Status: active"; then
    success "ufw уже включен"
else
    info "Включение ufw..."
    echo "y" | ufw enable >/dev/null 2>&1 || true
    success "ufw включен"
fi

# Открываем необходимые порты (22 уже открыт для удаленной работы)
PORTS=(8000 8100 8200)
PORTS_NAMES=("master" "test" "dev")

for i in "${!PORTS[@]}"; do
    PORT=${PORTS[$i]}
    NAME=${PORTS_NAMES[$i]}
    if ufw status numbered | grep -q "$PORT/tcp"; then
        success "Порт $PORT ($NAME) уже открыт"
    else
        info "Открытие порта $PORT ($NAME)..."
        ufw allow "$PORT/tcp" >/dev/null
        success "Порт $PORT ($NAME) открыт"
    fi
done

echo ""
echo "════════════════════════════════════════════════════════════"
success "Подготовка сервера завершена!"
echo "════════════════════════════════════════════════════════════"
echo ""

info "Статус файрволла:"
ufw status | tail -n +2

echo ""
info "Проверка Docker:"
docker ps 2>/dev/null | head -1 || warn "Docker недоступен до переподключения"

echo ""
echo "Последующие шаги для настройки CI/CD:"
echo ""
echo "1️⃣  Переподключитесь к серверу (если был добавлен в группу docker):"
echo "    exit"
echo "    ssh -i <path-to-key> ubuntu@<server-ip>"
echo ""
echo "2️⃣  Проверьте Docker:"
echo "    docker ps"
echo ""
echo "3️⃣  На GitHub.com настройте Secrets репозитория:"
echo "    1. Перейдите на https://github.com/<user>/<repo>/settings/secrets/actions"
echo "    2. Нажмите 'New repository secret' и добавьте:"
echo ""
echo "       SSH_HOST = <server-ip>"
echo "       SSH_USER = ubuntu"
echo "       SSH_PORT = 22"
echo ""
echo "    3. Для SSH_PRIVATE_KEY скопируйте содержимое файла ключа:"
echo "       cat ~/.ssh/your-key-name.key | xclip -selection clipboard"
echo "       (или просто откройте файл и скопируйте текст вручную)"
echo ""
echo "    4. Добавьте SSH_PRIVATE_KEY как еще один secret с полным содержимым ключа"
echo ""
echo "4️⃣  На GitHub.com сделайте репозиторий публичным:"
echo "    Settings → General → Danger zone → Change visibility → Public"
echo ""
echo "5️⃣  После первого успешного CI/CD деплоя сделайте образ публичным:"
echo "    Packages → ci-cd-pipeline → Package settings"
echo "    → Change visibility → Public"
echo ""
echo "6️⃣  На локальной машине запушьте в master:"
echo "    git push origin master"
echo ""
echo "    CI/CD GitHub Actions запустится автоматически!"
echo ""
