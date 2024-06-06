variable "vault_admin_kubernetes_auth_role_namespaces" {
  description = "K8s namespaces that need to be bound to the vault di-admin-role"
  type        = set(string)
  default     = ["kube-system", "cert-manager", "istio-system", "connaisseur"]
}

variable "role" {
  type = string
}

variable "instance" {
  type = string
}

variable "aws_account_id" {
  description = "default aws account id"
  type        = string

  validation {
    condition     = length(var.aws_account_id) == 12 && can(regex("^\\d{12}$", var.aws_account_id))
    error_message = "Invalid AWS account ID"
  }
}

variable "aws_region" {
  type = string
}

variable "aws_assume_role" {
  type = string
}

variable "aws_auth_roles" {
  type = list(object({
    rolearn  = string
    groups   = list(string)
    username = string
  }))
}

variable "cluster_eks_version" {
  type = string
}

variable "vpc_cni_version" {
  type = string
}

variable "kube_proxy_version" {
  type = string
}

variable "coredns_version" {
  type = string
}

variable "aws_ebs_csi_driver_version" {
  type = string
}

variable "management_node_group_name" {
  type = string
}

variable "management_node_group_role" {
  type = string
}

variable "management_node_group_ami_type" {
  type = string
}

variable "management_node_group_platform" {
  type = string
}

variable "management_node_group_disk_size" {
  type = number
}

variable "management_node_group_capacity_type" {
  type = string
}

variable "management_node_group_desired_size" {
  type = number
}

variable "management_node_group_max_size" {
  type = number
}

variable "management_node_group_min_size" {
  type = number
}

variable "management_node_group_instance_types" {
  type = list(string)
}
