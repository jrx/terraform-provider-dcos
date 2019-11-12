resource "tls_private_key" "engine_service_account_key" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "dcos_security_org_service_account" "engine_service_account" {
  uid         = "${var.engine_app_id}-principal"
  description = "Kubernets Engine Service Account"
  public_key  = "${tls_private_key.engine_service_account_key.public_key_pem}"
}

locals {
  engine_principal_grants_create = [
    "dcos:mesos:master:reservation:role:${var.engine_app_id}-role",
    "dcos:mesos:master:framework:role:${var.engine_app_id}-role",
    "dcos:mesos:master:task:user:nobody",
  ]
}

resource "dcos_security_org_user_grant" "engine_principal_grants_create" {
  count    = "${length(local.engine_principal_grants_create)}"
  uid      = "${dcos_security_org_service_account.engine_service_account.uid}"
  resource = "${element(local.engine_principal_grants_create, count.index)}"
  action   = "create"
}

locals {
  engine_secret = {
    scheme         = "RS256"
    uid            = "${dcos_security_org_service_account.engine_service_account.uid}"
    private_key    = "${tls_private_key.engine_service_account_key.private_key_pem}"
    login_endpoint = "https://leader.mesos/acs/api/v1/auth/login"
  }
}

resource "dcos_security_secret" "engine-secret" {
  path = "${var.engine_app_id}/secret"
  value = "${jsonencode(local.engine_secret)}"
}

data "dcos_package_version" "engine" {
  name     = "kubernetes"
  version  = "latest"
}

data "dcos_package_config" "engine" {
  version_spec = "${data.dcos_package_version.engine.spec}"
  autotype          = true

  section {
    path = "service"
    map = {
        service_account = "${dcos_security_org_service_account.engine_service_account.uid}"
        service_account_secret = "${dcos_security_secret.engine-secret.path}"
    }
  }
}

resource "dcos_package" "engine" {
  app_id = "${var.engine_app_id}"
  config = "${data.dcos_package_config.engine.config}"

  wait = true
  sdk = true

  depends_on = [
    "dcos_security_org_user_grant.engine_principal_grants_create",
    ]
}
