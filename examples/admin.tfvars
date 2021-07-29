admin = {
  name  = "hpccdemo"
  email = "hpccdemo@example.com"
}

naming_conventions_enabled = true # true will enforce all metadata inputs below

metadata = {
  location            = "eastus2"
  project             = "hpccdemo"
  product_name        = "contosoweb"
  business_unit       = "commercial"
  environment         = "dev"
  market              = "us"
  product_group       = "contoso"
  resource_group_type = "app"
  sre_team            = "hpccplatform"
  subscription_type   = "dev"
}

resource_group = {
  unique_name = true
}

system_node_pool = {
  vm_size    = "Standard_B2s"
  node_count = 2
}

additional_node_pool = {
  vm_size             = "Standard_B2ms"
  enable_auto_scaling = true
  min_count           = 1
  max_count           = 3
}

hpcc_image = {
  version = "8.2.4-rc1"
  name    = "platform-core"
  root    = "hpccsystems"
}

use_local_charts = false

hpcc_helm = {
  local_chart   = ""
  chart_version = "8.2.4"
  namespace     = "default"
  name          = "myhpcck8s"
  values        = ["HPCC-Platform/helm/examples/azure/values-retained-azurefile.yaml", "esp.yaml"]
}

storage_helm = {
  values = ["HPCC-Platform/helm/examples/azure/hpcc-azurefile/values.yaml"]
}

elk_helm = {
  name = "myhpccelk"
}