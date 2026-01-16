# Dynamic Block Storage Management for Linode

This repository provides scripts to attach existing block storage volumes to Linode virtual machines running Ubuntu 24.04 LTS via the Linode API.

## Repository Structure

```
.
├── scripts/
│   └── attach_block_storage.sh    # Script to attach block storage via Linode API
├── terraform/
│   ├── main.tf                     # Terraform configuration
│   ├── user-data.sh                # Cloud-init script for automatic attachment
│   ├── terraform.tfvars.example    # Example Terraform variables
│   └── variables.tf.example        # Example variable definitions
├── README.md                       # This file - general usage
└── README-terraform.md            # Terraform-specific documentation
```

## Overview

**Attach Script** (`scripts/attach_block_storage.sh`): Attach existing block storage volumes via Linode API. Uses curl (available by default on Ubuntu) and can auto-install jq if needed. Works out of the box on fresh Ubuntu systems.

## Prerequisites

- Ubuntu 24.04 LTS on Linode
- Linode API Personal Access Token
- Root or sudo access on the Linode instance
- curl (available by default on Ubuntu)
- jq will be auto-installed if needed (the script handles this automatically)

## Installation

1. Clone or copy the scripts to your Linode instance

2. Make script executable:
   ```bash
   chmod +x scripts/attach_block_storage.sh
   ```

3. Set your Linode API token (optional, can also pass via command line):
   ```bash
   export LINODE_API_TOKEN="your-api-token-here"
   ```

The scripts use `curl` (available by default on Ubuntu) and will automatically install `jq` if needed. Everything works out of the box on fresh Ubuntu systems - no Python or additional dependencies required!

## Usage

### Attach Block Storage via Linode API

Attach an existing block storage volume to your Linode. The block storage volume must already be created.

```bash
# Attach an existing volume (persist_across_boots=false by default)
./scripts/attach_block_storage.sh \
    --token "your-api-token" \
    --volume-id 89963435 \
    --linode-id 13285002 \
    --config-id 93473807 \
    --wait

# Persist attachment across boots (default is false)
./scripts/attach_block_storage.sh \
    --token "your-api-token" \
    --volume-id 789012 \
    --linode-id 123456 \
    --config-id 12345 \
    --persist-across-boots \
    --wait
```

**Parameters:**
- `--token` / `-t`: Linode API token (or set `LINODE_API_TOKEN` env var)
- `--volume-id` / `-v`: **Required** - Volume ID of the existing block storage volume
- `--linode-id` / `-l`: **Required** - Your Linode instance ID
- `--config-id` / `-c`: **Required** - Config ID to attach to specific boot configuration
- `--persist-across-boots` / `-p`: Optional: Persist attachment across boots (default: false)
- `--wait` / `-w`: Wait for volume to be ready before exiting

**Note:** Parameters can use either long (`--token`) or short (`-t`) format.

### Verify Block Storage Attachment

After attaching the volume, you can verify it's attached:

```bash
# List block devices
lsblk

# Or check for new devices
dmesg | tail
```

The new device will typically appear as `/dev/sdb`, `/dev/sdc`, or `/dev/nvme0n1` depending on your instance type.

## Complete Workflow Example

```bash
# 1. From your local machine or Linode, attach existing block storage via API
#    (Block storage volume must already be created)
./scripts/attach_block_storage.sh \
    --token "your-token" \
    --volume-id 789012 \
    --linode-id 123456 \
    --config-id 12345 \
    --wait

# 2. SSH into your Linode
ssh user@your-linode-ip

# 3. Verify the block storage is attached
lsblk

# The block storage volume should now be visible as a block device
# You can format and mount it manually if needed
```

## Running as a Systemd Service

If you need to attach block storage as part of a systemd service (e.g., during boot):

1. Copy the script to a system location:
   ```bash
   sudo cp scripts/attach_block_storage.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/attach_block_storage.sh
   ```

2. Create a systemd service file (e.g., `/etc/systemd/system/attach-block-storage.service`):
   ```ini
   [Unit]
   Description=Attach Block Storage Volume to Linode
   After=network-online.target
   Wants=network-online.target

   [Service]
   Type=oneshot
   Environment="LINODE_API_TOKEN=your-api-token-here"
   ExecStart=/usr/local/bin/attach_block_storage.sh --volume-id 789012 --linode-id 123456 --config-id 12345 --wait
   RemainAfterExit=yes
   StandardOutput=journal
   StandardError=journal

   [Install]
   WantedBy=multi-user.target
   ```

3. Enable and start the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable attach-block-storage.service
   sudo systemctl start attach-block-storage.service
   ```

**Note:** Store your API token securely. Consider using systemd environment files or secrets management instead of hardcoding in the service file.

## Terraform Integration

For automated provisioning with Terraform, see [README-terraform.md](README-terraform.md) and the `terraform/` directory.

## Troubleshooting

### Device not appearing after attachment

1. Check if the volume is attached in Linode dashboard
2. Check kernel messages: `dmesg | tail`
3. Rescan SCSI bus: `sudo rescan-scsi-bus.sh` (if installed)
4. Reboot if necessary

### Volume not ready after API call

- Use the `--wait` flag to wait for the volume to be ready
- Check Linode dashboard for volume status
- Volume may take a few minutes to become active

## Security Notes

- Keep your Linode API token secure
- Don't commit tokens to version control
- Use environment variables or secure credential storage

## API Documentation

For more details on the Linode API:
- [Linode API v4 Documentation](https://www.linode.com/api/v4)
- [Block Storage API Reference](https://www.linode.com/api/v4/volumes)

## License

This project is provided as-is for use with Linode infrastructure.
