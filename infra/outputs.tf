output "staging_acr_name" {
  value = module.staging_acr.name
}

output "prod_acr_name" {
  value = module.prod_acr.name
}

output "staging_client_id" {
  value     = azuread_application.staging.client_id
  sensitive = true
}

output "staging_client_secret" {
  value     = azuread_service_principal_password.staging.value
  sensitive = true
}

output "prod_client_id" {
  value     = azuread_application.prod.client_id
  sensitive = true
}

output "prod_client_secret" {
  value     = azuread_service_principal_password.prod.value
  sensitive = true
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}
