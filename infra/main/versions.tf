terraform {
  required_version = "~> 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.71.0"
    }
  }
  # Partial config: `make init` passes the bucket and key that the bootstrap stack made.
  backend "s3" {
    key          = "main.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { lab = "seceng-bootcamp-week-18", project = "sentinel-agent" }
  }
}
