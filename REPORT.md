# Отчёт о проверках

## 4 балла. Один контейнер

На порту `18084` приложение ответило с приветствием «Привет из одного контейнера!». Первый GET вернул `0`, после POST счётчик стал `1`. [Команды запуска](README.md#один-контейнер-с-sqlite-4-балла)

```text
2026-11-18 15:49:37,419 listening port=8000 storage=sqlite
2026-11-18 15:49:38,328 http 172.17.0.1 "GET /readyz HTTP/1.1" 200 -
2026-11-18 15:49:38,343 http 172.17.0.1 "GET / HTTP/1.1" 200 -
2026-11-18 15:49:38,354 http 172.17.0.1 "POST /increment HTTP/1.1" 200 -
2026-11-18 15:49:38,362 http 172.17.0.1 "GET / HTTP/1.1" 200 -
```

## 6 баллов. SQLite в Compose

С `APP_PORT=18086` и `--env-file .env.example` два POST дали `count=2`. После `down` и `up -d` контейнер сменился, а счётчик из тома `sqlite-data` остался равен `2`. [Команды запуска](README.md#compose-с-sqlite-6-баллов)

```text
{"greeting": "Привет из Docker!", "count": 2, "hostname": "f8881efb779b", "storage": "sqlite"}
{"greeting": "Привет из Docker!", "count": 2, "hostname": "0a8641f49452", "storage": "sqlite"}
```

## 8 баллов. Redis

```sh
stack() {
  APP_PORT=18088 docker compose -p docker-hw-report-redis --env-file .env.example "$@"
}
stack up --build -d --wait --wait-timeout 60
curl -fsS http://127.0.0.1:18088/
for i in 1 2 3; do curl -fsS -X POST http://127.0.0.1:18088/increment; done
stack down
stack up -d --wait --wait-timeout 60
curl -fsS http://127.0.0.1:18088/
stack ps -q app
stack stop redis
curl --disable -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18088/healthz
curl --disable -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18088/readyz
curl --disable -sS -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:18088/increment
stack start redis
curl -fsS --retry 15 --retry-delay 1 --retry-all-errors http://127.0.0.1:18088/readyz
stack ps -q app
curl -fsS http://127.0.0.1:18088/
curl -fsS -X POST http://127.0.0.1:18088/increment
```

| Проверка | Результат |
| --- | --- |
| Три POST в новом проекте | `count=1`, `2`, `3` |
| GET после `down` и `up -d` | `count=3` |
| После `stop redis` | `GET /healthz` → 200, `GET /readyz` → 503, `POST /increment` → 503 |
| После `start redis` | Тот же контейнер `app`, GET → `3`, POST → `4` |

## 10 баллов. Ограничения и автоматическая проверка

```text
$ stack exec -T app id -u
10001
$ docker inspect --format 'ReadOnlyRootfs={{.HostConfig.ReadonlyRootfs}} Memory={{.HostConfig.Memory}} NanoCpus={{.HostConfig.NanoCpus}}' "$(stack ps -q app)"
ReadOnlyRootfs=true Memory=268435456 NanoCpus=1000000000
$ stack down -v
```

Два запуска подряд.

```text
$ ./scripts/check.sh
Тестовый проект docker-hw-check-44435-1561-20844
GET / → count=0
POST /increment → count=1
POST /increment → count=2
POST /increment → count=3
GET / → count=3
Контейнер app пересоздан, Redis продолжает работать.
GET / → count=3
Redis остановлен.
GET /healthz → HTTP 200
GET /readyz → HTTP 503
POST /increment → HTTP 503
Redis запущен, app продолжает работу в том же процессе.
GET / → count=3
POST /increment → count=4
Резервная копия Redis сохранена в backups/docker-hw-check-44435-1561-20844/redis-data.tar.gz
Тестовый проект и том удалены. Проверка пройдена.

$ ./scripts/check.sh
Тестовый проект docker-hw-check-44580-6897-27778
GET / → count=0
POST /increment → count=1
POST /increment → count=2
POST /increment → count=3
GET / → count=3
Контейнер app пересоздан, Redis продолжает работать.
GET / → count=3
Redis остановлен.
GET /healthz → HTTP 200
GET /readyz → HTTP 503
POST /increment → HTTP 503
Redis запущен, app продолжает работу в том же процессе.
GET / → count=3
POST /increment → count=4
Резервная копия Redis сохранена в backups/docker-hw-check-44580-6897-27778/redis-data.tar.gz
Тестовый проект и том удалены. Проверка пройдена.
```
