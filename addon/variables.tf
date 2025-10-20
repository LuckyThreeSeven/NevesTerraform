data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "../infra/terraform.tfstate"
  }
}

data "aws_eks_cluster_auth" "cluster" {
  name = data.terraform_remote_state.infra.outputs.eks_cluster_name
}

variable "domain_name" {
  description = "domain name"
  type = string
  nullable = false
}

variable "aws_access_key" {
  description   = "aws access key"
  type          = string
  nullable      = false
  sensitive     = true
}

variable "aws_secret_key" {
  description   = "aws secret key"
  type          = string
  nullable      = false
  sensitive     = true
}
