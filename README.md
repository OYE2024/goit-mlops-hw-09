# MLOps Lesson-9: ML Experiment Tracking with MLflow

Comprehensive ML experiment tracking infrastructure with automatic best-model selection, metrics logging to MLflow, and push to Prometheus PushGateway for monitoring in Grafana.

## Architecture

```
lesson-9/
├── terraform/                   # Terraform for ArgoCD deployment
│   ├── main.tf                  # ArgoCD + ApplicationSet
│   ├── provider.tf              # AWS, Kubernetes, Helm providers
│   ├── variables.tf             # Configuration variables
│   ├── outputs.tf               # Outputs (namespace, commands)
│   ├── backend.tf               # S3 state backend
│   ├── terraform.tf             # Version constraints
│   └── values/
│       └── argocd-values.yaml   # ArgoCD Helm chart values
├── argocd/applications/         # ArgoCD Helm Applications
│   ├── minio.yaml               # S3-compatible artifact storage
│   ├── postgres.yaml            # MLflow backend database
│   ├── mlflow.yaml              # MLflow Tracking Server
│   └── pushgateway.yaml         # Prometheus Push Gateway
├── manifests/mlflow/            # Custom MLflow Kubernetes manifests
│   ├── Dockerfile               # Custom MLflow image
│   ├── deployment.yaml          # K8s Deployment + Service
│   ├── secret.yaml              # K8s Secrets
│   └── namespace.yaml           # mlops namespace
├── experiments/                 # Python experiment code
│   ├── train_and_push.py        # Main training & tracking script
│   ├── requirements.txt         # Python dependencies
│   ├── mlflow_local.db          # Auto-generated: local MLflow backend
│   ├── mlruns/                  # Auto-generated: experiment runs storage
│   └── best_model/              # Auto-generated: best model artifacts
├── best_model/                  # Auto-generated: copy of best model
├── .github/workflows/           # GitHub Actions CI/CD
│   └── build.yml                # Docker image build & push to GHCR
└── README.md
```

## Prerequisites

### Required
- **EKS Cluster**: Deployed via lesson-5 (goit-mlops-eks in eu-west-1)
- **Terraform**: >= 1.0 (for deploying ArgoCD in this lesson)
- **kubectl**: Configured for the EKS cluster
- **helm**: >= 3.0 (required by Terraform Helm provider)
- **Python 3.9+**: For running train_and_push.py locally
- **AWS CLI**: Configured with oie-cli profile
- **AWS S3 Bucket**: mlops-tfstate-oie for Terraform state (created during lesson-5)

### Verify Prerequisites
```bash
# Check EKS cluster is running
kubectl cluster-info

# Check Kubernetes connectivity
kubectl get nodes

# Check Terraform version
terraform version

# Check helm version
helm version

# Check Python
python3 --version

# Verify AWS credentials
aws sts get-caller-identity --profile oie-cli
```

## Deployment

### Step 1: Deploy ArgoCD Control Plane

Deploy ArgoCD to the EKS cluster using Terraform:

```bash
# Navigate to lesson-9/terraform
cd lesson-9/terraform

# Initialize Terraform
terraform init

# Review the plan (optional, to see what will be created)
terraform plan

# Apply the configuration
terraform apply

# Confirm by typing 'yes' when prompted
```

Wait 2-3 minutes for ArgoCD to fully start. You can monitor with:

```bash
# Watch ArgoCD pods come up
kubectl get pods -n infra-tools -w

# Wait until all ArgoCD pods show STATUS: Running
# Expected pods: argocd-server, argocd-repo-server, argocd-controller-manager, argocd-dex-server
```

### Step 2: Verify ArgoCD Applications Are Created

Once ArgoCD is running, it will automatically discover and deploy the Applications from `argocd/applications/`:

```bash
# Verify Applications are created
kubectl get applications -n argocd

# Verify ApplicationSet
kubectl get applicationset -n infra-tools
```

Expected output:
```
NAME          SYNC STATUS   HEALTH STATUS
app-minio     Synced        Healthy
app-postgres  Synced        Healthy
app-mlflow    Synced        Healthy
app-pushgateway Synced      Healthy
```

**Note**: If Applications are not yet created, ArgoCD may still be initializing. Wait a few more minutes and check again.

### Step 3: Verify All Services Are Running

```bash
# Check all namespaces and services
kubectl get ns
kubectl get svc -A

# Check specific pods
kubectl get pods -n storage     # minio, postgres
kubectl get pods -n mlops       # mlflow
kubectl get pods -n monitoring  # pushgateway

# Wait for all pods to be Running (may take 2-3 minutes)
kubectl get pods -n storage -w
kubectl get pods -n mlops -w
```

### Step 4: Port-Forward Services

In separate terminal windows, set up port forwarding:

