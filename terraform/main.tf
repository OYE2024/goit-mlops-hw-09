# ---------------------------------------------------------------------------
# External Secrets Operator IAM role for AWS Secrets Manager access via IRSA
# ---------------------------------------------------------------------------
resource "random_password" "minio_root" {
  length  = 32
  special = false
}

resource "random_password" "postgres_user" {
  length  = 32
  special = false
}

resource "random_password" "postgres_admin" {
  length  = 32
  special = false
}

resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "minio" {
  name = "lesson-9/minio"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "minio" {
  secret_id = aws_secretsmanager_secret.minio.id
  secret_string = jsonencode({
    rootUser     = "minioadmin"
    rootPassword = random_password.minio_root.result
  })
}

resource "aws_secretsmanager_secret" "postgres" {
  name = "lesson-9/postgres"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id = aws_secretsmanager_secret.postgres.id
  secret_string = jsonencode({
    password            = random_password.postgres_user.result
    "postgres-password" = random_password.postgres_admin.result
  })
}

resource "aws_secretsmanager_secret" "mlflow" {
  name = "lesson-9/mlflow"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "mlflow" {
  secret_id = aws_secretsmanager_secret.mlflow.id
  secret_string = jsonencode({
    MLFLOW_AWS_ACCESS_KEY_ID     = "minioadmin"
    MLFLOW_AWS_SECRET_ACCESS_KEY = random_password.minio_root.result
    MLFLOW_S3_ENDPOINT_URL       = "http://minio.storage.svc.cluster.local:9000"
    MLFLOW_BACKEND_STORE_URI     = "postgresql://mlflow:${random_password.postgres_user.result}@postgres-postgresql.storage.svc.cluster.local:5432/mlflow"
    MLFLOW_ARTIFACT_ROOT         = "s3://mlflow-artifacts"
  })
}

resource "aws_secretsmanager_secret" "grafana" {
  name = "lesson-9/grafana"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id = aws_secretsmanager_secret.grafana.id
  secret_string = jsonencode({
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin.result
  })
}

data "aws_iam_policy_document" "external_secrets_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.this.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.this.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.external_secrets_namespace}:external-secrets"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.this.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${data.terraform_remote_state.eks.outputs.cluster_name}-external-secrets-role"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume_role.json

  tags = var.tags
}

data "aws_iam_policy_document" "external_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds"
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:*:secret:lesson-9/minio*",
      "arn:aws:secretsmanager:${var.aws_region}:*:secret:lesson-9/postgres*",
      "arn:aws:secretsmanager:${var.aws_region}:*:secret:lesson-9/mlflow*",
      "arn:aws:secretsmanager:${var.aws_region}:*:secret:lesson-9/grafana*"
    ]
  }
}

resource "aws_iam_policy" "external_secrets" {
  name   = "${data.terraform_remote_state.eks.outputs.cluster_name}-external-secrets-policy"
  policy = data.aws_iam_policy_document.external_secrets.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

# ---------------------------------------------------------------------------
# External Secrets Operator
# ---------------------------------------------------------------------------
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = var.external_secrets_namespace
  create_namespace = true

  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "2.8.0"

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      create = true
      name   = "external-secrets"
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets.arn
      }
    }
  })]

  depends_on = [aws_iam_role_policy_attachment.external_secrets]
}

resource "kubernetes_namespace_v1" "storage" {
  metadata {
    name = "storage"
  }
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_manifest" "storage_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"
    metadata = {
      name      = "aws-secretsmanager"
      namespace = kubernetes_namespace_v1.storage.metadata[0].name
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
        }
      }
    }
  }

  depends_on = [helm_release.external_secrets]
}

resource "kubernetes_manifest" "minio_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "minio-root-credentials"
      namespace = kubernetes_namespace_v1.storage.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = kubernetes_manifest.storage_secret_store.manifest.metadata.name
        kind = "SecretStore"
      }
      target = {
        name           = "minio-root-credentials"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "rootUser"
          remoteRef = {
            key      = aws_secretsmanager_secret.minio.name
            property = "rootUser"
          }
        },
        {
          secretKey = "rootPassword"
          remoteRef = {
            key      = aws_secretsmanager_secret.minio.name
            property = "rootPassword"
          }
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.storage_secret_store,
    aws_secretsmanager_secret_version.minio
  ]
}

