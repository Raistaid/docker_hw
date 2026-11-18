#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

project="docker-hw-check-$$-$RANDOM-$RANDOM"
project_started=0
partial_archive=''
stage='запуск тестового проекта'

compose() {
    APP_PORT=0 docker compose --project-name "$project" --file compose.yaml "$@"
}

cleanup() {
    local status=$?
    if (( status != 0 )); then
        printf 'Ошибка на этапе «%s» (код %s).\n' "$stage" "$status" >&2
    fi
    if (( project_started )) && ! compose down -v --rmi local; then
        printf 'Ошибка при очистке проекта %s.\n' "$project" >&2
        status=1
    fi
    if [[ -n $partial_archive ]]; then
        rm -f -- "$partial_archive"
        rmdir -- "$backup_dir"
    fi
    exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

request() {
    curl --disable --noproxy '*' --silent --show-error --connect-timeout 2 --max-time 5 "$@"
}

wait_ready() {
    local deadline=$((SECONDS + 45))
    until request --fail --output /dev/null "$base_url/readyz" 2>/dev/null; do
        if (( SECONDS >= deadline )); then
            printf 'Тайм-аут ожидания %s/readyz.\n' "$base_url" >&2
            return 1
        fi
        sleep 1
    done
}

check_count() {
    local method=$1 path=$2 expected=$3 body
    body=$(request --fail --request "$method" "$base_url$path")
    printf '%s\n' "$body" | compose exec -T app python -c '
import json
import sys

expected = int(sys.argv[1])
actual = json.load(sys.stdin)["count"]
if type(actual) is not int or actual != expected:
    sys.exit(f"Ожидался count={expected}, получено {actual!r}")
' "$expected"
    printf '%s %s → count=%s\n' "$method" "$path" "$expected"
}

check_status() {
    local method=$1 path=$2 expected=$3 actual
    actual=$(request --request "$method" --output /dev/null --write-out '%{http_code}' "$base_url$path")
    if [[ $actual != "$expected" ]]; then
        printf '%s %s: ожидался HTTP %s, получен %s.\n' "$method" "$path" "$expected" "$actual" >&2
        return 1
    fi
    printf '%s %s → HTTP %s\n' "$method" "$path" "$actual"
}

printf 'Тестовый проект %s\n' "$project"
project_started=1
compose up --build -d --wait --wait-timeout 60
base_url="http://$(compose port app 8000)"
wait_ready

stage='проверка нового счётчика'
check_count GET / 0
n=3
for (( step = 1; step <= n; step++ )); do
    check_count POST /increment "$step"
done
check_count GET / "$n"

stage='пересоздание только app'
app_id=$(compose ps -q app)
redis_id=$(compose ps -q redis)
compose up -d --no-deps --force-recreate --wait --wait-timeout 60 app
[[ $(compose ps -q app) != "$app_id" && $(compose ps -q redis) == "$redis_id" ]]
base_url="http://$(compose port app 8000)"
wait_ready
printf 'Контейнер app пересоздан, Redis продолжает работать.\n'
check_count GET / "$n"

stage='отключение Redis'
app_id=$(compose ps -q app)
app_started=$(docker inspect --format '{{.State.StartedAt}}' "$app_id")
compose stop redis
printf 'Redis остановлен.\n'
check_status GET /healthz 200
check_status GET /readyz 503
check_status POST /increment 503

stage='восстановление соединения с Redis'
compose start redis
wait_ready
[[ $(compose ps -q app) == "$app_id" ]]
[[ $(docker inspect --format '{{.State.StartedAt}}' "$app_id") == "$app_started" ]]
printf 'Redis запущен, app продолжает работу в том же процессе.\n'
check_count GET / "$n"
check_count POST /increment "$((n + 1))"

stage='резервное копирование Redis'
compose stop app
compose stop -t 20 redis
[[ $(docker inspect --format '{{.State.ExitCode}}' "$redis_id") == 0 ]]
mkdir -p backups
backup_dir="backups/$project"
mkdir "$backup_dir"
archive="$backup_dir/redis-data.tar.gz"
partial_archive="$archive.part"
compose run --rm --no-deps -T --user 0:0 --entrypoint tar redis \
    -czf - -C /data . > "$partial_archive"
[[ -s $partial_archive ]]
mv -- "$partial_archive" "$archive"
partial_archive=''
printf 'Резервная копия Redis сохранена в %s\n' "$archive"

stage='удаление тестового проекта и тома'
compose down -v --rmi local
project_started=0
printf 'Тестовый проект и том удалены. Проверка пройдена.\n'
