variable "project" {
  description = "Name of GCP project"
  type        = string
  default     = "team-skeletor-scratchpad"
}

variable "region" {
  description = "GCP region that will be targeted for infrastructure deployment"
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "GCP zone that will be targeted for infrastructure deployment"
  type        = string
  default     = "us-west1-b"
}

variable "user" {
  description = "User name associated with GCP"
  type        = string
  default     = "cas.donoghue"
}

variable "ssh_key" {
  description = "Public ssh key to access GCP VMs"
  type        = string
  default     = "/Users/cas.donoghue/.ssh/id_rsa-gcloud.pub"
}

variable "subnet" {
  description = "The subnet your project is on"
  type        = string
  default     = "team-skeletor-scratchpad"
}

variable "subnet_project" {
  description = "The name of the subnet project"
  type        = string
  default     = "itsysopsnetworking"
}

variable "num_instances" {
  description = "The number of VMs to provision"
  type        = number
  default     = 2
}