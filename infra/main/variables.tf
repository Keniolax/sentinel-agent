variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "lab_resource_group" {
  description = "The empty group the bootstrap stack made for this stack"
  type        = string
  default     = "rg-sentinel-lab"
}

variable "agent_image" {
  description = "The agent image by digest: <registry>/sentinel-agent@sha256:..."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]+\\.azurecr\\.io/sentinel-agent@sha256:[0-9a-f]{64}$", var.agent_image))
    error_message = "agent_image must name the sentinel-agent image in an Azure registry by digest."
  }
}

variable "acr_id" {
  description = "Resource ID of the bootstrap stack's registry; the job's identity gets AcrPull on it"
  type        = string
}

variable "network_watcher_name" {
  description = "The bootstrap stack's Network Watcher in the lab group"
  type        = string
}

variable "siem_vm_size" {
  description = "Wazuh's indexer and manager need about 8 GB of memory"
  type        = string
  default     = "Standard_B2ms"
}

variable "home_soc_lab_ref" {
  description = "Commit of Keniolax/home-soc-lab whose Wazuh manager and indexer the SIEM runs"
  type        = string
  default     = "34878910c2bb20c212651e645ff39e8ab77e094f"
}
