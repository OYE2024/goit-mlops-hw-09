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
# ApplicationSet that watches argocd/applications/* in this repository.
#
# Deployed via the argocd-apps chart (not kubernetes_manifest) so that we never
# reference the ApplicationSet CRD before the argo-cd release above has created
# it. depends_on enforces the ordering.
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
        namespace = var.argocd_namespace
        generators = [
          {
            git = {
              repoURL  = var.gitops_repo_url
              revision = var.gitops_repo_revision
              directories = [
                { path = var.gitops_repo_path }
              ]
            }
          }
        ]
        template = {
          metadata = {
            # e.g. app-minio, app-postgres, app-mlflow, app-pushgateway
            name = "app-{{path.basename}}"
          }
          spec = {
            project = "default"
            source = {
              repoURL        = var.gitops_repo_url
              targetRevision = var.gitops_repo_revision
              path           = "{{path}}"
            }
            destination = {
              server    = "https://kubernetes.default.svc"
              namespace = "{{path.basename}}"
            }
            syncPolicy = {
              automated = {
                prune    = true
                selfHeal = true
              }
              syncOptions = [
                "CreateNamespace=true",
                "ApplyOutOfSyncOnly=true"
              ]
            }
          }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