resource "kubernetes_manifest" "postgres_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "postgres-auth"
      namespace = kubernetes_namespace_v1.storage.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = kubernetes_manifest.storage_secret_store.manifest.metadata.name
        kind = "SecretStore"
      }
      target = {
        name           = "postgres-auth"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "password"
          remoteRef = {
            key      = aws_secretsmanager_secret.postgres.name
            property = "password"
          }
        },
        {
          secretKey = "postgres-password"
          remoteRef = {
            key      = aws_secretsmanager_secret.postgres.name
            property = "postgres-password"
          }
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.storage_secret_store,
    aws_secretsmanager_secret_version.postgres
  ]
}

resource "kubernetes_manifest" "monitoring_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"
    metadata = {
      name      = "aws-secretsmanager"
      namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
        }
      }
    }
  }

  depends_on = [helm_release.external_secrets]
}

resource "kubernetes_manifest" "grafana_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "grafana-admin-credentials"
      namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = kubernetes_manifest.monitoring_secret_store.manifest.metadata.name
        kind = "SecretStore"
      }
      target = {
        name           = "grafana-admin-credentials"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "admin-user"
          remoteRef = {
            key      = aws_secretsmanager_secret.grafana.name
            property = "admin-user"
          }
        },
        {
          secretKey = "admin-password"
          remoteRef = {
            key      = aws_secretsmanager_secret.grafana.name
            property = "admin-password"
          }
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.monitoring_secret_store,
    aws_secretsmanager_secret_version.grafana
  ]
}

# ---------------------------------------------------------------------------
# Argo CD control plane (Helm release)
# ---------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.argocd_namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  # All chart tuning lives in the values file (ClusterIP, extraArgs, rbac, timeouts).
  values = [file("${path.module}/values/argocd-values.yaml")]

  # Give the CRDs and controllers time to become ready before the
  # ApplicationSet release is applied.
  wait          = true
  wait_for_jobs = true
  timeout       = 900
}

# ---------------------------------------------------------------------------
# ApplicationSet that watches Application manifests in argocd/applications/*.yaml.
#
# Deployed via the argocd-apps chart (not kubernetes_manifest) so that we never
# reference the ApplicationSet CRD before the argo-cd release above has created
# it. depends_on enforces the ordering.
# Each matched YAML file is parsed and used as the source of truth for one
# generated child Application.
# ---------------------------------------------------------------------------
resource "helm_release" "argocd_apps" {
  name      = "argocd-apps"
  namespace = var.argocd_namespace

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.2"

  values = [yamlencode({
    applicationsets = {
      applications = {
        namespace         = var.argocd_namespace
        goTemplate        = true
        goTemplateOptions = ["missingkey=error"]
        generators = [
          {
            git = {
              repoURL  = var.gitops_repo_url
              revision = var.gitops_repo_revision
              files = [
                { path = var.gitops_repo_path }
              ]
            }
          }
        ]
        template = {
          metadata = {
            name      = "{{ .metadata.name }}"
            namespace = var.argocd_namespace
          }
          spec = {
            project = "default"
            source = {
              repoURL        = "https://invalid.example.com/placeholder.git"
              targetRevision = "HEAD"
              path           = "."
            }
            destination = {
              server    = "https://kubernetes.default.svc"
              namespace = "default"
            }
          }
        }
        templatePatch = <<-EOT
          spec:
          {{ toYaml .spec | nindent 4 }}
        EOT
      }
    }
  })]

  depends_on = [
    helm_release.argocd,
    helm_release.external_secrets,
    kubernetes_manifest.minio_external_secret,
    kubernetes_manifest.postgres_external_secret,
    kubernetes_manifest.grafana_external_secret
  ]
}
