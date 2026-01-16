# Terraform Configuration for Dynamic Block Storage

This Terraform configuration creates an Ubuntu 24.04 LTS virtual machine on Linode with a 2GB block storage volume, and automatically attaches the block storage on boot using the user-data script.

## Prerequisites

1. Terraform installed (>= 1.0)
2. Linode API Personal Access Token
3. The `scripts/attach_block_storage.sh` script in the parent directory

## Setup

1. **Navigate to the terraform directory:**
   ```bash
   cd terraform
   ```

2. **Copy the example variables file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. **Edit `terraform.tfvars` with your values:**
   ```hcl
   linode_token = "your-linode-api-token-here"
   linode_region = "us-east"
   linode_type = "g6-nanode-1"
   root_pass = "your-secure-root-password-here"
   
   # Optional: Add your SSH public keys
   ssh_keys = [
     "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... user@host"
   ]
   
   block_storage_size = 2
   block_storage_label = "dynamic-storage"
   ```

4. **Initialize Terraform:**
   ```bash
   terraform init
   ```

5. **Review the plan:**
   ```bash
   terraform plan
   ```

6. **Apply the configuration:**
   ```bash
   terraform apply
   ```

## How It Works

1. **Creates Block Storage Volume**: A 2GB block storage volume is created first
2. **Creates Ubuntu VM**: An Ubuntu 24.04 LTS instance is created
3. **User-Data Script**: The `user-data.sh` script is passed via cloud-init metadata, which:
   - Installs `jq` if needed
   - Copies the `attach_block_storage.sh` script to `/usr/local/bin/`
   - Attaches the block storage volume on first boot
   - Creates a systemd service to ensure the volume stays attached on future reboots

4. **Volume Attachment**: The user-data script handles the attachment dynamically via the Linode API

## Outputs

After running `terraform apply`, you'll get:

- `linode_instance_id`: The ID of the created Linode instance
- `linode_instance_label`: The label of the instance
- `linode_instance_ip`: The public IP address
- `block_storage_volume_id`: The ID of the block storage volume
- `block_storage_volume_label`: The label of the volume

## Verification

After the instance boots, you can SSH in and verify:

```bash
# Check if block storage is attached
lsblk

# Check the attach service status
sudo systemctl status attach-block-storage.service

# Check logs
sudo journalctl -u attach-block-storage.service
cat /var/log/block-storage-attach.log
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## Notes

- The user-data script runs only on first boot
- The systemd service ensures the volume is attached on subsequent reboots
- The API token is stored in the systemd service file - consider using a secrets manager for production
- The block storage volume is created and attached, but not formatted or mounted - you can format and mount it manually if needed

## Security Considerations

- Never commit `terraform.tfvars` to version control (it's in `.gitignore`)
- Consider using Terraform Cloud or a secrets manager for API tokens in production
- Use SSH keys instead of passwords when possible
- Rotate API tokens regularly
