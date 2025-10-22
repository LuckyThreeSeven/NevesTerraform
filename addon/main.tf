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

  depends_on = [ module.lb_controller_irsa]
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
# EBS
# ------------------------------------------------------------------------------

module "ebs_csi_driver_irsa" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "5.39.0"

  role_name = "${data.terraform_remote_state.infra.outputs.eks_cluster_name}-ebs-csi-driver"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.infra.outputs.eks_oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = data.terraform_remote_state.infra.outputs.eks_cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
  depends_on = [ module.ebs_csi_driver_irsa ]
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

resource "kubernetes_storage_class" "efs_sc" {
  metadata  {
    name = "efs-sc"
  }
  storage_provisioner = "efs.csi.aws.com"
  reclaim_policy = "Retain"
  volume_binding_mode = "Immediate"
  parameters = {
    fileSystemId = data.terraform_remote_state.infra.outputs.efs_file_system_id
    directoryPerms = "777"
  }
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

# ------------------------------------------------------------------------------
# prometheus
# ------------------------------------------------------------------------------

resource "helm_release" "prometheus" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "67.2.0"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 600
  wait             = true

  depends_on = [
    helm_release.aws_lb_controller
  ]

  values = [
    yamlencode({
      alertmanager = {
        persistence = { enabled = false }
      }
      prometheus = {
        prometheusSpec = {
          storageSpec = {}
          serviceMonitorSelectorNilUsesHelmValues: false
          serviceMonitorSelector: {}
          serviceMonitorNamespaceSelector: {}
          podMonitorSelectorNilUsesHelmValues: false
          podMonitorSelector: {}
          podMonitorNamespaceSelector: {}
        }
      }
      grafana = {
        enabled = false
      }
    })
  ]
}

# ------------------------------------------------------------------------------
# metrics server
# ------------------------------------------------------------------------------

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.0"
  namespace  = "kube-system"

  depends_on = [
    helm_release.aws_lb_controller
  ]

  values = [
    yamlencode({
      args = [
        "--kubelet-insecure-tls"
      ]
    })
  ]
}
