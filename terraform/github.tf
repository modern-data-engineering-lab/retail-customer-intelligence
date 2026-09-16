####################################################
# GitHub environments — mirrors databricks-bundle-template's terraform/github.tf exactly.
####################################################
resource "github_repository_environment" "staging" {
  repository  = var.github_repository
  environment = "staging"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "staging" {
  repository     = var.github_repository
  environment    = github_repository_environment.staging.environment
  branch_pattern = "stg"
}

resource "github_repository_environment" "production" {
  repository  = var.github_repository
  environment = "production"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }

  dynamic "reviewers" {
    for_each = var.production_approver_github_user_id != null ? [var.production_approver_github_user_id] : []
    content {
      users = [reviewers.value]
    }
  }
}

resource "github_repository_environment_deployment_policy" "production" {
  repository     = var.github_repository
  environment    = github_repository_environment.production.environment
  branch_pattern = "main"
}

####################################################
# GitHub secrets — opt-in only, see variables.tf's manage_github_secrets_with_terraform.
####################################################
resource "github_actions_environment_secret" "staging_host" {
  count           = var.manage_github_secrets_with_terraform ? 1 : 0
  repository      = var.github_repository
  environment     = github_repository_environment.staging.environment
  secret_name     = "DATABRICKS_HOST"
  plaintext_value = var.databricks_host
}

resource "github_actions_environment_secret" "staging_client_id" {
  count           = var.manage_github_secrets_with_terraform ? 1 : 0
  repository      = var.github_repository
  environment     = github_repository_environment.staging.environment
  secret_name     = "DATABRICKS_CLIENT_ID"
  plaintext_value = databricks_service_principal.staging.application_id
}

resource "github_actions_environment_secret" "staging_client_secret" {
  count           = var.manage_github_secrets_with_terraform ? 1 : 0
  repository      = var.github_repository
  environment     = github_repository_environment.staging.environment
  secret_name     = "DATABRICKS_CLIENT_SECRET"
  plaintext_value = databricks_service_principal_secret.staging.secret
}

resource "github_actions_environment_secret" "staging_warehouse_http_path" {
  count           = var.manage_github_secrets_with_terraform ? 1 : 0
  repository      = var.github_repository
  environment     = github_repository_environment.staging.environment
  secret_name     = "DBT_WAREHOUSE_HTTP_PATH"
  plaintext_value = data.databricks_sql_warehouse.shared.odbc_params[0].path
}

resource "github_actions_environment_secret" "prod_host" {
  count           = var.manage_github_secrets_with_terraform ? 1 : 0
  repository      = var.github_repository
  environment     = github_repository_environment.production.environment
  secret_name     = "DATABRICKS_HOST"
  plaintext_value = var.databricks_host
}

resource "github_actions_environment_secret" "prod_client_id" {
  count           = var.manage_github_secrets_with_terraform ? 1 : 0
  repository      = var.github_repository
  environment     = github_repository_environment.production.environment
  secret_name     = "DATABRICKS_CLIENT_ID"
  plaintext_value = databricks_service_principal.prod.application_id
}

resource "github_actions_environment_secret" "prod_client_secret" {
  count           = var.manage_github_secrets_with_terraform ? 1 : 0
  repository      = var.github_repository
  environment     = github_repository_environment.production.environment
  secret_name     = "DATABRICKS_CLIENT_SECRET"
  plaintext_value = databricks_service_principal_secret.prod.secret
}

resource "github_actions_environment_secret" "prod_warehouse_http_path" {
  count           = var.manage_github_secrets_with_terraform ? 1 : 0
  repository      = var.github_repository
  environment     = github_repository_environment.production.environment
  secret_name     = "DBT_WAREHOUSE_HTTP_PATH"
  plaintext_value = data.databricks_sql_warehouse.shared.odbc_params[0].path
}
