resource "vault_policy" "di_admin_policy" {
  name = "di-admin-kubernetes-policy"

  policy = <<EOT
  path "secret/*" {
    capabilities = ["read"]
  }
  path "database/*" {
    capabilities = ["read"]
  }
  path "shared/*" {
    capabilities = ["read", "create", "update", "delete", "list", "patch", "sudo"]
  }
  path "pki*" {
    capabilities = [ "create", "read", "update", "delete", "list", "sudo" ]
  }
  path "transit/*" {
    capabilities = [ "create", "read", "update", "delete", "list" ]
  }
  EOT
}

resource "vault_auth_backend" "vault_auth_backend" {
  type = "kubernetes"
  path = module.eks.cluster_name
}

resource "vault_kubernetes_auth_backend_config" "vault_k8s_auth_config" {
  backend                = vault_auth_backend.vault_auth_backend.path
  kubernetes_host        = module.eks.cluster_endpoint
  kubernetes_ca_cert     = base64decode(module.eks.cluster_certificate_authority_data)
  disable_iss_validation = "true"
}

resource "vault_kubernetes_auth_backend_role" "vault_admin_kubernetes_auth_role" {
  backend   = vault_auth_backend.vault_auth_backend.path
  role_name = "di-admin-kubernetes-role"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = var.vault_admin_kubernetes_auth_role_namespaces
  token_policies                   = [vault_policy.di_admin_policy.name]
}
