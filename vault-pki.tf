resource "vault_mount" "pki_int" {
  path = "pki-int-${var.instance}"
  type = "pki"

  default_lease_ttl_seconds = 86400
  max_lease_ttl_seconds     = 315360000
}

resource "vault_pki_secret_backend_intermediate_cert_request" "csr_request" {
  backend     = vault_mount.pki_int.path
  type        = "internal"
  common_name = "Istio-ca Intermediate Authority"
}

resource "vault_pki_secret_backend_root_sign_intermediate" "intermediate" {
  backend     = "pki-${var.role}"
  common_name = "new_intermediate"
  csr         = vault_pki_secret_backend_intermediate_cert_request.csr_request.csr
  format      = "pem_bundle"
  ttl         = 15480000
}

resource "vault_pki_secret_backend_intermediate_set_signed" "intermediate" {
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.intermediate.certificate
}

resource "vault_pki_secret_backend_role" "intermediate_role" {
  backend = vault_mount.pki_int.path

  name              = "istio-ca-${var.instance}"
  ttl               = 86400
  allowed_domains   = ["istio-ca"]
  allow_any_name    = true
  enforce_hostnames = false
  require_cn        = false
  allowed_uri_sans  = ["spiffe://*"]
}
