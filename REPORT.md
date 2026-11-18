# Отчёт о проверках

Проверки выполнены на Docker Engine 29.10.0 с Docker Compose v5.8.0.

## 4 балла. Один контейнер

```sh
docker build -t docker-hw:sqlite .
docker run -d --name docker-hw-single -p 127.0.0.1:18084:8000 \
  -e GREETING="Привет из одного контейнера!" docker-hw:sqlite
curl -fsS --retry 10 --retry-delay 1 --retry-all-errors http://127.0.0.1:18084/readyz
curl -fsS http://127.0.0.1:18084/
curl -fsS -X POST http://127.0.0.1:18084/increment
curl -fsS http://127.0.0.1:18084/
docker logs docker-hw-single
docker rm -f docker-hw-single
```

Первый `GET /` вернул `count=0`. POST увеличил его до `1`, и следующий GET вернул `1`. В ответах было приветствие «Привет из одного контейнера!».

```text
2026-11-18 15:49:37,419 listening port=8000 storage=sqlite
2026-11-18 15:49:38,328 http 172.17.0.1 "GET /readyz HTTP/1.1" 200 -
2026-11-18 15:49:38,343 http 172.17.0.1 "GET / HTTP/1.1" 200 -
2026-11-18 15:49:38,354 http 172.17.0.1 "POST /increment HTTP/1.1" 200 -
2026-11-18 15:49:38,362 http 172.17.0.1 "GET / HTTP/1.1" 200 -
```

## 6 баллов. Сохранение данных SQLite

```sh
sqlite() {
  APP_PORT=18086 docker compose -p docker-hw-report-sqlite \
    --env-file .env.example -f compose.sqlite.yaml "$@"
}
sqlite up --build -d
curl -fsS --retry 10 --retry-delay 1 --retry-all-errors http://127.0.0.1:18086/
curl -fsS -X POST http://127.0.0.1:18086/increment
curl -fsS -X POST http://127.0.0.1:18086/increment
sqlite down
sqlite up -d
curl -fsS --retry 10 --retry-delay 1 --retry-all-errors http://127.0.0.1:18086/
sqlite down -v
```

Приложение ответило на порту `18086` с приветствием «Привет из Docker!» из `.env.example`. Счётчик прошёл `0 → 1 → 2`. После `down` и `up -d` изменился `hostname`, а `count` остался равен `2`.

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
stack stop redis
curl --disable -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18088/healthz
curl --disable -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18088/readyz
curl --disable -sS -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:18088/increment
stack start redis
curl -fsS --retry 15 --retry-delay 1 --retry-all-errors http://127.0.0.1:18088/readyz
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

Проверка ограничений в уже запущенном стеке Redis.

```text
$ stack exec -T app id -u
10001
$ docker inspect --format 'ReadOnlyRootfs={{.HostConfig.ReadonlyRootfs}} Memory={{.HostConfig.Memory}} NanoCpus={{.HostConfig.NanoCpus}}' "$(stack ps -q app)"
ReadOnlyRootfs=true Memory=268435456 NanoCpus=1000000000
$ stack down -v
```

Вывод проверок из двух последовательных запусков.

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

После обоих запусков проверил, что Docker удалил контейнеры, сеть, том и образ приложения каждого тестового проекта. Распаковал второй архив в новый том и запустил Redis с AOF. Команда `redis-cli GET docker-hw:counter` вернула `4`. При имитации сбоя на этапе запуска скрипт вывел название этапа, завершился с кодом `42` и удалил ресурсы тестового проекта.

При повторной проверке скрипт также прошёл на Docker Compose v2.40.3. Во всех трёх прогонах был задан `.curlrc` с опцией `fail`. Параллельно на порту `8080` работал обычный проект с отдельным томом. Healthcheck приложения оставался успешным при недоступном HTTP-прокси, заданном в контейнере. После тестов контейнеры обычного проекта и значение его счётчика `1` сохранились.
