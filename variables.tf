variable "deployment_version" {
  type = string
}

variable "name" {
  description = "Name of a Google Cloud Project"
  default     = "cloudroot7-demo"
}

variable "id" {
  description = "ID of a Google Cloud Project. Can be omitted and will be generated automatically"
  default     = "appegine-447812"
}

variable "project_id" {
  type        = string
  description = "project id"
  default     = "appegine-447812"
}

variable "region" {
  type        = string
  description = "Region of policy "
  default     = "us-central1"
}

variable "gcp_service_list" {
  type        = list(string)
  description = "The list of apis necessary for the project"
  default     = []
}