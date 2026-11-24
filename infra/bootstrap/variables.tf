variable "region" {
  type    = string
  default = "us-east-1"
}

variable "github_repo" {
  description = "owner/name of the repository whose main branch may deploy"
  type        = string
  default     = "Keniolax/sentinel-agent"
}
