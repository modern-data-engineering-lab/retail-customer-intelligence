terraform {
  required_version = ">= 1.5.0"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.30.0, < 2.0.0"
    }
    github = {
      source  = "integrations/github"
      version = ">= 6.0.0, < 7.0.0"
    }
  }

  # No backend block: state is local (terraform.tfstate in this directory, gitignored) by
  # default — see the "State" section in terraform/README.md for why that's fine for one
  # person on one Free Edition workspace, and not fine for a real team.
}
