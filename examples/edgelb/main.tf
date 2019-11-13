provider "dcos" {}

resource "tls_private_key" "edgelb_service_account_private_key" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "dcos_security_org_service_account" "edgelb_service_account" {
  uid         = "edgelb-principal"
  description = "Edge-LB service account"
  public_key  = "${tls_private_key.edgelb_service_account_private_key.public_key_pem}"
}

locals {
  edgelb_principal_grants = [
    "dcos:adminrouter:ops:ca:rw",
    "dcos:adminrouter:ops:ca:ro",
    "dcos:adminrouter:service:marathon",
    "dcos:adminrouter:package",
    "dcos:adminrouter:service:edgelb",
    "dcos:service:marathon:marathon:services:/dcos-edgelb",
    "dcos:mesos:master:endpoint:path:/api/v1",
    "dcos:mesos:master:endpoint:path:/api/v1/scheduler",
    "dcos:mesos:master:framework:principal:edgelb",
    "dcos:mesos:master:framework:role",
    "dcos:mesos:master:reservation:principal:edgelb",
    "dcos:mesos:master:reservation:role",
    "dcos:mesos:master:volume:principal:edgelb",
    "dcos:mesos:master:volume:role",
    "dcos:mesos:master:task:user:root",
    "dcos:mesos:master:task:app_id",
    "dcos:secrets:default:/dcos-edgelb/*",
    "dcos:secrets:list:default:/dcos-edgelb/*",
    "dcos:adminrouter:service:dcos-edgelb/pools/auto-default",
  ]
}

resource "dcos_security_org_user_grant" "edgelb" {
  count    = "${length(local.edgelb_principal_grants)}"
  uid      = "${dcos_security_org_service_account.edgelb_service_account.uid}"
  resource = "${element(local.edgelb_principal_grants, count.index)}"
  action   = "full"
}

locals {
  edgelb_secret = {
    scheme         = "RS256"
    uid            = "${dcos_security_org_service_account.edgelb_service_account.uid}"
    private_key    = "${tls_private_key.edgelb_service_account_private_key.private_key_pem}"
    login_endpoint = "https://leader.mesos/acs/api/v1/auth/login"
  }
}

resource "dcos_security_secret" "edgelb-secret" {
  path = "dcos-edgelb/secret"

  value = "${jsonencode(local.edgelb_secret)}"
}

resource "dcos_package_repo" "edgelb" {
  name = "edgelb"
  url  = "https://downloads.mesosphere.com/edgelb/v1.5.0/assets/stub-universe-edgelb.json"
}

resource "dcos_package_repo" "edgelb-pool" {
  name = "edgelb-pool"
  url  = "https://downloads.mesosphere.com/edgelb-pool/v1.5.0/assets/stub-universe-edgelb-pool.json"
}

data "dcos_package_version" "edgelb" {
  repo_url = "${dcos_package_repo.edgelb.url}"
  name     = "edgelb"
}

data "dcos_package_config" "edgelb" {
  version_spec = "${data.dcos_package_version.edgelb.spec}"

  section {
    path = "service"

    map {
      name = ""
      secretName    = "${dcos_security_secret.edgelb-secret.path}"
      principal     = "${dcos_security_org_service_account.edgelb_service_account.uid}"
      mesosProtocol = "https"
      mesosAuthNZ = "true"
      logLevel = "info"
    }
  }
}

resource "dcos_package" "edgelb" {
  app_id = "dcos-edgelb/api"
  config = "${data.dcos_package_config.edgelb.config}"

  wait = true
}

resource "dcos_marathon_app" "edgelb-ping" {
  app_id    = "/ping"
  cpus      = 0.1
  mem       = 32
  instances = 1

  cmd = <<EOF
echo "pong" > index.html && python -m http.server $PORT0
EOF

  container {
    type = "DOCKER"

    docker {
      image = "python:3"
    }
  }

  health_checks {
    path                     = "/"
    protocol                 = "MESOS_HTTP"
    port_index               = 0
    grace_period_seconds     = 5
    interval_seconds         = 10
    timeout_seconds          = 10
    max_consecutive_failures = 3
  }

  port_definitions {
    protocol = "tcp"
    port     = 0
    name     = "pong-port"
  }

  require_ports = true
}

locals {
  edgelb_principal_grants_ping = [
    "dcos:adminrouter:service:dcos-edgelb/pools/ping-lb",
  ]
}

resource "dcos_security_org_user_grant" "edgelb-pool-ping" {
  count    = "${length(local.edgelb_principal_grants_ping)}"
  uid      = "${dcos_security_org_service_account.edgelb_service_account.uid}"
  resource = "${element(local.edgelb_principal_grants_ping, count.index)}"
  action   = "full"
}

resource "dcos_edgelb_v2_pool" "edgelb-ping" {
  name       = "ping-lb"
  namespace  = "edgelb"
  pool_count = 1
  mem        = 128

  haproxy_frontends {
    bind_port = 80
    protocol  = "HTTP"

    linked_backend_default_backend = "ping-backend"
  }

  haproxy_backends {
    name     = "ping-backend"
    protocol = "HTTP"

    services {
      marathon_service_id = "/ping"
      endpoint_port_name  = "pong-port"
    }
  }

  depends_on = [
    "dcos_package.edgelb",
    "dcos_security_org_user_grant.edgelb-pool-ping", "dcos_marathon_app.edgelb-ping",
  ]
}
