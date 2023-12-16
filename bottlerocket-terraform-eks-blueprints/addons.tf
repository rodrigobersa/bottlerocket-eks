################################################################################
# Data Sources
################################################################################
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

################################################################################
# EKS Blueprints Addons
################################################################################
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.12"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_cert_manager = true
  cert_manager = {
    wait = true
  }

  helm_releases = {
    burpop-crd = {
      description   = "CRDs for Bottlerocket Update Operator"
      chart         = "bottlerocket-shadow"
      chart_version = "1.0.0"
      repository    = "https://bottlerocket-os.github.io/bottlerocket-update-operator/"
    }
    brupop-operator = {
      description      = "A Helm chart for Bottlerocket Update Operator"
      chart            = "bottlerocket-update-operator"
      chart_version    = "1.3.0"
      namespace        = "brupop-bottlerocket-aws"
      create_namespace = true
      repository       = "https://bottlerocket-os.github.io/bottlerocket-update-operator/"
    }
  }

  enable_karpenter = true
  karpenter = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
    version             = "v0.33"
  }

  tags = local.tags
}

################################################################################
# Example application and dependencies Helm Chart
################################################################################
resource "helm_release" "application" {
  name  = "application"
  chart = "./application"
  set_list {
    name  = "nodepool.zone"
    value = local.azs
  }

  depends_on = [module.eks_blueprints_addons]
}
