# ## AKS resources

data "terraform_remote_state" "aks" {
  backend = "local"
  config = {
    path = "../learn-terraform-multicloud-kubernetes-aks/terraform.tfstate"
  }
}

provider "kubernetes" {
  alias                  = "aks"
  host                   = data.terraform_remote_state.aks.outputs.host
  client_certificate     = base64decode(data.terraform_remote_state.aks.outputs.client_certificate)
  client_key             = base64decode(data.terraform_remote_state.aks.outputs.client_key)
  cluster_ca_certificate = base64decode(data.terraform_remote_state.aks.outputs.cluster_ca_certificate)
}

resource "kubernetes_service_account" "counting" {
  provider = kubernetes.aks

  metadata {
    name = "counting"
  }
}

resource "kubernetes_pod" "counting" {
  provider = kubernetes.aks

  metadata {
    name = "counting"
  }

  spec {
    service_account_name = "counting"
    container {
      image = "hashicorp/counting-service:0.0.2"
      name  = "counting"

      port {
        container_port = 9001
        name           = "http"
      }
    }
  }

  depends_on = [kubernetes_service_account.counting]
}

## EKS resources 

data "terraform_remote_state" "eks" {
  backend = "local"
  config = {
    path = "../learn-terraform-multicloud-kubernetes-eks/terraform.tfstate"
  }
}


provider "kubernetes" {
  alias                  = "eks"
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority)
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name]
    command     = "aws"
  }
}

resource "kubernetes_service_account" "dashboard" {
  provider = kubernetes.eks

  metadata {
    name = "dashboard"
  }
}

resource "kubernetes_pod" "dashboard" {
  provider = kubernetes.eks

  metadata {
    name = "dashboard"
    annotations = {
      "consul.hashicorp.com/connect-service-upstreams" = "counting:9001:dc2"
    }
    labels = {
      "app" = "dashboard"
    }
  }

  spec {
    service_account_name = "dashboard"
    container {
      image = "hashicorp/dashboard-service:0.0.4"
      name  = "dashboard"

      env {
        name  = "COUNTING_SERVICE_URL"
        value = "http://localhost:9001"
      }

      port {
        container_port = 9002
        name           = "http"
      }
    }
  }

  depends_on = [kubernetes_service_account.dashboard]
}

resource "kubernetes_service" "dashboard" {
  provider = kubernetes.eks

  metadata {
    name      = "dashboard-service-load-balancer"
    namespace = "default"
    labels = {
      "app" = "dashboard"
    }
  }

  spec {
    selector = {
      "app" = "dashboard"
    }
    port {
      port        = 80
      target_port = 9002
    }

    type             = "LoadBalancer"
    load_balancer_ip = ""
  }
}
