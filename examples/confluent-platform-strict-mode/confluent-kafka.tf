resource "tls_private_key" "kafka_service_account_key" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "dcos_security_org_service_account" "kafka_service_account" {
  uid         = "${var.kafka_app_id}-principal"
  description = "Confluent-Kafka Service Account"
  public_key  = "${tls_private_key.kafka_service_account_key.public_key_pem}"
}

locals {
  kafka_principal_grants_create = [
    "dcos:mesos:master:framework:role:${var.kafka_app_id}-role",
    "dcos:mesos:master:reservation:role:${var.kafka_app_id}-role",
    "dcos:mesos:master:volume:role:${var.kafka_app_id}-role",
    "dcos:mesos:master:task:user:nobody",
  ]
}

resource "dcos_security_org_user_grant" "kafka_principal_grants_create" {
  count    = "${length(local.kafka_principal_grants_create)}"
  uid      = "${dcos_security_org_service_account.kafka_service_account.uid}"
  resource = "${element(local.kafka_principal_grants_create, count.index)}"
  action   = "create"
}

locals {
  kafka_principal_grants_delete = [
    "dcos:mesos:master:reservation:principal:${var.kafka_app_id}-principal",
    "dcos:mesos:master:volume:principal:${var.kafka_app_id}-principal",
  ]
}

resource "dcos_security_org_user_grant" "kafka_principal_grants_delete" {
  count    = "${length(local.kafka_principal_grants_delete)}"
  uid      = "${dcos_security_org_service_account.kafka_service_account.uid}"
  resource = "${element(local.kafka_principal_grants_delete, count.index)}"
  action   = "delete"
}

locals {
  kafka_principal_grants_read = [
    "dcos:secrets:list:default:/${var.kafka_app_id}",
  ]
}

resource "dcos_security_org_user_grant" "kafka_principal_grants_read" {
  count    = "${length(local.kafka_principal_grants_read)}"
  uid      = "${dcos_security_org_service_account.kafka_service_account.uid}"
  resource = "${element(local.kafka_principal_grants_read, count.index)}"
  action   = "read"
}

locals {
  kafka_principal_grants_full = [
    "dcos:secrets:default:/${var.kafka_app_id}/*",
    "dcos:adminrouter:ops:ca:rw",
    "dcos:adminrouter:ops:ca:ro",
    "dcos:superuser",
  ]
}

resource "dcos_security_org_user_grant" "kafka_principal_grants_full" {
  count    = "${length(local.kafka_principal_grants_full)}"
  uid      = "${dcos_security_org_service_account.kafka_service_account.uid}"
  resource = "${element(local.kafka_principal_grants_full, count.index)}"
  action   = "full"
}

locals {
  kafka_secret = {
    scheme         = "RS256"
    uid            = "${dcos_security_org_service_account.kafka_service_account.uid}"
    private_key    = "${tls_private_key.kafka_service_account_key.private_key_pem}"
    login_endpoint = "https://leader.mesos/acs/api/v1/auth/login"
  }
}

resource "dcos_security_secret" "kafka-secret" {
  path = "${var.kafka_app_id}/secret"
  value = "${jsonencode(local.kafka_secret)}"
}

data "dcos_package_version" "kafka" {
  name     = "confluent-kafka"
  version  = "latest"
}

data "dcos_package_config" "kafka" {
  version_spec = "${data.dcos_package_version.kafka.spec}"
  autotype          = true

  section {
    path = "service"
    map = {
      service_account = "${dcos_security_org_service_account.kafka_service_account.uid}"
      service_account_secret = "${dcos_security_secret.kafka-secret.path}"
    }
  }

  section {
    path = "service.security.ssl_authentication"
    map = {
      enabled = "true"
    }
  }

  section {
    path = "service.security.transport_encryption"
    map = {
      enabled = "true"
    }
  }

  section {
    path = "service.security.authorization"
    map = {
      enabled = "true"
      super_users = "User:admin"
      allow_everyone_if_no_acl_found = "true"
    }
  }

  section {
    path = "brokers"
    map = {
      port_tls = 9092
    }
  }

  section {
    path = "kafka"
    map = {
      kafka_zookeeper_uri = "zookeeper-0-server.${var.zookeeper_app_id}.autoip.dcos.thisdcos.directory:1140,zookeeper-1-server.${var.zookeeper_app_id}.autoip.dcos.thisdcos.directory:1140,zookeeper-2-server.${var.zookeeper_app_id}.autoip.dcos.thisdcos.directory:1140"
    }
  }

}

resource "dcos_package" "kafka" {
  app_id = "${var.kafka_app_id}"
  config = "${data.dcos_package_config.kafka.config}"

  wait = true
  sdk = true

  depends_on = [
    "dcos_package.zookeeper",
    "dcos_security_org_user_grant.kafka_principal_grants_create",
    "dcos_security_org_user_grant.kafka_principal_grants_delete",
    "dcos_security_org_user_grant.kafka_principal_grants_read",
    "dcos_security_org_user_grant.kafka_principal_grants_full",
  ]
}