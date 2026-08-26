# MLOps Lesson-9

Мінімальна інструкція для запуску `train_and_push.py`, перевірки сервісів і перегляду метрик.

## 1. Перевірка MLflow, PushGateway, Prometheus і Grafana у кластері

```bash
kubectl get applications -n infra-tools
kubectl get pods -n mlops
kubectl get pods -n monitoring
kubectl get svc -n mlops
kubectl get svc -n monitoring
```

Очікування:
- application `mlflow` у `infra-tools` має бути `Synced/Healthy`
- applications `pushgateway`, `prometheus`, `grafana` у `infra-tools` мають бути `Synced/Healthy`
- pod `mlflow` у `mlops` має бути `Running`
- pod `pushgateway` у `monitoring` має бути `Running`
- pod-и `prometheus-server` і `grafana` у `monitoring` мають бути `Running`
- PushGateway у кластері доступний за адресою `http://pushgateway.monitoring.svc.cluster.local:9091`
- Prometheus у кластері доступний за адресою `http://prometheus-server.monitoring.svc.cluster.local`

## 2. Port-forward

```bash
kubectl port-forward -n mlops svc/mlflow 5000:5000
kubectl port-forward -n monitoring svc/pushgateway 9091:9091
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

## 3. Як запустити train_and_push.py

```bash
cd lesson-9/experiments
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

export MLFLOW_TRACKING_URI=http://localhost:5000
export PUSHGATEWAY_URL=http://localhost:9091

python train_and_push.py
```

Після запуску:
- run-и з’являться в MLflow
- метрики підуть у PushGateway
- найкраща модель буде збережена в `lesson-9/best_model/`
- метадані експериментів будуть у `lesson-9/experiments/best_model/`

## 4. Як подивитись метрики в Grafana

1. Відкрити Grafana: `http://localhost:3000`
2. Перейти в `Explore`
3. Вибрати data source `Prometheus`
4. Виконати один із запитів:

```promql
mlflow_accuracy{run_id=~".*"}
```

```promql
mlflow_loss{run_id=~".*"}
```

## 5. Скриншоти

- Директорія зі скриншотами: [docs](/Users/oie/goit/mlops/lesson-9/docs)
- MLflow UI: додайте файл у `lesson-9/docs/`
- Grafana Explore: додайте файл у `lesson-9/docs/`
