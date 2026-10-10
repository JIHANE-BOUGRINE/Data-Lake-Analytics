terraform {
    required_providers {
        azurerm = {
            source = "hashicorp/azurerm"
            version = "~> 3.90"
        }
        random={
            source = "hashicorp/random"
            version = "~> 3.6"
        }
    }
    
    backend "azurerm" {
        resource_group_name = "rg-jb-terraform"
        storage_account_name = "storageterraformb"
        container_name = "tfstate"
        key = "dlake.terraform.tfstate"
    }
}

provider "azurerm" {
    features{}
}

resource "azurerm_resource_group" "rg"{
    name = var.resource_group_name
    location = var.location
}

resource "azurerm_storage_account" "adls"{
    name = "adlsbougrine"
    resource_group_name = azurerm_resource_group.rg.name
    location = var.location
    account_tier = "Standard"
    account_replication_type = "LRS"
    account_kind = "StorageV2"
    is_hns_enabled = true
    min_tls_version = "TLS1_2"

}

resource "azurerm_storage_data_lake_gen2_filesystem" "raw" {
    name = "raw"
    storage_account_id = azurerm_storage_account.adls.id
}

resource "azurerm_storage_data_lake_gen2_filesystem" "curated" {
    name = "curated"
    storage_account_id = azurerm_storage_account.adls.id
}

resource "azurerm_storage_data_lake_gen2_filesystem" "enriched" {
    name = "enriched"
    storage_account_id = azurerm_storage_account.adls.id
}

resource "azurerm_storage_data_lake_gen2_filesystem" "quarantine" {
    name               = "quarantine"
    storage_account_id = azurerm_storage_account.adls.id
}

resource "azurerm_data_factory" "adf" {
    name = "adfbougrine"
    location = var.location
    resource_group_name = azurerm_resource_group.rg.name
    identity {
        type = "SystemAssigned"
    }
}

resource "azurerm_storage_account" "synapse_storage" {
    name                     = "synapsestoragebougrine"
    resource_group_name      = azurerm_resource_group.rg.name
    location                 = var.location
    account_tier             = "Standard"
    account_replication_type = "LRS"
    account_kind             = "StorageV2"
    is_hns_enabled           = true
    min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_data_lake_gen2_filesystem" "synapse_fs" {
    name               = "synapsefilesystem"
    storage_account_id = azurerm_storage_account.synapse_storage.id
}

resource "random_password" "synapse_admin" {
  length           = 32
  special          = true
  override_special = "!#$%*-_"
}

resource "azurerm_synapse_workspace" "synapse" {
    name = "synapsebougrine"
    location = var.location
    resource_group_name = azurerm_resource_group.rg.name
    storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.synapse_fs.id
    sql_administrator_login = var.synapse_admin_login
    sql_administrator_login_password = random_password.synapse_admin.result
    identity {
        type = "SystemAssigned"
    }
}

resource "azurerm_key_vault" "kv" {
    name = "kvbougrine"
    location = var.location
    resource_group_name = azurerm_resource_group.rg.name
    tenant_id = var.tenant_id
    sku_name = "standard"
}

resource "azurerm_key_vault_access_policy" "user_policy" {
    key_vault_id = azurerm_key_vault.kv.id
    tenant_id = var.tenant_id
    object_id = var.object_id
    secret_permissions = ["Get","List", "Set", "Delete", "Purge"]
    key_permissions = ["Get","List", "Create", "Delete"]
}

resource "azurerm_key_vault_access_policy" "adf_policy"{
    key_vault_id = azurerm_key_vault.kv.id
    tenant_id = var.tenant_id
    object_id = azurerm_data_factory.adf.identity[0].principal_id
    secret_permissions = ["Get","List"]
}

resource "azurerm_key_vault_access_policy" "synapse_policy"{
    key_vault_id = azurerm_key_vault.kv.id
    tenant_id = var.tenant_id
    object_id = azurerm_synapse_workspace.synapse.identity[0].principal_id
    secret_permissions = ["Get","List"]
}


resource "azurerm_key_vault_secret" "synapse_admin_password" {
    name = "synapse-adminpassword"
    value = random_password.synapse_admin.result
    key_vault_id = azurerm_key_vault.kv.id
    depends_on = [azurerm_key_vault_access_policy.user_policy]
}

resource "azurerm_key_vault_secret" "synapse_admin_login" {
    name = "synapse-adminlogin"
    value = var.synapse_admin_login
    key_vault_id = azurerm_key_vault.kv.id
    depends_on = [azurerm_key_vault_access_policy.user_policy]
}

resource "azurerm_storage_account" "source" {
    name               = "sourcebougrine"
    resource_group_name = azurerm_resource_group.rg.name
    location           = var.location
    account_tier             = "Standard"
    account_replication_type = "LRS"
    account_kind             = "StorageV2"
    min_tls_version          = "TLS1_2"
}

#Azure RBAC : droits sur les stockages

resource "azurerm_role_assignment" "adf_datalake" {
    scope = azurerm_storage_account.adls.id
    role_definition_name = "Storage Blob Data Contributor"
    principal_id = azurerm_data_factory.adf.identity[0].principal_id
}

resource "azurerm_role_assignment" "synapse_datalake" {
    scope = azurerm_storage_account.adls.id
    role_definition_name = "Storage Blob Data Owner"
    principal_id = azurerm_synapse_workspace.synapse.identity[0].principal_id
}

resource "azurerm_role_assignment" "user_datalake_contributor" {
    scope                = azurerm_storage_account.adls.id
    role_definition_name = "Storage Blob Data Contributor"
    principal_id         = var.object_id
}

resource "azurerm_role_assignment" "adf_source" {
    scope = azurerm_storage_account.source.id
    role_definition_name = "Storage Blob Data Contributor"
    principal_id = azurerm_data_factory.adf.identity[0].principal_id
}

resource "azurerm_synapse_role_assignment" "adf_synapse_contributor" {
  synapse_workspace_id = azurerm_synapse_workspace.synapse.id
  role_name            = "Synapse Contributor"
  principal_id         = azurerm_data_factory.adf.identity[0].principal_id
  depends_on           = [azurerm_synapse_firewall_rule.allow_my_ip]
}

resource "azurerm_storage_container" "source_ecommerce" {
    name                  = "source-ecommerce"
    storage_account_name  = azurerm_storage_account.source.name
    container_access_type = "private"
}

resource "azurerm_synapse_firewall_rule" "allow_my_ip" {
    name = "AllowMyIP"
    synapse_workspace_id = azurerm_synapse_workspace.synapse.id
    start_ip_address = "0.0.0.0"
    end_ip_address = "255.255.255.255"
}

resource "azurerm_synapse_firewall_rule" "allow_azure_services" {
  name                 = "AllowAllWindowsAzureIps"
  synapse_workspace_id = azurerm_synapse_workspace.synapse.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "0.0.0.0"
}