```bash
# Terminal 1: MLflow UI (port 5000)
kubectl port-forward -n mlops svc/mlflow 5000:5000

# Terminal 2: PushGateway (port 9091)
kubectl port-forward -n monitoring svc/pushgateway 9091:9091

# Terminal 3 (optional): MinIO UI (port 9001)
kubectl port-forward -n storage svc/minio 9001:9001

# Terminal 4 (optional): PostgreSQL (port 5432)
kubectl port-forward -n storage svc/postgres-postgresql 5432:5432
```

## Running Experiments

### Local Setup

```bash
# Navigate to experiments directory
cd experiments

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### Set Environment Variables

```bash
# Export MLflow tracking URI
export MLFLOW_TRACKING_URI=http://localhost:5000

# Export PushGateway URL
export PUSHGATEWAY_URL=http://localhost:9091

# Optional: S3 configuration (if using MinIO directly)
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export MLFLOW_S3_ENDPOINT_URL=http://localhost:9000
```

### Run Experiment Script

```bash
# From experiments/ directory
python train_and_push.py
```

The script will:
1. Load Iris dataset
2. Train 6 LogisticRegression models with different hyperparameters
3. Log each run to MLflow with:
   - Hyperparameters (C, max_iter, solver)
   - Metrics (accuracy, precision, recall, F1)
   - Model artifacts
4. Push metrics to Prometheus PushGateway
5. Select best model (highest accuracy)
6. Save best model to `best_model/` directory
7. Generate `all_runs.json` and `best_run.json` metadata

Expected output:
```
✓ MLflow tracking initialized: http://localhost:5000
✓ Data loaded: 105 training, 45 test samples

🔬 Starting hyperparameter sweep (6 configurations)...

Run 1/6 - Run ID: abc123...
  Hyperparams: {'C': 0.1, 'max_iter': 100, 'solver': 'lbfgs'}
  Accuracy: 0.9333
  ...

📦 Saving best model (Run ID: def456...)
  ✓ Model downloaded to: experiments/best_model
  ✓ Model copied to: best_model

✅ Experiment tracking completed successfully!
```

## Verification

### MLflow UI

Open http://localhost:5000 in your browser:

- **Navigation**: Left sidebar shows "iris-classification" experiment
- **Runs**: Each run displays hyperparameters, metrics, and artifacts
- **Artifacts**: Click on a run to download model artifacts
- **Best Run**: Identified by highest accuracy metric

### PushGateway

Open http://localhost:9091 in your browser:

- **Metrics**: Lists all pushed metrics grouped by job (mlflow-experiments)
- **Metrics Format**:
  ```
  mlflow_accuracy{run_id="abc123"} 0.9333
  mlflow_loss{run_id="abc123"} 0.0667
  ```

### Prometheus (if connected to lesson-7 monitoring)

Query in Prometheus UI (http://prometheus.your-domain):

```promql
# Query accuracy metrics
mlflow_accuracy{run_id=~".*"}

# Query loss metrics
mlflow_loss{run_id=~".*"}

# Calculate average accuracy across all runs
avg(mlflow_accuracy)
```

### Grafana (if connected to lesson-7 monitoring)

In Grafana → Explore → Prometheus:

1. Select "Prometheus" datasource
2. Query: `mlflow_accuracy{run_id=~".*"}`
3. Visualize as:
   - Table: Run ID, accuracy value
   - Graph: Accuracy trends
   - Stat: Current average accuracy

## Output Files

### Generated Directories

- **`experiments/best_model/`**: Complete MLflow model artifacts
  - `MLmodel`: Model metadata (format, flavors, signature)
  - `model.pkl`: Pickled scikit-learn model
  - `conda.yaml`: Python environment specification
  - `python_env.yaml`: Direct Python dependencies
  - `all_runs.json`: Metadata for all runs
  - `best_run.json`: Best run details and metrics

- **`best_model/`**: Root-level copy of best model (for easy access)

### Metadata Files

- **`experiments/best_model/all_runs.json`**:
  ```json
  [
    {
      "run_id": "...",
      "hyperparams": {...},
      "metrics": {"accuracy": 0.93, ...},
      "timestamp": "2026-08-23T..."
    }
  ]
  ```

- **`experiments/best_model/best_run.json`**:
  ```json
  {
    "run_id": "...",
    "accuracy": 0.9556,
    "params": {"C": 1.0, ...},
    "all_metrics": {...}
  }
  ```

## Troubleshooting

### MLflow Service Not Starting

```bash
# Check pod status
kubectl describe pod -n mlops -l app=mlflow

# Check logs
kubectl logs -n mlops -l app=mlflow -f

# Common issue: PostgreSQL not ready
# Wait for postgres pod to be Running
kubectl get pods -n storage | grep postgres
```

### Connection Refused to MLflow

```bash
# Verify MLflow pod is running
kubectl get pods -n mlops

