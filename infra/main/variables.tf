variable "region" {
  type    = string
  default = "us-east-1"
}

variable "agent_image" {
  description = "The agent image by digest: <registry>/sentinel-agent@sha256:..."
  type        = string
  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.agent_image))
    error_message = "agent_image must name the image by digest."
  }
}

variable "boundary_policy_arn" {
  description = "The permissions boundary from the bootstrap stack. Every role here carries it."
  type        = string
}

variable "siem_instance_type" {
  description = "The account's free plan allows only free-tier types; m7i-flex.large is the one with 8 GiB"
  type        = string
  default     = "m7i-flex.large"
}

variable "home_soc_lab_ref" {
  description = "Commit of Keniolax/home-soc-lab whose Wazuh manager and indexer the SIEM runs"
  type        = string
  default     = "34878910c2bb20c212651e645ff39e8ab77e094f"
}

variable "availability_zones" {
  description = "Two zones for the two public subnets, named so the set cannot change under the stack"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}
