terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.0"
}

# Configure the Linode Provider
provider "linode" {
  token = var.linode_token
}

# Variables
variable "linode_token" {
  description = "Linode API Personal Access Token"
  type        = string
  sensitive   = true
}

variable "linode_region" {
  description = "Linode region"
  type        = string
  default     = "us-east"
}

variable "linode_type" {
  description = "Linode instance type"
  type        = string
  default     = "g6-nanode-1"
}

variable "root_pass" {
  description = "Root password for the Linode instance"
  type        = string
  sensitive   = true
}

variable "ssh_keys" {
  description = "SSH public keys to add to the Linode instance"
  type        = list(string)
  default     = []
}

variable "block_storage_size" {
  description = "Size of block storage volume in GB"
  type        = number
  default     = 2
}

variable "block_storage_label" {
  description = "Label for the block storage volume"
  type        = string
  default     = "dynamic-storage"
}

# Read the attach script from scripts directory
locals {
  attach_script = file("${path.module}/../scripts/attach_block_storage.sh")
}

# Create block storage volume first (needed for user-data script)
resource "linode_volume" "block_storage" {
  label  = var.block_storage_label
  region = var.linode_region
  size   = var.block_storage_size
  # Note: We don't set linode_id here because the attach_block_storage.sh script will attach it dynamically
}

# Create a Linode instance (Ubuntu 24.04 LTS)
resource "linode_instance" "ubuntu_vm" {
  label           = "ubuntu-vm-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  region          = var.linode_region
  type            = var.linode_type
  image           = "linode/ubuntu24.04"
  root_pass       = var.root_pass
  authorized_keys = var.ssh_keys

  # Metadata for user-data script
  # Note: linode_id and config_id will be queried by the user-data script
  # since we can't self-reference the resource during creation
  metadata {
    user_data = base64encode(templatefile("${path.module}/user-data.sh", {
      attach_script     = local.attach_script
      volume_id        = linode_volume.block_storage.id
      linode_api_token = var.linode_token
    }))
  }

  depends_on = [linode_volume.block_storage]
}


# Outputs
output "linode_instance_id" {
  description = "ID of the Linode instance"
  value       = linode_instance.ubuntu_vm.id
}

output "linode_instance_label" {
  description = "Label of the Linode instance"
  value       = linode_instance.ubuntu_vm.label
}

output "linode_instance_ip" {
  description = "Public IP address of the Linode instance"
  value       = linode_instance.ubuntu_vm.ipv4[0]
}

output "block_storage_volume_id" {
  description = "ID of the block storage volume"
  value       = linode_volume.block_storage.id
}

output "block_storage_volume_label" {
  description = "Label of the block storage volume"
  value       = linode_volume.block_storage.label
}
