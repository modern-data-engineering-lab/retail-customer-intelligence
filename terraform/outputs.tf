output "staging_service_principal_application_id" {
  description = "Copy this into ../databricks.yml's staging target if you add an explicit run_as there."
  value       = databricks_service_principal.staging.application_id
}

output "prod_service_principal_application_id" {
  description = "Paste this into ../databricks.yml's prod target under run_as.service_principal_name — it must be the Application ID (UUID), not the display name."
  value       = databricks_service_principal.prod.application_id
}

output "staging_service_principal_client_secret" {
  description = "For DATABRICKS_CLIENT_SECRET in the staging GitHub environment, if not using manage_github_secrets_with_terraform."
  value       = databricks_service_principal_secret.staging.secret
  sensitive   = true
}

output "prod_service_principal_client_secret" {
  description = "For DATABRICKS_CLIENT_SECRET in the production GitHub environment, if not using manage_github_secrets_with_terraform."
  value       = databricks_service_principal_secret.prod.secret
  sensitive   = true
}

output "schema_name" {
  value = databricks_schema.staging.name
}

output "staging_raw_volume_path" {
  description = "Where to upload the 9 Olist CSVs for staging (Getting Started)."
  value       = "/Volumes/${data.databricks_catalog.staging.name}/${databricks_schema.staging.name}/${databricks_volume.staging_raw.name}"
}

output "prod_raw_volume_path" {
  description = "Where to upload the 9 Olist CSVs for prod (Getting Started)."
  value       = "/Volumes/${data.databricks_catalog.prod.name}/${databricks_schema.prod.name}/${databricks_volume.prod_raw.name}"
}

output "warehouse_http_path" {
  description = "For DBT_WAREHOUSE_HTTP_PATH (GitHub secret and local dbt profiles.yml)."
  value       = data.databricks_sql_warehouse.shared.odbc_params[0].path
}

output "manual_use_catalog_grant_commands" {
  description = <<-EOT
    databricks_grants can't safely manage the shared catalog's grant list from this repo's
    Terraform state (see databricks.tf) — run these once after apply so this repo's service
    principals can traverse into the shared catalog to reach their own schema. Uses the Grants
    REST API (via the CLI) rather than SQL — it's an additive patch (add USE_CATALOG to this
    principal) rather than the authoritative replace-all a raw GRANT statement risks looking
    like, and it needs no SQL warehouse running to execute.
  EOT
  value = [
    "databricks grants update catalog ${var.staging_catalog_name} --profile weather-app --json '{\"changes\": [{\"principal\": \"${databricks_service_principal.staging.application_id}\", \"add\": [\"USE_CATALOG\"]}]}'",
    "databricks grants update catalog ${var.prod_catalog_name} --profile weather-app --json '{\"changes\": [{\"principal\": \"${databricks_service_principal.prod.application_id}\", \"add\": [\"USE_CATALOG\"]}]}'",
  ]
}
