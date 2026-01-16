#!/bin/bash
#
# Bash script to attach an existing block storage volume to a Linode instance via Linode API.
# This script uses curl which is available by default on Ubuntu, so it can run as a service.
#

set -euo pipefail

# Default values
TOKEN=""
VOLUME_ID=""
LINODE_ID=""
CONFIG_ID=""
PERSIST_ACROSS_BOOTS=false
WAIT=false
TIMEOUT=300

LINODE_API_BASE="https://api.linode.com/v4"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Attach existing block storage volume to Linode instance via Linode API.

OPTIONS:
    -t, --token TOKEN           Linode API Personal Access Token (or set LINODE_API_TOKEN env var)
    -v, --volume-id ID          Volume ID of the existing block storage volume (required)
    -l, --linode-id ID          Linode ID to attach the volume to (required)
    -c, --config-id ID          Config ID to attach to specific boot config (required)
    -p, --persist-across-boots  Persist attachment across boots (default: false)
    -w, --wait                  Wait for volume to be ready after attachment
    -h, --help                  Show this help message

EXAMPLES:
    # Attach volume (persist_across_boots=false by default)
    $0 --token "your-token" --volume-id 789012 --linode-id 123456 --config-id 12345

    # Attach volume with wait
    $0 --token "your-token" --volume-id 789012 --linode-id 123456 --config-id 12345 --wait

    # Attach volume with persist across boots
    $0 --token "your-token" --volume-id 789012 --linode-id 123456 --config-id 12345 --persist-across-boots
EOF
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--token)
            TOKEN="$2"
            shift 2
            ;;
        -v|--volume-id)
            VOLUME_ID="$2"
            shift 2
            ;;
        -l|--linode-id)
            LINODE_ID="$2"
            shift 2
            ;;
        -c|--config-id)
            CONFIG_ID="$2"
            shift 2
            ;;
        -p|--persist-across-boots)
            PERSIST_ACROSS_BOOTS=true
            shift
            ;;
        -w|--wait)
            WAIT=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Get token from environment if not provided
if [[ -z "$TOKEN" ]]; then
    TOKEN="${LINODE_API_TOKEN:-}"
fi

# Validate required parameters
if [[ -z "$TOKEN" ]]; then
    log_error "Linode API token is required (--token or LINODE_API_TOKEN env var)"
    exit 1
fi

if [[ -z "$VOLUME_ID" ]]; then
    log_error "Volume ID is required (--volume-id)"
    usage
    exit 1
fi

if [[ -z "$LINODE_ID" ]]; then
    log_error "Linode ID is required (--linode-id)"
    usage
    exit 1
fi

if [[ -z "$CONFIG_ID" ]]; then
    log_error "Config ID is required (--config-id)"
    usage
    exit 1
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
    log_error "curl is required but not installed"
    exit 1
fi

# Function to make API request
api_request() {
    local method=$1
    local url=$2
    local data=$3
    
    if [[ -n "$data" ]]; then
        curl -s -w "\n%{http_code}" \
            -X "$method" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$url"
    else
        curl -s -w "\n%{http_code}" \
            -X "$method" \
            -H "Authorization: Bearer $TOKEN" \
            "$url"
    fi
}

# Attach volume
attach_volume() {
    log_info "Attaching volume $VOLUME_ID to Linode $LINODE_ID with config $CONFIG_ID (persist_across_boots=$PERSIST_ACROSS_BOOTS)..."
    
    local data
    data=$(jq -n \
        --arg linode_id "$LINODE_ID" \
        --arg config_id "$CONFIG_ID" \
        --argjson persist "$PERSIST_ACROSS_BOOTS" \
        '{
            linode_id: ($linode_id | tonumber),
            config_id: ($config_id | tonumber),
            persist_across_boots: $persist
        }')
    
    local response
    response=$(api_request "POST" "$LINODE_API_BASE/volumes/$VOLUME_ID/attach" "$data")
    
    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" -lt 200 || "$http_code" -gt 299 ]]; then
        local error_msg
        error_msg=$(echo "$body" | jq -r '.errors[0].reason // "Unknown error"' 2>/dev/null || echo "Unknown error")
        
        # If volume is already attached, consider it success
        if echo "$error_msg" | grep -qi "already attached\|already.*attach"; then
            log_info "Volume $VOLUME_ID is already attached (API returned: $error_msg)"
            return 0
        fi
        
        log_error "Failed to attach volume: $error_msg (Status: $http_code)"
        exit 1
    fi
    
    log_info "Volume attached successfully!"
}

# Get volume status
get_volume_status() {
    local response
    response=$(api_request "GET" "$LINODE_API_BASE/volumes/$VOLUME_ID" "")
    
    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" != 200 ]]; then
        log_error "Failed to get volume status: $http_code"
        return 1
    fi
    
    echo "$body"
}

# Wait for volume to be ready
wait_for_volume_ready() {
    log_info "Waiting for volume $VOLUME_ID to be ready..."
    local start_time
    start_time=$(date +%s)
    
    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $TIMEOUT ]]; then
            log_error "Timeout waiting for volume $VOLUME_ID to be ready"
            return 1
        fi
        
        local volume_status
        volume_status=$(get_volume_status 2>/dev/null || echo "")
        
        if [[ -n "$volume_status" ]]; then
            local status
            status=$(echo "$volume_status" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
            
            if [[ "$status" == "active" ]]; then
                local linode_id_attached
                linode_id_attached=$(echo "$volume_status" | jq -r '.linode_id // empty' 2>/dev/null || echo "")
                
                if [[ -n "$linode_id_attached" ]]; then
                    log_info "Volume $VOLUME_ID is ready and attached to Linode $linode_id_attached"
                    return 0
                else
                    log_info "Volume $VOLUME_ID is active but not attached yet..."
                fi
            else
                log_info "Volume status: $status"
            fi
        fi
        
        sleep 5
    done
}

# Main execution
main() {
    # Check if jq is available (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        log_warn "jq is not installed. Attempting to install..."
        if command -v apt-get &> /dev/null; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq && apt-get install -y -qq jq > /dev/null 2>&1 || {
                log_error "Failed to install jq. Please install jq manually: sudo apt-get install jq"
                exit 1
            }
        else
            log_error "jq is required but not installed. Please install jq: sudo apt-get install jq"
            exit 1
        fi
    fi
    
    attach_volume
    
    if [[ "$WAIT" == true ]]; then
        wait_for_volume_ready
    fi
    
    # Print volume information
    local volume_info
    volume_info=$(get_volume_status)
    
    if [[ -n "$volume_info" ]]; then
        echo ""
        echo "=================================================="
        echo "Volume Information:"
        echo "  Volume ID: $VOLUME_ID"
        echo "  Label: $(echo "$volume_info" | jq -r '.label // "N/A"')"
        echo "  Size: $(echo "$volume_info" | jq -r '.size // "N/A"') GB"
        echo "  Region: $(echo "$volume_info" | jq -r '.region // "N/A"')"
        echo "  Linode ID: $(echo "$volume_info" | jq -r '.linode_id // "N/A"')"
        echo "  Persist Across Boots: $PERSIST_ACROSS_BOOTS"
        echo "=================================================="
    fi
}

main "$@"
