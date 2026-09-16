####################################################
# Catalogs — referenced, not owned. staging_catalog/prod_catalog are shared across this
# portfolio's repos and already provisioned by databricks-bundle-template's Terraform. A
# databricks_grants resource is authoritative for the ENTIRE grant list of its target object,
# so a second Terraform root module can't also declare databricks_grants on the same catalog
# without fighting the template repo's state over ownership on every apply — each would
# silently strip the other's grants. This repo therefore only reads the catalog (data source)
# and owns its own schema underneath it; granting this repo's service principals USE CATALOG
# on the shared catalog is a one-time manual step instead (see terraform/README.md).
####################################################
data "databricks_catalog" "staging" {
  name = var.staging_catalog_name
}

data "databricks_catalog" "prod" {
  name = var.prod_catalog_name
}

####################################################
# Schemas — this repo's actual isolation boundary within the shared catalog (see the note
# above for why that boundary had to move down a level from databricks-bundle-template's
# original catalog-per-environment design, now that a catalog is shared by more than one repo).
####################################################
resource "databricks_schema" "staging" {
  catalog_name  = data.databricks_catalog.staging.name
  name          = var.schema_name
  force_destroy = true
}

resource "databricks_schema" "prod" {
  catalog_name  = data.databricks_catalog.prod.name
  name          = var.schema_name
  force_destroy = true
}

####################################################
# Volumes — where the Olist CSVs get uploaded (manually — Terraform provisions the volume,
# not the upload; see main README Getting Started).
####################################################
resource "databricks_volume" "staging_raw" {
  catalog_name = data.databricks_catalog.staging.name
  schema_name  = databricks_schema.staging.name
  name         = "raw"
  volume_type  = "MANAGED"
}

resource "databricks_volume" "prod_raw" {
  catalog_name = data.databricks_catalog.prod.name
  schema_name  = databricks_schema.prod.name
  name         = "raw"
  volume_type  = "MANAGED"
}

####################################################
# Service principals — one per environment, same rationale as databricks-bundle-template's
# main README ("Why two, not one").
####################################################
resource "databricks_service_principal" "staging" {
  display_name = var.staging_service_principal_name
  active       = true
}

resource "databricks_service_principal" "prod" {
  display_name = var.prod_service_principal_name
  active       = true
}

# See databricks-bundle-template/terraform/databricks.tf's identical comment on the same
# tradeoff: these land in Terraform state in plaintext unless your backend encrypts at rest.
resource "databricks_service_principal_secret" "staging" {
  service_principal_id = databricks_service_principal.staging.id
}

resource "databricks_service_principal_secret" "prod" {
  service_principal_id = databricks_service_principal.prod.id
}

####################################################
# Schema grants — the real isolation boundary here (see the catalogs note above for why this
# can't live at the catalog level anymore). Each SP gets ALL PRIVILEGES on this repo's own
# schema only; USE CATALOG on the shared catalog is granted manually, once, per
# terraform/README.md.
####################################################
resource "databricks_grants" "staging_schema" {
  schema = "${data.databricks_catalog.staging.name}.${databricks_schema.staging.name}"
  grant {
    principal  = databricks_service_principal.staging.application_id
    privileges = ["ALL_PRIVILEGES"]
  }
}

resource "databricks_grants" "prod_schema" {
  schema = "${data.databricks_catalog.prod.name}.${databricks_schema.prod.name}"
  grant {
    principal  = databricks_service_principal.prod.application_id
    privileges = ["ALL_PRIVILEGES"]
  }
}

####################################################
# SQL warehouse access — new versus databricks-bundle-template, which never ran anything
# through a SQL warehouse. Both the DAB's dbt_task and CI's `dbt build` submit queries through
# the shared Free Edition warehouse; a schema grant alone doesn't authorize that — it needs
# its own permission on the warehouse (cluster/endpoint) object. The data source also gives us
# the warehouse's HTTP path for dbt's profiles.yml / the DBT_WAREHOUSE_HTTP_PATH secret,
# without hand-copying it out of the UI.
####################################################
data "databricks_sql_warehouse" "shared" {
  id = var.warehouse_id
}

resource "databricks_permissions" "warehouse_usage" {
  sql_endpoint_id = var.warehouse_id

  access_control {
    service_principal_name = databricks_service_principal.staging.application_id
    permission_level       = "CAN_USE"
  }

  access_control {
    service_principal_name = databricks_service_principal.prod.application_id
    permission_level       = "CAN_USE"
  }
}
