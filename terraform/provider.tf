provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = var.tags
  }
}

# Pull EKS connection details from the lesson-5 EKS remote state so that
# this stack does not depend on a local kubeconfig.
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket  = "mlops-tfstate-oie"
    key     = "eks/terraform.tfstate"
    region  = "eu-west-1"
    profile = "oie-cli"
  }
}

data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
