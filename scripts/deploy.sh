#!/usr/bin/env bash
# Автоматизированная доставка сайта на devops-vm
# Использование: scripts/deploy.sh [--dry-run]

set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="/mnt/c/Users/Данил/devops.crt"

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

# 1. Обработка аргументов
DRY_RUN=false

if [[ $# -gt 1 ]]; then
    echo "Ошибка: слишком много аргументов" >&2
    exit 1
fi

if [[ $# -eq 1 ]]; then
    if [[ "$1" == "--dry-run" ]]; then
        DRY_RUN=true
    else
        echo "Ошибка: неизвестный аргумент $1" >&2
        exit 1
    fi
fi

# 2. Проверка наличия главной страницы
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл site/index.html отсутствует" >&2
    exit 1
fi

# 3. Проверка незакоммиченных изменений
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории имеются незакоммиченные изменения" >&2
    exit 1
fi

# 4. Проверка сертификата
if [[ "$DRY_RUN" == false && ! -f "$CA_CERT" ]]; then
    echo "Ошибка: сертификат не найден: $CA_CERT" >&2
    exit 1
fi

# 5. Параметры rsync
RSYNC_OPTIONS=(
    -avz
    --delete
    --chmod=D755,F644
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5"
)

if [[ "$DRY_RUN" == true ]]; then
    RSYNC_OPTIONS+=(--dry-run)
    echo "Пробный запуск деплоя..."
else
    echo "Начинается доставка сайта..."
fi

# 6. Синхронизация
rsync "${RSYNC_OPTIONS[@]}" \
    "$LOCAL_DIR" \
    "${REMOTE}:${REMOTE_DIR}/"

# 7. Завершение пробного запуска
if [[ "$DRY_RUN" == true ]]; then
    echo "Пробный запуск завершён успешно."
    exit 0
fi

# 8. Проверка HTTPS
echo "Проверка доступности сайта..."

if ! curl --silent --show-error --fail \
    --connect-timeout 5 \
    --max-time 15 \
    --resolve "devops.local:443:192.168.56.101" \
    --cacert "$CA_CERT" \
    --output /dev/null \
    "$SITE_URL"; then

    echo "Ошибка: сайт недоступен по HTTPS" >&2
    exit 1
fi

# 9. Вывод хеша коммита
COMMIT_HASH="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

echo "Деплой успешно завершён."
echo "Коммит: $COMMIT_HASH"

exit 0
