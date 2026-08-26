FROM python:3.11-slim                    # ← Base image з Python 3.11 (slim = легкіша, менший розмір)

WORKDIR /app                             # ← Робоча директорія всередину контейнера

# ← Установка системних пакетів (PostgreSQL client для підключення до БД)
RUN apt-get update && apt-get install -y \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# ← Установка Python пакетів:
#   • mlflow==2.10.2 - Tracking Server
#   • boto3==1.28.85 - AWS S3 SDK для артефактів
#   • psycopg2-binary==2.9.9 - PostgreSQL драйвер
#   • prometheus-client==0.19.0 - Prometheus метрики
#   • gunicorn==21.2.0 - WSGI сервер
#   • waitress==2.1.2 - WSGI сервер (запасний)
RUN pip install --no-cache-dir \
    mlflow==2.10.2 \
    boto3==1.28.85 \
    psycopg2-binary==2.9.9 \
    prometheus-client==0.19.0 \
    gunicorn==21.2.0 \
    waitress==2.1.2

# ← Port 5000 для MLflow UI та API
EXPOSE 5000

# ← Runtime конфігурація приходить з Kubernetes env vars, тому один і той самий
#    образ можна використовувати в різних середовищах без rebuild.
CMD ["sh", "-ec", "exec mlflow server --backend-store-uri \"$MLFLOW_BACKEND_STORE_URI\" --default-artifact-root \"$MLFLOW_ARTIFACT_ROOT\" --host \"${MLFLOW_HOST:-0.0.0.0}\" --port \"${MLFLOW_PORT:-5000}\""]
