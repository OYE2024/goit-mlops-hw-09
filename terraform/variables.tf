variable "aws_region" {
  description = "AWS region where the EKS cluster lives"
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "oie-cli"
}

variable "argocd_namespace" {
  description = "Namespace where Argo CD is installed"
  type        = string
  default     = "infra-tools"
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart (see https://artifacthub.io/packages/helm/argo/argo-cd)"
  type        = string
  default     = "7.7.11"
}

variable "gitops_repo_url" {
  description = "HTTPS URL of the GitOps repository tracked by the ApplicationSet"
  type        = string
  default     = "https://github.com/OYE2024/goit-mlops-hw-09.git"
}

variable "gitops_repo_revision" {
  description = "Git branch/revision the ApplicationSet tracks"
  type        = string
  default     = "main"
}

variable "gitops_repo_path" {
  description = "Directory glob the ApplicationSet git generator scans (one Application per matched dir)"
  type        = string
  default     = "argocd/applications"
}

variable "tags" {
  description = "Common tags applied to AWS resources"
  type        = map(string)
  default = {
    Environment = "mlops"
    ManagedBy   = "terraform"
    Component   = "argocd"
  }
}
