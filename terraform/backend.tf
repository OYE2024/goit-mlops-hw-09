terraform {
  backend "s3" {
    bucket  = "mlops-tfstate-oie"
    key     = "lesson-9/terraform.tfstate"
    region  = "eu-west-1"
    profile = "oie-cli"
  }
}
