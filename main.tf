provider "azurerm" {
  features {}
}

provider "kubernetes" {
  host                   = module.kubernetes.kube_config.host
  client_certificate     = base64decode(module.kubernetes.kube_config.client_certificate)
  client_key             = base64decode(module.kubernetes.kube_config.client_key)
  cluster_ca_certificate = base64decode(module.kubernetes.kube_config.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.kubernetes.kube_config.host
    client_certificate     = base64decode(module.kubernetes.kube_config.client_certificate)
    client_key             = base64decode(module.kubernetes.kube_config.client_key)
    cluster_ca_certificate = base64decode(module.kubernetes.kube_config.cluster_ca_certificate)
  }
}

locals {
  names = var.naming_conventions_enabled ? module.metadata[0].names : merge(
    {
      business_unit     = var.metadata.business_unit
      environment       = var.metadata.environment
      location          = var.metadata.location
      market            = var.metadata.market
      subscription_type = var.metadata.subscription_type
    },
    var.metadata.product_group != "" ? { product_group = var.metadata.product_group } : {},
    var.metadata.product_name != "" ? { product_name = var.metadata.product_name } : {},
    var.metadata.resource_group_type != "" ? { resource_group_type = var.metadata.resource_group_type } : {}
  )

  tags = merge(module.metadata[0].tags, { "admin" : var.admin.name }, { "email" : var.admin.email })
}

data "http" "my_ip" {
  url = "http://ipv4.icanhazip.com"
}

data "azurerm_subscription" "current" {
}

resource "random_string" "random" {
  length  = 12
  upper   = false
  number  = false
  special = false
}

resource "random_password" "admin" {
  length  = 6
  special = true
}

module "subscription" {
  source          = "github.com/Azure-Terraform/terraform-azurerm-subscription-data.git?ref=v1.0.0"
  subscription_id = data.azurerm_subscription.current.subscription_id
}

module "naming" {
  source = "github.com/Azure-Terraform/example-naming-template.git?ref=v1.0.0"

  count = var.naming_conventions_enabled ? 1 : 0
}

module "metadata" {
  source = "github.com/Azure-Terraform/terraform-azurerm-metadata.git?ref=v1.5.1"

  count        = var.naming_conventions_enabled ? 1 : 0
  naming_rules = module.naming[0].yaml

  market              = var.metadata.market
  location            = var.metadata.location
  sre_team            = var.metadata.sre_team
  environment         = var.metadata.environment
  product_name        = var.metadata.product_name
  business_unit       = var.metadata.business_unit
  product_group       = var.metadata.product_group
  subscription_type   = var.metadata.subscription_type
  resource_group_type = var.metadata.resource_group_type
  subscription_id     = module.subscription.output.subscription_id
  project             = var.metadata.project
}

module "resource_group" {
  source = "github.com/Azure-Terraform/terraform-azurerm-resource-group.git?ref=v2.0.0"

  unique_name = var.resource_group.unique_name
  location    = var.metadata.location
  names       = local.names
  tags        = local.tags
}

module "virtual_network" {
  source = "github.com/Azure-Terraform/terraform-azurerm-virtual-network.git?ref=v2.9.0"

  naming_rules = var.naming_conventions_enabled ? module.naming[0].yaml : null

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  names               = local.names
  tags                = local.tags

  address_space = ["10.1.0.0/22"]

  subnets = {
    iaas-private = {
      cidrs                   = ["10.1.0.0/24"]
      route_table_association = "default"
      configure_nsg_rules     = false
    }
    iaas-public = {
      cidrs                   = ["10.1.1.0/24"]
      route_table_association = "default"
      configure_nsg_rules     = false
    }
  }

  route_tables = {
    default = {
      disable_bgp_route_propagation = true
      routes = {
        internet = {
          address_prefix = "0.0.0.0/0"
          next_hop_type  = "Internet"
        }
        local-vnet = {
          address_prefix = "10.1.0.0/22"
          next_hop_type  = "vnetlocal"
        }
      }
    }
  }
}

module "kubernetes" {
  # source = "github.com/Azure-Terraform/terraform-azurerm-kubernetes.git?ref=v4.2.0"
  source = "github.com/Azure-Terraform/terraform-azurerm-kubernetes.git?ref=v4.2.1"

  cluster_name        = "${local.names.resource_group_type}-${local.names.product_name}-terraform-${local.names.location}-${var.admin.name}"
  location            = var.metadata.location
  names               = local.names
  tags                = local.tags
  resource_group_name = module.resource_group.name

  identity_type = "UserAssigned" # Allowed values: UserAssigned or SystemAssigned

  rbac = {
    enabled        = false
    ad_integration = false
  }

  network_plugin         = "azure"
  configure_network_role = true

  virtual_network = {
    subnets = {
      private = {
        id = module.virtual_network.subnets["iaas-private"].id
      }
      public = {
        id = module.virtual_network.subnets["iaas-public"].id
      }
    }
    route_table_id = module.virtual_network.route_tables["default"].id
  }

  node_pools = {
    system = {
      vm_size                      = var.system_node_pool.vm_size
      node_count                   = var.system_node_pool.node_count
      only_critical_addons_enabled = true
      subnet                       = "private"
    }
    linuxweb = {
      vm_size             = var.additional_node_pool.vm_size
      enable_auto_scaling = var.additional_node_pool.enable_auto_scaling
      min_count           = var.additional_node_pool.min_count
      max_count           = var.additional_node_pool.max_count
      subnet              = "public"
    }
  }

  default_node_pool = "system"

}

module "helm" {
  source = "github.com/gfortil/terraform-azurerm-hpcc-helm.git?ref=v2.0.0"

  image = {
    version = var.hpcc_image.version
    root    = var.hpcc_image.root
    name    = var.hpcc_image.name
  }

  use_local_charts = var.use_local_charts

  hpcc_helm = {
    local_chart = var.hpcc_helm.local_chart # Clone helm-chart.git if left empty. Examples: ./HPCC-Platform, ./helm-chart

    name          = var.hpcc_helm.name
    chart_version = var.hpcc_helm.chart_version # Tag or branch for local. Examples: 8.2.4, my-feature-branch
    namespace     = var.hpcc_helm.namespace
    values        = var.hpcc_helm.values # A list of desired state files similar to -f in CLI
  }

  storage_helm = {
    values = var.storage_helm.values
  }

  elk_helm = {
    name = var.elk_helm.name
  }
}

output "aks_login" {
  value = "az aks get-credentials --name ${module.kubernetes.name} --resource-group ${module.resource_group.name}"
}

output "recommendations" {
  value = data.azurerm_advisor_recommendations.advisor.recommendations
}