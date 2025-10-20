# ------------------------------------------------------------------------------
# LB Controller
# ------------------------------------------------------------------------------

module "lb_controller_irsa" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "5.39.0"

  role_name = "${data.terraform_remote_state.infra.outputs.eks_cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.infra.outputs.eks_oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.1"

   values = [
    yamlencode({
      clusterName = data.terraform_remote_state.infra.outputs.eks_cluster_name
      region      = data.terraform_remote_state.infra.outputs.aws_region
      vpcId       = data.terraform_remote_state.infra.outputs.vpc_id

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.lb_controller_irsa.iam_role_arn
        }
      }
    })
  ]

  depends_on = [ module.efs_csi_driver_irsa ]
}

# ------------------------------------------------------------------------------
# ExternalDNS
# ------------------------------------------------------------------------------

module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.0"

  role_name = "${data.terraform_remote_state.infra.outputs.eks_cluster_name}-external-dns"
  attach_external_dns_policy = true

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.infra.outputs.eks_oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.14.4"

  values = [
    yamlencode({
      provider      = "aws"
      policy        = "upsert-only"
      aws = {
        zoneType = "public"
      }
      domainFilters = [var.domain_name]
      txtOwnerId    = data.terraform_remote_state.infra.outputs.eks_cluster_name
      logLevel      = "debug"
      sources = ["service", "ingress", "gateway-httproute", "gateway-tlsroute", "gateway-tcproute", "gateway-udproute"]
      rbac = {
        create = true
        additionalPermissions = [{
          apiGroups = ["gateway.networking.k8s.io"]
          resources = ["gateways","httproutes","tlsroutes","tcproutes","udproutes"]
          verbs = ["get","watch","list"]
        }]
      }

      serviceAccount = {
        create = true
        name   = "external-dns"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.external_dns_irsa.iam_role_arn
        }
      }
    })
  ]
  depends_on = [ module.external_dns_irsa ]
}

# ------------------------------------------------------------------------------
# EFS
# ------------------------------------------------------------------------------

module "efs_csi_driver_irsa" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "5.39.0"

  role_name = "${data.terraform_remote_state.infra.outputs.eks_cluster_name}-efs-csi-driver"
  attach_efs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.infra.outputs.eks_oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }
}

resource "helm_release" "aws_efs_csi_driver" {
  name       = "aws-efs-csi-driver"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  chart      = "aws-efs-csi-driver"
  version    = "3.2.3"

  values = [
    yamlencode({
      controller = {
        serviceAccount = {
          create = true
          name   = "efs-csi-controller-sa"
          annotations = {
            "eks.amazonaws.com/role-arn" = module.efs_csi_driver_irsa.iam_role_arn
          }
        }
      }
    })
  ]

  depends_on = [
    module.efs_csi_driver_irsa
  ]
}

# ------------------------------------------------------------------------------
# istio minimal setting
# ------------------------------------------------------------------------------

resource "helm_release" "istio_base" {
  name             = "istio-base"
  chart            = "base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  namespace        = "istio-system"
  create_namespace = true
  version          = "1.27.1"
  timeout          = 300
  wait             = true
}

resource "helm_release" "istiod" {
  name       = "istiod"
  chart      = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  namespace  = "istio-system"
  version    = "1.27.1"
  timeout    = 600
  wait       = true
  values = [
    yamlencode({
      pilot = {
        env = {
          PILOT_ENABLE_ALPHA_GATEWAY_API = "true"
        }
      }
    })
  ]
 
  depends_on = [
    helm_release.istio_base,
    helm_release.aws_lb_controller
  ]
}

