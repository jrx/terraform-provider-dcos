provider "dcos" {}

variable "zookeeper_app_id" {
  default = "confluent-zookeeper"
}

variable "kafka_app_id" {
  default = "confluent-kafka"
}