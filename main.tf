provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.instance, "--region", var.aws_region, "--role-arn", "arn:aws:iam::${var.aws_account_id}:role/${var.aws_assume_role}"]
  }
}

data "aws_vpc" "vpc" {
  tags = {
    Name = "${var.instance}-vpc"
  }
}

data "aws_subnets" "cluster_private_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  tags = {
    Tier = "private"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.15.3"

  cluster_name                   = var.instance
  cluster_version                = var.cluster_eks_version
  cluster_endpoint_public_access = true
  cluster_enabled_log_types      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_id     = data.aws_vpc.vpc.id
  subnet_ids = data.aws_subnets.cluster_private_subnets.ids

  manage_aws_auth_configmap = true

  aws_auth_roles = concat(
    var.aws_auth_roles,
    [{
      rolearn  = module.common_node_role.iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes"
      ]
    }]
  )

  create_kms_key = false
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.cluster_encyption_key.arn
    resources        = ["secrets"]
  }

  iam_role_use_name_prefix = false

  cluster_addons = {

    vpc-cni = {
      addon_version            = var.vpc_cni_version
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
    }

    kube-proxy = {
      addon_version     = var.kube_proxy_version
      resolve_conflicts = "OVERWRITE"
    }

    coredns = {
      addon_version     = var.coredns_version
      resolve_conflicts = "OVERWRITE"
      configuration_values = jsonencode({
        nodeSelector = {
          "node.kubernetes.io/role" = "management"
        }
        tolerations = [
          {
            key      = "dedicated"
            operator = "Equal"
            value    = "management"
            effect   = "NoSchedule"
          }
        ]
      })
    }

    aws-ebs-csi-driver = {
      addon_version            = var.aws_ebs_csi_driver_version
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
      configuration_values = jsonencode({
        controller = {
          nodeSelector = {
            "node.kubernetes.io/role" = "management"
          }
          tolerations = [
            {
              key      = "dedicated"
              operator = "Equal"
              value    = "management"
              effect   = "NoSchedule"
            }
          ]
        }
      })
    }
  }

  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {
    allow_control_plane_tcp = {
      description                   = "Allow TCP Protocol Port"
      protocol                      = "TCP"
      from_port                     = 1024
      to_port                       = 65535
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_group_defaults = {
    force_update_version = true
    enable_monitoring    = true
  }

  eks_managed_node_groups = {
    (var.management_node_group_name) = {
      ami_type       = var.management_node_group_ami_type
      platform       = var.management_node_group_platform
      instance_types = var.management_node_group_instance_types
      capacity_type  = var.management_node_group_capacity_type
      min_size       = var.management_node_group_min_size
      max_size       = var.management_node_group_max_size
      desired_size   = var.management_node_group_desired_size
      disk_size      = var.management_node_group_disk_size
      labels = {
        "nodegroup"               = var.management_node_group_name
        "node.kubernetes.io/role" = var.management_node_group_role
      }
      taints = {
        dedicated = {
          key    = "dedicated"
          value  = var.management_node_group_role
          effect = "NO_SCHEDULE"
        }
      }
    }
  }
}

resource "aws_kms_key" "cluster_encyption_key" {
  description             = "Encryption key for kubernetes-secrets envelope encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = {
    Name = "${var.instance}-kms"
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.instance}-kms"
  target_key_id = aws_kms_key.cluster_encyption_key.key_id
}

module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.1.0"

  role_name             = "${var.instance}-vpc-cni"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.1.0"

  role_name             = "${var.instance}-ebs-csi-controller-sa"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "common_node_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "~> 5.29.0"

  create_instance_profile = true
  create_role             = true
  role_name               = "${var.instance}-common-node-role"
  trusted_role_services   = ["ec2.amazonaws.com"]
  role_requires_mfa       = false

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}
