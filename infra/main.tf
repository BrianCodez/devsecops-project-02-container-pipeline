data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

locals {
  lab_tags = merge(var.tags, {
    lab        = "true"
    expires_on = var.expires_on
  })
}

resource "azurerm_resource_group" "main" {
  name     = "rg-container-pipeline-${var.yourname}"
  location = var.location
  tags     = local.lab_tags
}

resource "azurerm_consumption_budget_resource_group" "lab" {
  count             = var.budget_email == "" ? 0 : 1
  name              = "budget-container-pipeline-${var.yourname}"
  resource_group_id = azurerm_resource_group.main.id
  amount            = var.monthly_budget_amount
  time_grain        = "Monthly"

  time_period {
    start_date = var.budget_start_date
    end_date   = "2036-01-01T00:00:00Z"
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.budget_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.budget_email]
  }
}

module "staging_acr" {
  source              = "./modules/acr"
  name                = "acrstaging${var.yourname}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.lab_tags
}

module "prod_acr" {
  source              = "./modules/acr"
  name                = "acrprod${var.yourname}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.lab_tags
}

resource "azuread_application" "staging" {
  display_name = "sp-acr-staging-${var.yourname}"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "staging" {
  client_id                    = azuread_application.staging.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal_password" "staging" {
  service_principal_id = azuread_service_principal.staging.object_id
  rotate_when_changed  = { rotation_id = "v1" }
}

resource "azurerm_role_assignment" "staging_push" {
  scope                            = module.staging_acr.id
  role_definition_name             = "AcrPush"
  principal_id                     = azuread_service_principal.staging.object_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "staging_pull" {
  scope                            = module.staging_acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azuread_service_principal.staging.object_id
  skip_service_principal_aad_check = true
}

resource "azuread_application" "prod" {
  display_name = "sp-acr-prod-${var.yourname}"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "prod" {
  client_id                    = azuread_application.prod.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal_password" "prod" {
  service_principal_id = azuread_service_principal.prod.object_id
  rotate_when_changed  = { rotation_id = "v1" }
}

resource "azurerm_role_assignment" "prod_push" {
  scope                            = module.prod_acr.id
  role_definition_name             = "AcrPush"
  principal_id                     = azuread_service_principal.prod.object_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "prod_staging_pull" {
  scope                            = module.staging_acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azuread_service_principal.prod.object_id
  skip_service_principal_aad_check = true
}

# `az acr import` is a management-plane call; AcrPush/AcrPull are
# data-plane only, so the prod SP also needs registry read + the
# importImage action.
resource "azurerm_role_definition" "acr_import" {
  name  = "acr-import-${var.yourname}"
  scope = azurerm_resource_group.main.id

  permissions {
    actions = [
      "Microsoft.ContainerRegistry/registries/read",
      "Microsoft.ContainerRegistry/registries/importImage/action",
    ]
  }

  assignable_scopes = [azurerm_resource_group.main.id]
}

resource "azurerm_role_assignment" "prod_import" {
  scope                            = module.prod_acr.id
  role_definition_id               = azurerm_role_definition.acr_import.role_definition_resource_id
  principal_id                     = azuread_service_principal.prod.object_id
  skip_service_principal_aad_check = true
}

# Reader on the staging ACR lets the import call resolve and pull the
# source image with the caller's identity (paired with AcrPull above).
resource "azurerm_role_assignment" "prod_staging_read" {
  scope                            = module.staging_acr.id
  role_definition_name             = "Reader"
  principal_id                     = azuread_service_principal.prod.object_id
  skip_service_principal_aad_check = true
}
