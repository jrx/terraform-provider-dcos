resource "tls_private_key" "cluster_service_account_key" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "dcos_security_org_service_account" "cluster_service_account" {
  uid         = "${var.cluster_app_id}-principal"
  description = "Kubernets Cluster Service Account"
  public_key  = "${tls_private_key.cluster_service_account_key.public_key_pem}"
}

locals {
  cluster_principal_grants_create = [
    "dcos:mesos:master:framework:role:${var.cluster_app_id}-role",
    "dcos:mesos:master:task:user:root",
    "dcos:mesos:agent:task:user:root",
    "dcos:mesos:master:reservation:role:${var.cluster_app_id}-role",
    "dcos:mesos:master:volume:role:${var.cluster_app_id}-role",
    "dcos:service:marathon:marathon:services:/",
    "dcos:mesos:master:framework:role:slave_public/${var.cluster_app_id}-role",
    "dcos:mesos:master:reservation:role:slave_public/${var.cluster_app_id}-role",
    "dcos:mesos:master:volume:role:slave_public/${var.cluster_app_id}-role",
  ]
}

locals {
  cluster_principal_grants_read = [
    "dcos:secrets:list:default:/${var.cluster_app_id}",
    "dcos:mesos:master:framework:role:*",
    "dcos:mesos:master:framework:role:slave_public/${var.cluster_app_id}-role",
    "dcos:mesos:master:framework:role:slave_public",
    "dcos:mesos:agent:framework:role:slave_public",
  ]
}

locals {
  cluster_principal_grants_delete = [
    "dcos:mesos:master:reservation:principal:${var.cluster_app_id}",
    "dcos:mesos:master:volume:principal:${var.cluster_app_id}",
    "dcos:service:marathon:marathon:services:/",
  ]
}

locals {
  cluster_principal_grants_full = [
    "dcos:secrets:default:/${var.cluster_app_id}/*",
    "dcos:adminrouter:ops:ca:rw",
    "dcos:adminrouter:ops:ca:ro",
  ]
}

resource "dcos_security_org_user_grant" "cluster_principal_grants_create" {
  count    = "${length(local.cluster_principal_grants_create)}"
  uid      = "${dcos_security_org_service_account.cluster_service_account.uid}"
  resource = "${element(local.cluster_principal_grants_create, count.index)}"
  action   = "create"
}

resource "dcos_security_org_user_grant" "cluster_principal_grants_read" {
  count    = "${length(local.cluster_principal_grants_read)}"
  uid      = "${dcos_security_org_service_account.cluster_service_account.uid}"
  resource = "${element(local.cluster_principal_grants_read, count.index)}"
  action   = "read"
}

resource "dcos_security_org_user_grant" "cluster_principal_grants_delete" {
  count    = "${length(local.cluster_principal_grants_delete)}"
  uid      = "${dcos_security_org_service_account.cluster_service_account.uid}"
  resource = "${element(local.cluster_principal_grants_delete, count.index)}"
  action   = "delete"
}

resource "dcos_security_org_user_grant" "cluster_principal_grants_full" {
  count    = "${length(local.cluster_principal_grants_full)}"
  uid      = "${dcos_security_org_service_account.cluster_service_account.uid}"
  resource = "${element(local.cluster_principal_grants_full, count.index)}"
  action   = "full"
}

locals {
  cluster_secret = {
    scheme         = "RS256"
    uid            = "${dcos_security_org_service_account.cluster_service_account.uid}"
    private_key    = "${tls_private_key.cluster_service_account_key.private_key_pem}"
    login_endpoint = "https://leader.mesos/acs/api/v1/auth/login"
  }
}

resource "dcos_security_secret" "cluster-secret" {
  path = "${var.cluster_app_id}/secret"
  value = "${jsonencode(local.cluster_secret)}"
}

data "dcos_package_version" "cluster" {
  name     = "kubernetes-cluster"
  version  = "latest"
}

data "dcos_package_config" "cluster" {
  version_spec = "${data.dcos_package_version.cluster.spec}"
  autotype          = true

  section {
    path = "service"
    map = {
        service_account = "${dcos_security_org_service_account.cluster_service_account.uid}"
        service_account_secret = "${dcos_security_secret.cluster-secret.path}"
        virtual_network_name = "dcos",
        use_agent_docker_certs = "true",
    }
  }

  section {
    path = "kubernetes"
    map = {
        authorization_mode = "RBAC", # AlwaysAllow or RBAC
        dcos_token_authentication = "true",
        high_availability = "false",
        private_node_count = 3,
        public_node_count = 0,
    }
  }

  section {
    path = "kubernetes.private_reserved_resources"
    map = {
        kube_cpus = 2,
        kube_mem = 5120,
    }
  }

  section {
    path = "kubernetes.metrics_exporter"
    map = {
        "enabled" = "true",
    }
  }

  section {
    path = "kubernetes.apiserver_edgelb"
    map = {
        "expose" = "true",
        "template" = "default",
        "certificate" = "$AUTOCERT",
        "port" = 8181,
        "path" = ""
    }
  }
}

resource "dcos_package" "cluster" {
  app_id = "${var.cluster_app_id}"
  config = "${data.dcos_package_config.cluster.config}"

  wait            = false
  sdk             = true

  depends_on = [
  "dcos_package.engine",
  "dcos_security_org_user_grant.cluster_principal_grants_create",
  "dcos_security_org_user_grant.cluster_principal_grants_read",
  "dcos_security_org_user_grant.cluster_principal_grants_delete",
  "dcos_security_org_user_grant.cluster_principal_grants_full",
  ]
}
