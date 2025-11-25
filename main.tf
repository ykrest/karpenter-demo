locals {
  name   = var.cluster_name
  region = var.region

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

data "aws_caller_identity" "current" {}
# Separate provider for us-east-1 (required for ECR public)
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}
