
variable "project_id" {
  type        = string
  description = "project id"
  default     = "api-terraform-403712"
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