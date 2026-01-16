#!/bin/bash
#
# Cloud-init user-data script to attach block storage volume on boot
# This script runs once when the instance first boots
#

set -euo pipefail

# Variables passed from Terraform
VOLUME_ID="${volume_id}"
LINODE_API_TOKEN="${linode_api_token}"

# Install jq if not already installed
if ! command -v jq &> /dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq jq > /dev/null 2>&1
fi

# Create directory for scripts
mkdir -p /usr/local/bin

# Write the attach script
cat > /usr/local/bin/attach_block_storage.sh << 'ATTACH_SCRIPT_EOF'
${attach_script}
ATTACH_SCRIPT_EOF

# Make script executable
chmod +x /usr/local/bin/attach_block_storage.sh

# Wait for network and metadata service to be ready
sleep 10

# Get Linode instance ID from metadata service
# First, get a metadata token
METADATA_TOKEN=$(curl -s -X PUT -H "Metadata-Token-Expiry-Seconds: 3600" \
    http://169.254.169.254/v1/token | jq -r '.token' 2>/dev/null || echo "")

if [[ -z "$METADATA_TOKEN" ]]; then
    echo "ERROR: Could not get metadata token. Retrying..." >> /var/log/block-storage-attach.log
    sleep 10
    METADATA_TOKEN=$(curl -s -X PUT -H "Metadata-Token-Expiry-Seconds: 3600" \
        http://169.254.169.254/v1/token | jq -r '.token' 2>/dev/null || echo "")
fi

if [[ -z "$METADATA_TOKEN" ]]; then
    echo "ERROR: Failed to get metadata token after retry." >> /var/log/block-storage-attach.log
    exit 1
fi

# Get instance ID from metadata service
LINODE_ID=$(curl -s -H "Metadata-Token: $METADATA_TOKEN" \
    http://169.254.169.254/v1/instance | grep "^id:" | awk '{print $2}' 2>/dev/null || echo "")

if [[ -z "$LINODE_ID" ]]; then
    echo "ERROR: Could not determine Linode ID from metadata service." >> /var/log/block-storage-attach.log
    exit 1
fi

# Get the config ID for this instance using the Linode API
CONFIG_ID=$(curl -s -H "Authorization: Bearer $LINODE_API_TOKEN" \
    "https://api.linode.com/v4/linode/instances/$LINODE_ID/configs" | \
    jq -r '.data[0].id' 2>/dev/null || echo "")

if [[ -z "$CONFIG_ID" ]]; then
    echo "ERROR: Could not determine Config ID from Linode API." >> /var/log/block-storage-attach.log
    exit 1
fi

# Attach the block storage volume
/usr/local/bin/attach_block_storage.sh \
    --token "$LINODE_API_TOKEN" \
    --volume-id "$VOLUME_ID" \
    --linode-id "$LINODE_ID" \
    --config-id "$CONFIG_ID" \
    --wait || {
    echo "Failed to attach block storage volume. Check logs for details." >> /var/log/block-storage-attach.log
    exit 1
}

# Log success
echo "Block storage volume $VOLUME_ID attached successfully to Linode $LINODE_ID with config $CONFIG_ID" >> /var/log/block-storage-attach.log

# Create a systemd service to ensure it stays attached on reboot
cat > /etc/systemd/system/attach-block-storage.service << SERVICE_EOF
[Unit]
Description=Attach Block Storage Volume to Linode
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment="LINODE_API_TOKEN=$LINODE_API_TOKEN"
ExecStart=/bin/bash -c '/usr/local/bin/attach_block_storage.sh --token "$LINODE_API_TOKEN" --volume-id $VOLUME_ID --linode-id $LINODE_ID --config-id $CONFIG_ID --wait'
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Replace placeholders in service file with actual values
sed -i "s|\$VOLUME_ID|$VOLUME_ID|g" /etc/systemd/system/attach-block-storage.service
sed -i "s|\$LINODE_ID|$LINODE_ID|g" /etc/systemd/system/attach-block-storage.service
sed -i "s|\$CONFIG_ID|$CONFIG_ID|g" /etc/systemd/system/attach-block-storage.service

# Enable the service for future reboots
systemctl daemon-reload
systemctl enable attach-block-storage.service

echo "Block storage attachment service configured successfully" >> /var/log/block-storage-attach.log