# Check if port-forward is active
lsof -i :5000

# Restart port-forward if needed
kubectl port-forward -n mlops svc/mlflow 5000:5000
```

### PushGateway Metrics Not Appearing

```bash
# Verify PushGateway service is accessible
curl http://localhost:9091/metrics

# Check PushGateway pod logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-pushgateway

# Ensure script has correct PUSHGATEWAY_URL
# Default: http://localhost:9091
```

### PostgreSQL Connection Issues

```bash
# Test connection from pod
kubectl exec -n mlops deployment/mlflow -- \
  psql -h postgres.storage.svc.cluster.local -U mlflow -d mlflow

# Check PostgreSQL password in secret
kubectl get secret -n mlops mlflow-secrets -o yaml
```

### MinIO Bucket Not Found

```bash
# Port-forward to MinIO UI
kubectl port-forward -n storage svc/minio 9001:9001

# Access UI at http://localhost:9001
# Default credentials: minioadmin / minioadmin
# Create bucket "mlflow-artifacts" if missing

# Or create via MinIO CLI
mc alias set local http://localhost:9000 minioadmin minioadmin
mc mb local/mlflow-artifacts
```

## Advanced Usage

### Custom Hyperparameters

Edit `experiments/train_and_push.py` - modify `HYPERPARAMS` list:

```python
HYPERPARAMS = [
    {"C": 0.01, "max_iter": 150, "solver": "lbfgs"},
    {"C": 5.0, "max_iter": 250, "solver": "saga"},
    # Add more configurations
]
```

### Using S3 Instead of MinIO

Update MLflow Deployment environment variables:

```yaml
env:
- name: MLFLOW_S3_ENDPOINT_URL
  value: "https://s3.eu-west-1.amazonaws.com"
- name: AWS_DEFAULT_REGION
  value: "eu-west-1"
```

### Experiment Retention

Clean up old runs to save storage:

```bash
# Delete specific run
mlflow runs delete <run_id>

# Clear all experiments (caution!)
mlflow gc --backend-store-uri postgresql://... --artifact-uri s3://...
```

## Performance Considerations

- **MinIO**: 10Gi storage by default (sufficient for hundreds of small models)
- **PostgreSQL**: 10Gi storage (tracks run metadata, not model artifacts)
- **MLflow Pod**: 500m CPU, 1Gi RAM limits
- **PushGateway**: No persistence (metrics reset on pod restart)

For production:
- Increase storage sizes in ArgoCD Applications
- Enable high-availability for PostgreSQL
- Use managed AWS S3 instead of MinIO
- Integrate with persistent monitoring (Prometheus with retention)

## Project Structure Summary

| Component | Location | Purpose |
|-----------|----------|---------|
| ArgoCD Apps | `argocd/applications/` | Infrastructure as Code |
| MLflow K8s | `manifests/mlflow/` | Custom deployment |
| Training Script | `experiments/train_and_push.py` | ML experiment tracking |
| Best Model | `best_model/` | Production-ready model |
| Metadata | `experiments/best_model/` | Run tracking & metadata |
| Dependencies | `experiments/requirements.txt` | Python packages |

## Integration with lesson-5

- **lesson-5**: Provides EKS cluster (goit-mlops-eks) with Terraform state stored in S3
- **lesson-9**: Deploys ArgoCD control plane + ML applications on top of the EKS cluster

Integration:
- **Terraform State**: lesson-9 reads lesson-5's remote state to get EKS cluster details
- **Kubernetes API**: Terraform providers (Kubernetes, Helm) connect to EKS using the cluster endpoint
- **ApplicationSet**: ArgoCD automatically discovers and deploys Applications from `argocd/applications/`

## References

- MLflow Documentation: https://mlflow.org/docs/latest/
- MLflow Tracking: https://mlflow.org/docs/latest/tracking/
- Prometheus PushGateway: https://github.com/prometheus/pushgateway
- MinIO Kubernetes: https://docs.min.io/docs/minio-kubernetes-operator.html
- ArgoCD Applications: https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/

## Success Checklist

- [ ] All 4 services deployed and Running
- [ ] MLflow UI accessible at http://localhost:5000
- [ ] PushGateway accessible at http://localhost:9091
- [ ] `train_and_push.py` runs without errors
- [ ] 6 runs visible in MLflow UI
- [ ] Metrics pushed to PushGateway
- [ ] Best model saved in `best_model/` directory
- [ ] Metrics queryable in Prometheus/Grafana
- [ ] `all_runs.json` and `best_run.json` generated

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Review pod logs: `kubectl logs -n <namespace> <pod-name>`
3. Verify network connectivity: `kubectl exec <pod> -- curl <service>`
4. Check resource quotas: `kubectl describe node`

---

**Last Updated**: 2026-08-23
**Status**: Production Ready ✅
