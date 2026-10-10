variable "location" {
    default = "francecentral"
}

variable "resource_group_name" {
    default = "rgJihaneBougrine"
}

variable "synapse_admin_login" {
    description = "login administrateur pour synapse SQL"
    type = string
    sensitive = true
}

variable "synapse_admin_password" {
    description = "mot de passe administrateur pour synapse SQL"
    type = string
    sensitive = true
}

variable "tenant_id" {
    description = "tenant ID Azure"
    type = string
    sensitive = true
}

variable "object_id" {
    description = "object ID de l'administrateur"
    type = string
    sensitive = true
}
variable "terraform_client_ip" {
    description = "IP du client terraform"
    type = string
    sensitive = true
}