#!/bin/bash

# Cloudflare Tunnel Cleanup Script
# Keeps only the newest ACTIVE tunnel if multiple ACTIVE tunnels exist
# Only works with active (non-soft-deleted) tunnels

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔍 Cloudflare Tunnel Cleanup Script (Fixed)${NC}"
echo "================================================"
echo -e "${BLUE}ℹ️  This script only works with ACTIVE tunnels (ignores soft-deleted ones)${NC}"
echo ""

# Get credentials from 1Password
echo -e "${YELLOW}📋 Getting credentials from 1Password...${NC}"

# Get Cloudflare API Token
CF_API_TOKEN=$(op read "op://HomeOps/cloudflare/apitoken_1" 2>/dev/null)
if [ -z "$CF_API_TOKEN" ]; then
    echo -e "${RED}❌ Failed to get API token from 1Password${NC}"
    exit 1
fi

# Get Cloudflare Account ID
CF_ACCOUNT_ID=$(op read "op://HomeOps/cloudflare/account_id" 2>/dev/null)
if [ -z "$CF_ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Failed to get Account ID from 1Password${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Credentials retrieved successfully${NC}"

# Function to make API calls with error handling
make_api_call() {
    local method="$1"
    local url="$2"
    local response
    local success

    response=$(curl -s -X "$method" "$url" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

    # Check if response is valid JSON and successful
    if ! echo "$response" | jq . >/dev/null 2>&1; then
        echo -e "${RED}❌ Invalid JSON response from API${NC}" >&2
        exit 1
    fi

    success=$(echo "$response" | jq -r '.success // false')
    if [ "$success" != "true" ]; then
        echo -e "${RED}❌ API call failed${NC}" >&2
        echo "$response" | jq -r '.errors[]?.message // "Unknown error"' >&2
        exit 1
    fi

    echo "$response"
}

# Get ONLY active tunnels (not soft-deleted ones)
echo -e "${YELLOW}🔍 Checking ACTIVE tunnels only...${NC}"
active_tunnels_response=$(make_api_call "GET" "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel?is_deleted=false")

# Parse active tunnel information
active_tunnel_count=$(echo "$active_tunnels_response" | jq -r '.result | length')
echo -e "${GREEN}📊 Found $active_tunnel_count ACTIVE tunnel(s)${NC}"

# Also show total count for reference (including soft-deleted)
echo -e "${BLUE}🔧 Checking total tunnels for reference...${NC}"
all_tunnels_response=$(make_api_call "GET" "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel")
total_tunnel_count=$(echo "$all_tunnels_response" | jq -r '.result | length')
soft_deleted_count=$((total_tunnel_count - active_tunnel_count))
echo -e "${BLUE}📊 Total tunnels (including $soft_deleted_count soft-deleted): $total_tunnel_count${NC}"
echo ""

if [ "$active_tunnel_count" -eq 0 ]; then
    echo -e "${YELLOW}ℹ️  No ACTIVE tunnels found. Nothing to clean up.${NC}"
    if [ "$soft_deleted_count" -gt 0 ]; then
        echo -e "${BLUE}ℹ️  Note: There are $soft_deleted_count soft-deleted tunnels that will be purged by Cloudflare eventually.${NC}"
    fi
    exit 0
elif [ "$active_tunnel_count" -eq 1 ]; then
    tunnel_name=$(echo "$active_tunnels_response" | jq -r '.result[0].name')
    tunnel_id=$(echo "$active_tunnels_response" | jq -r '.result[0].id')
    echo -e "${GREEN}✅ Only 1 ACTIVE tunnel found: $tunnel_name ($tunnel_id)${NC}"
    echo -e "${GREEN}ℹ️  No cleanup needed.${NC}"
    exit 0
fi

# Multiple ACTIVE tunnels found - show them
echo -e "${YELLOW}📋 Current ACTIVE tunnels:${NC}"
echo "$active_tunnels_response" | jq -r '.result[] | "  • \(.name) (\(.id)) - Created: \(.created_at)"'

# Find the newest ACTIVE tunnel (by creation date)
newest_tunnel=$(echo "$active_tunnels_response" | jq -r '[.result[]] | sort_by(.created_at) | reverse | .[0]')
newest_id=$(echo "$newest_tunnel" | jq -r '.id')
newest_name=$(echo "$newest_tunnel" | jq -r '.name')
newest_created=$(echo "$newest_tunnel" | jq -r '.created_at')

echo ""
echo -e "${GREEN}🏆 Newest ACTIVE tunnel to keep:${NC}"
echo -e "  • $newest_name ($newest_id) - Created: $newest_created"

# Get ACTIVE tunnels to delete (all except the newest)
tunnels_to_delete=$(echo "$active_tunnels_response" | jq -r --arg newest_id "$newest_id" '[.result[] | select(.id != $newest_id)]')
delete_count=$(echo "$tunnels_to_delete" | jq -r 'length')

if [ "$delete_count" -eq 0 ]; then
    echo -e "${GREEN}ℹ️  No ACTIVE tunnels to delete.${NC}"
    exit 0
fi

echo ""
echo -e "${RED}🗑️  ACTIVE tunnels to delete ($delete_count):${NC}"
echo "$tunnels_to_delete" | jq -r '.[] | "  • \(.name) (\(.id)) - Created: \(.created_at)"'

# Ask for confirmation
echo ""
read -p "$(echo -e "${YELLOW}⚠️  Do you want to delete these $delete_count ACTIVE tunnel(s)? [y/N]: ${NC}")" -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}❌ Deletion cancelled by user${NC}"
    exit 0
fi

# Delete old ACTIVE tunnels
echo ""
echo -e "${RED}🗑️  Deleting old ACTIVE tunnels...${NC}"

deleted_count=0
failed_count=0

# Create temporary files to track results
temp_dir=$(mktemp -d)
success_file="$temp_dir/success_count"
fail_file="$temp_dir/fail_count"
echo "0" > "$success_file"
echo "0" > "$fail_file"

# Process each tunnel to delete
echo "$tunnels_to_delete" | jq -c '.[]' | while read -r tunnel; do
    tunnel_id=$(echo "$tunnel" | jq -r '.id')
    tunnel_name=$(echo "$tunnel" | jq -r '.name')

    echo -e "${YELLOW}🗑️  Deleting: $tunnel_name ($tunnel_id)${NC}"

    if delete_response=$(make_api_call "DELETE" "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$tunnel_id" 2>/dev/null); then
        if echo "$delete_response" | jq -r '.success' | grep -q "true"; then
            echo -e "${GREEN}✅ Successfully deleted: $tunnel_name${NC}"
            # Increment success counter
            current_success=$(cat "$success_file")
            echo $((current_success + 1)) > "$success_file"
        else
            echo -e "${RED}❌ Failed to delete: $tunnel_name (API returned success=false)${NC}"
            echo "Error details: $(echo "$delete_response" | jq -r '.errors[]?.message // "No error message"')"
            # Increment fail counter
            current_fail=$(cat "$fail_file")
            echo $((current_fail + 1)) > "$fail_file"
        fi
    else
        echo -e "${RED}❌ Failed to delete: $tunnel_name (API call failed)${NC}"
        # Increment fail counter
        current_fail=$(cat "$fail_file")
        echo $((current_fail + 1)) > "$fail_file"
    fi
done

# Read final counts
deleted_count=$(cat "$success_file" 2>/dev/null || echo "0")
failed_count=$(cat "$fail_file" 2>/dev/null || echo "0")

# Cleanup temp files
rm -rf "$temp_dir"

echo ""
echo -e "${GREEN}🎉 Cleanup completed!${NC}"
echo -e "${GREEN}📊 Final Summary:${NC}"
echo -e "  • ACTIVE tunnels found: $active_tunnel_count"
echo -e "  • ACTIVE tunnels successfully deleted: $deleted_count"
echo -e "  • ACTIVE tunnels failed to delete: $failed_count"
echo -e "  • Remaining ACTIVE tunnel: $newest_name ($newest_id)"

# Verify by checking current ACTIVE tunnel count
echo ""
echo -e "${YELLOW}🔍 Verifying cleanup...${NC}"
final_response=$(make_api_call "GET" "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel?is_deleted=false")
final_count=$(echo "$final_response" | jq -r '.result | length')
echo -e "${GREEN}📊 Current ACTIVE tunnel count: $final_count${NC}"

if [ "$final_count" -eq 1 ]; then
    remaining_tunnel=$(echo "$final_response" | jq -r '.result[0].name')
    remaining_id=$(echo "$final_response" | jq -r '.result[0].id')
    echo -e "${GREEN}✅ Perfect! Only 1 ACTIVE tunnel remains: $remaining_tunnel ($remaining_id)${NC}"
elif [ "$final_count" -eq 0 ]; then
    echo -e "${RED}⚠️  Warning: No ACTIVE tunnels remain! You may need to create a new one.${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: Expected 1 ACTIVE tunnel, but found $final_count ACTIVE tunnels${NC}"
    echo "$final_response" | jq -r '.result[] | "  • \(.name) (\(.id))"'
fi

echo ""
echo -e "${GREEN}✨ ACTIVE tunnel cleanup process completed.${NC}"
echo -e "${BLUE}ℹ️  Note: Soft-deleted tunnels are not affected and will be purged by Cloudflare eventually.${NC}"
