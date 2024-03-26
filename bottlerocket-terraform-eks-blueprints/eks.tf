################################################################################
# Data sources
################################################################################
# This DataSource is for testing purposes in order to validate Botterocket Update Operator
data "aws_ami" "eks_bottlerocket" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["bottlerocket-aws-k8s-1.28-x86_64-v1.18*"]
  }
}

################################################################################
# Modules
################################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.21"

  cluster_name                   = local.name
  cluster_version                = "1.28"
  cluster_endpoint_public_access = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
      #service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
    }
  }

  # authentication_mode = "CONFIG_MAP"

  eks_managed_node_group_defaults = {
    ami_type       = "BOTTLEROCKET_x86_64"
    instance_types = ["m5.large", "m5a.large"]

    iam_role_attach_cni_policy = true
  }

  eks_managed_node_groups = {
    bottlerocket = {
      platform = "bottlerocket"

      # Uncomment the following line to use a custom ami_id, this can be provided by a data-source
      ami_id = data.aws_ami.eks_bottlerocket.image_id

      min_size     = 1
      max_size     = 5
      desired_size = 3

      ebs_optimized     = true
      enable_monitoring = true
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            encrypted             = true
            kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
        xvdb = {
          device_name = "/dev/xvdb"
          ebs = {
            encrypted             = true
            kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
      }
      # The following line MUST be changed to true if you want to use a custom ami_id
      use_custom_launch_template = true

      # The next line MUST be uncomment if using a custom_launch_template is set to true
      enable_bootstrap_user_data = true

      # The following block customize your Bottlerocket user-data, you can comment if you don't need any customizations or add more parameters.
      bootstrap_extra_args = <<-EOT
            [settings.host-containers.admin]
            enabled = false

            [settings.host-containers.control]
            enabled = true

            [settings.kernel]
            lockdown = "integrity"

            [settings.kubernetes.node-labels]
            "bottlerocket.aws/updater-interface-version" = "1.0.0"

            [settings.kubernetes.node-taints]
            "CriticalAddonsOnly" = "true:NoSchedule"
          EOT

      # It is also possible to set labels and taints using the following blocks other than the bootstrap arguments above
      #   labels = {
      #     GithubRepo = "terraform-aws-eks"
      #     GithubOrg  = "terraform-aws-modules"
      #   }

      #   taints = [
      #     {
      #       key    = "dedicated"
      #       value  = "gpuGroup"
      #       effect = "NO_SCHEDULE"
      #     }
      #   ]

      # labels = {
      #   "bottlerocket.aws/updater-interface-version" = "2.0.0"
      # }
    }
  }

  tags = local.tags

  # }

  # module "aws_auth" {
  #   source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  #   version = "~> 20.0"

  manage_aws_auth_configmap = true
  aws_auth_roles = [
    # {
    #   rolearn  = module.eks.eks_managed_node_groups.bottlerocket.iam_role_arn
    #   username = "system:node:{{EC2PrivateDNSName}}"
    #   groups = [
    #     "system:bootstrappers",
    #     "system:nodes",
    #   ]
    # },
    # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    }
  ]

}

module "ebs_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 1.5"

  description = "Customer managed key to encrypt EKS managed node group volumes"

  # Policy
  key_administrators = [
    data.aws_caller_identity.current.arn
  ]

  key_service_roles_for_autoscaling = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling",
    module.eks.cluster_iam_role_arn,
  ]

  aliases = ["eks/${local.name}/ebs"]

  tags = local.tags
}

################################################################################
# Outputs
################################################################################
output "eks_cluster" {
  description = "Amazon EKS Cluster configuration."
  value       = module.eks
}

output "kms_key" {
  description = "AWS KMS CMK Configuration."
  value       = module.ebs_kms_key
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig."
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}
