FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && groupadd --gid 10001 app \
    && useradd --uid 10001 --gid 10001 --no-create-home app \
    && install -d -o app -g app /data

COPY app/app.py .
USER 10001:10001
EXPOSE 8000
STOPSIGNAL SIGINT
CMD ["python", "app.py"]
