#!/usr/bin/env python3

import os
import json
import shutil
from pathlib import Path
from datetime import datetime
from typing import Dict, Any

import mlflow
import mlflow.sklearn
import numpy as np
import pandas as pd
from sklearn.datasets import load_iris
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

# Configuration
MLFLOW_TRACKING_URI = os.getenv("MLFLOW_TRACKING_URI", "http://localhost:5000")
PUSHGATEWAY_URL = os.getenv("PUSHGATEWAY_URL", "http://localhost:9091")
EXPERIMENT_NAME = "iris-classification"
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
BEST_MODEL_DIR = PROJECT_ROOT / "best_model"
EXPERIMENT_ARTIFACTS_DIR = SCRIPT_DIR / "best_model"
ALL_RUNS_FILE = EXPERIMENT_ARTIFACTS_DIR / "all_runs.json"
BEST_RUN_FILE = EXPERIMENT_ARTIFACTS_DIR / "best_run.json"

# Hyperparameter configurations to test
HYPERPARAMS = [
    {"C": 0.1, "max_iter": 100, "solver": "lbfgs"},
    {"C": 0.5, "max_iter": 200, "solver": "lbfgs"},
    {"C": 1.0, "max_iter": 200, "solver": "lbfgs"},
    {"C": 1.0, "max_iter": 300, "solver": "saga"},
    {"C": 10.0, "max_iter": 200, "solver": "lbfgs"},
    {"C": 10.0, "max_iter": 300, "solver": "saga"},
]


def setup_mlflow():
    """Initialize MLflow tracking."""
    mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)
    mlflow.set_experiment(EXPERIMENT_NAME)
    print(f"✓ MLflow tracking initialized: {MLFLOW_TRACKING_URI}")


def load_data():
    """Load and prepare Iris dataset."""
    iris = load_iris()
    X = iris.data
    y = iris.target

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.3, random_state=42, stratify=y
    )

    print(f"✓ Data loaded: {X_train.shape[0]} training, {X_test.shape[0]} test samples")
    return X_train, X_test, y_train, y_test


def train_model(X_train, y_train, hyperparams: Dict[str, Any]) -> LogisticRegression:
    """Train LogisticRegression model."""
    model = LogisticRegression(
        C=hyperparams["C"],
        max_iter=hyperparams["max_iter"],
        solver=hyperparams["solver"],
        random_state=42,
        multi_class="multinomial",
    )
    model.fit(X_train, y_train)
    return model


def evaluate_model(model, X_test, y_test) -> Dict[str, float]:
    """Evaluate model and return metrics."""
    y_pred = model.predict(X_test)

    metrics = {
        "accuracy": accuracy_score(y_test, y_pred),
        "precision": precision_score(y_test, y_pred, average="weighted", zero_division=0),
        "recall": recall_score(y_test, y_pred, average="weighted", zero_division=0),
        "f1": f1_score(y_test, y_pred, average="weighted", zero_division=0),
    }

    return metrics


def push_metrics_to_gateway(run_id: str, metrics: Dict[str, float]):
    """Push metrics to PushGateway."""
    try:
        registry = CollectorRegistry()

        accuracy_gauge = Gauge(
            "mlflow_accuracy",
            "MLflow model accuracy",
            ["run_id"],
            registry=registry,
        )
        loss_gauge = Gauge(
            "mlflow_loss",
            "MLflow model loss (1 - accuracy)",
            ["run_id"],
            registry=registry,
        )

        accuracy_gauge.labels(run_id=run_id).set(metrics["accuracy"])
        loss_gauge.labels(run_id=run_id).set(1.0 - metrics["accuracy"])

        push_to_gateway(
            PUSHGATEWAY_URL,
            job="mlflow-experiments",
            registry=registry,
            grouping_key={"run_id": run_id},
        )
        print(f"  ✓ Metrics pushed to PushGateway: {PUSHGATEWAY_URL}")
    except Exception as e:
        print(f"  ⚠ Failed to push to PushGateway: {e}")


