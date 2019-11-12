provider "dcos" {}

variable "engine_app_id" {
  default = "kubernetes"
}

variable "cluster_app_id" {
  default = "kubernetes-cluster"
}
