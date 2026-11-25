variable "subscription_id" {
  description = "The subscription that holds the lab"
  type        = string
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "github_repo" {
  description = "owner/name of the repository whose main branch may deploy"
  type        = string
  default     = "Keniolax/sentinel-agent"
}

# GitHub's OIDC subject names the owner and repository by name and by numeric ID
# (use_immutable_subject). Pinning the IDs means a repository deleted and re-created under
# the same name cannot deploy.
variable "github_owner_id" {
  type    = string
  default = "314053048"
}

variable "github_repo_id" {
  type    = string
  default = "1470747646"
}