def run_experiment(X_train, X_test, y_train, y_test) -> Dict[str, Any]:
    """Run complete experiment with hyperparameter tuning."""
    results = []
    best_run = None
    best_accuracy = 0

    print(f"\n Starting hyperparameter sweep ({len(HYPERPARAMS)} configurations)...\n")

    for idx, hyperparams in enumerate(HYPERPARAMS, 1):
        with mlflow.start_run(run_name=f"iris-run-{idx}"):
            run_id = mlflow.active_run().info.run_id
            print(f"Run {idx}/{len(HYPERPARAMS)} - Run ID: {run_id}")
            print(f"  Hyperparams: {hyperparams}")

            # Log parameters
            for key, value in hyperparams.items():
                mlflow.log_param(key, value)

            # Train model
            model = train_model(X_train, y_train, hyperparams)

            # Evaluate
            metrics = evaluate_model(model, X_test, y_test)

            # Log metrics
            for key, value in metrics.items():
                mlflow.log_metric(key, value)

            # Log model
            mlflow.sklearn.log_model(model, "model", registered_model_name=None)

            # Push to PushGateway
            push_metrics_to_gateway(run_id, metrics)

            print(f"  Accuracy: {metrics['accuracy']:.4f}")
            print(f"  Precision: {metrics['precision']:.4f}")
            print(f"  Recall: {metrics['recall']:.4f}")
            print(f"  F1: {metrics['f1']:.4f}\n")

            # Track results
            result = {
                "run_id": run_id,
                "hyperparams": hyperparams,
                "metrics": metrics,
                "timestamp": datetime.now().isoformat(),
            }
            results.append(result)

            # Update best run
            if metrics["accuracy"] > best_accuracy:
                best_accuracy = metrics["accuracy"]
                best_run = {
                    "run_id": run_id,
                    "accuracy": metrics["accuracy"],
                    "params": hyperparams,
                    "all_metrics": metrics,
                }

    return {
        "all_runs": results,
        "best_run": best_run,
        "total_runs": len(results),
    }


def save_best_model(best_run_info: Dict[str, Any]):
    """Save best model from MLflow to local directories."""
    if not best_run_info:
        print("⚠ No best run found!")
        return

    run_id = best_run_info["run_id"]
    print(f"\n Saving best model (Run ID: {run_id})...")

    # Recreate output directories so only the latest promoted model remains.
    if BEST_MODEL_DIR.exists():
        shutil.rmtree(BEST_MODEL_DIR)
    if EXPERIMENT_ARTIFACTS_DIR.exists():
        shutil.rmtree(EXPERIMENT_ARTIFACTS_DIR)

    BEST_MODEL_DIR.mkdir(parents=True, exist_ok=True)
    EXPERIMENT_ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)

    # Download only the logged model artifact for the best run.
    downloaded_model_path = Path(
        mlflow.artifacts.download_artifacts(
            run_id=run_id,
            artifact_path="model",
            dst_path=str(EXPERIMENT_ARTIFACTS_DIR),
        )
    )

    print(f"  ✓ Model downloaded to: {downloaded_model_path}")

    # Promote the best model to a stable project-level directory.
    for item in downloaded_model_path.iterdir():
        target = BEST_MODEL_DIR / item.name
        if item.is_dir():
            shutil.copytree(item, target)
        else:
            shutil.copy2(item, target)

    print(f"  ✓ Model copied to: {BEST_MODEL_DIR}")


def save_run_metadata(experiment_results: Dict[str, Any]):
    """Save all runs and best run metadata as JSON."""
    EXPERIMENT_ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)

    with open(ALL_RUNS_FILE, "w") as f:
        json.dump(experiment_results["all_runs"], f, indent=2)
    print(f"  ✓ All runs saved to: {ALL_RUNS_FILE}")

    with open(BEST_RUN_FILE, "w") as f:
        json.dump(experiment_results["best_run"], f, indent=2)
    print(f"  ✓ Best run saved to: {BEST_RUN_FILE}")


def print_summary(experiment_results: Dict[str, Any]):
    """Print experiment summary."""
    best = experiment_results["best_run"]

    print("\n" + "=" * 60)
    print("EXPERIMENT SUMMARY")
    print("=" * 60)
    print(f"Total runs: {experiment_results['total_runs']}")
    print(f"\nBest Model:")
    print(f"  Run ID: {best['run_id']}")
    print(f"  Accuracy: {best['accuracy']:.4f}")
    print(f"  Hyperparameters: {best['params']}")
    print(f"\nAll Metrics:")
    for metric, value in best['all_metrics'].items():
        print(f"  {metric}: {value:.4f}")
    print(f"\nModel Location: {BEST_MODEL_DIR}")
    print("=" * 60 + "\n")


def main():
    """Main execution function."""
    print("Starting MLflow Experiment Tracking\n")

    # Setup
    setup_mlflow()

    # Load data
    X_train, X_test, y_train, y_test = load_data()

    # Run experiments
    results = run_experiment(X_train, X_test, y_train, y_test)

    # Save best model
    save_best_model(results["best_run"])

    # Save metadata
    save_run_metadata(results)

    # Print summary
    print_summary(results)

    print("Experiment tracking completed successfully!")


if __name__ == "__main__":
    main()
