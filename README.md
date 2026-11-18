# Счётчик в Docker

Для запуска нужны Docker с Docker Compose и `curl`. Исходное приложение находится в [app/](app/). [Условие задания](https://github.com/Nikfilk2030/missing_semester_hse_cs/tree/main/2026/amcs/year_1/hw_3)

## Запуск с Redis

```sh
cp .env.example .env
docker compose up --build -d --wait
curl -fsS http://127.0.0.1:8080/
curl -fsS -X POST http://127.0.0.1:8080/increment
docker compose down
```

| Переменная в `.env` | Назначение |
| --- | --- |
| `APP_PORT` | Порт приложения на компьютере. По умолчанию `8080`. |
| `GREETING` | Поле `greeting` в JSON. По умолчанию `Hello, Docker!`. |

Если поменяли `APP_PORT`, подставьте новый порт в команды `curl`. Приложение публикуется на `127.0.0.1` и соединяется с Redis по адресу `redis://redis:6379/0`. Redis хранит данные в томе `redis-data` и записывает изменения в AOF. Команда `docker compose down` сохраняет том, а `docker compose down -v` его удаляет.

Docker проверяет готовность Redis через `PING`, а готовность приложения через `GET /readyz`. Приложение работает с UID `10001`, корневой файловой системой только для чтения и лимитами 256 MiB RAM и 1 CPU.

## Один контейнер с SQLite (4 балла)

```sh
docker build -t docker-hw:sqlite .
docker run -d --name docker-hw-single -p 127.0.0.1:8080:8000 \
  -e GREETING="Привет из одного контейнера!" docker-hw:sqlite
curl -fsS --retry 10 --retry-delay 1 --retry-all-errors http://127.0.0.1:8080/
curl -fsS -X POST http://127.0.0.1:8080/increment
docker logs docker-hw-single
docker rm -f docker-hw-single
```

## Compose с SQLite (6 баллов)

Вариант `compose.sqlite.yaml` использует тот же `.env` и хранит базу в именованном томе `sqlite-data`.

```sh
docker compose -p docker-hw-sqlite -f compose.sqlite.yaml up --build -d
curl -fsS --retry 10 --retry-delay 1 --retry-all-errors http://127.0.0.1:8080/
curl -fsS -X POST http://127.0.0.1:8080/increment
docker compose -p docker-hw-sqlite -f compose.sqlite.yaml down
docker compose -p docker-hw-sqlite -f compose.sqlite.yaml up -d
curl -fsS --retry 10 --retry-delay 1 --retry-all-errors http://127.0.0.1:8080/
docker compose -p docker-hw-sqlite -f compose.sqlite.yaml down
```

## Проверка восстановления (10 баллов)

```sh
./scripts/check.sh
./scripts/check.sh
```

Скрипт запускает отдельный тестовый проект. Архив Redis остаётся в `backups/<имя-проекта>/redis-data.tar.gz`.

[Отчёт с командами, логами и результатами проверок](REPORT.md)
