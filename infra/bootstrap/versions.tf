terraform {
  required_version = "~> 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.71.0"
    }
  }
  # Local state: this stack makes the bucket that holds the main stack's state. An admin
  # applies it once. Every resource carries the lab tag, so a lost state file can still be
  # cleaned up by hand.
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { lab = "seceng-bootcamp-week-18", project = "sentinel-agent" }
  }
}
