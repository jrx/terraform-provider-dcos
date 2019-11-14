resource "tls_private_key" "zookeeper_service_account_key" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "dcos_security_org_service_account" "zookeeper_service_account" {
  uid         = "${var.zookeeper_app_id}-principal"
  description = "ZooKeeper Service Account"
  public_key  = "${tls_private_key.zookeeper_service_account_key.public_key_pem}"
}

locals {
  zookeeper_principal_grants_create = [
    "dcos:mesos:master:framework:role:${var.zookeeper_app_id}-role",
    "dcos:mesos:master:reservation:role:${var.zookeeper_app_id}-role",
    "dcos:mesos:master:volume:role:${var.zookeeper_app_id}-role",
    "dcos:mesos:master:task:user:nobody",
  ]
}

resource "dcos_security_org_user_grant" "zookeeper_principal_grants_create" {
  count    = "${length(local.zookeeper_principal_grants_create)}"
  uid      = "${dcos_security_org_service_account.zookeeper_service_account.uid}"
  resource = "${element(local.zookeeper_principal_grants_create, count.index)}"
  action   = "create"
}

locals {
  zookeeper_principal_grants_delete = [
    "dcos:mesos:master:reservation:principal:${var.zookeeper_app_id}-principal",
    "dcos:mesos:master:volume:principal:${var.zookeeper_app_id}-principal",
  ]
}

resource "dcos_security_org_user_grant" "zookeeper_principal_grants_delete" {
  count    = "${length(local.zookeeper_principal_grants_delete)}"
  uid      = "${dcos_security_org_service_account.zookeeper_service_account.uid}"
  resource = "${element(local.zookeeper_principal_grants_delete, count.index)}"
  action   = "delete"
}

locals {
  zookeeper_secret = {
    scheme         = "RS256"
    uid            = "${dcos_security_org_service_account.zookeeper_service_account.uid}"
    private_key    = "${tls_private_key.zookeeper_service_account_key.private_key_pem}"
    login_endpoint = "https://leader.mesos/acs/api/v1/auth/login"
  }
}

resource "dcos_security_secret" "zookeeper-secret" {
  path = "${var.zookeeper_app_id}/secret"
  value = "${jsonencode(local.zookeeper_secret)}"
}

data "dcos_package_version" "zookeeper" {
  name     = "confluent-zookeeper"
  version  = "latest"
}

data "dcos_package_config" "zookeeper" {
  version_spec = "${data.dcos_package_version.zookeeper.spec}"
  autotype          = true

  section {
    path = "service"
    map = {
        service_account = "${dcos_security_org_service_account.zookeeper_service_account.uid}"
        service_account_secret = "${dcos_security_secret.zookeeper-secret.path}"
    }
  }
}

resource "dcos_package" "zookeeper" {
  app_id = "${var.zookeeper_app_id}"
  config = "${data.dcos_package_config.zookeeper.config}"

  wait = true
  sdk = true

  depends_on = [
    "dcos_security_org_user_grant.zookeeper_principal_grants_create",
    "dcos_security_org_user_grant.zookeeper_principal_grants_delete",
  ]
}