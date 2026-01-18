#!/bin/sh
# Paperless-ngx metadata seeder script
# Supports: document_types, tags, custom_fields
#
# Environment variables:
#   PAPERLESS_URL      - Base URL (default: http://paperless:8000)
#   PAPERLESS_TOKEN    - API authentication token (required)
#   SEED_MODE          - "skip" (default) or "update"
#   SEED_DATA_FILE     - Path to JSON seed file (default: /config/seed-metadata.json)

set -e

PAPERLESS_URL="$${PAPERLESS_URL:-http://paperless:8000}"
SEED_MODE="$${SEED_MODE:-skip}"
SEED_DATA_FILE="$${SEED_DATA_FILE:-/config/seed-metadata.json}"

log() {
    echo "[$$(date '+%Y-%m-%d %H:%M:%S')] $$1"
}

error() {
    echo "[$$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $$1" >&2
}

# Check for required tools
check_dependencies() {
    for cmd in curl jq; do
        if ! command -v "$$cmd" > /dev/null 2>&1; then
            error "Required command not found: $$cmd"
            exit 1
        fi
    done
}

# Wait for Paperless to be ready
wait_for_paperless() {
    log "Waiting for Paperless to be ready..."
    max_attempts=60
    attempt=1

    while [ "$$attempt" -le "$$max_attempts" ]; do
        if curl -sf "$${PAPERLESS_URL}/api/" -H "Authorization: Token $${PAPERLESS_TOKEN}" > /dev/null 2>&1; then
            log "Paperless is ready"
            return 0
        fi
        log "Attempt $$attempt/$$max_attempts - Paperless not ready, waiting..."
        sleep 5
        attempt=$$((attempt + 1))
    done

    error "Paperless did not become ready in time"
    return 1
}

# Get existing item by name from an endpoint
# Returns the item ID if found, empty string if not
get_existing_id() {
    endpoint="$$1"
    name="$$2"

    # URL encode the name for the query
    encoded_name=$$(printf '%s' "$$name" | jq -sRr @uri)

    response=$$(curl -sf "$${PAPERLESS_URL}/api/$${endpoint}/?name__iexact=$${encoded_name}" \
        -H "Authorization: Token $${PAPERLESS_TOKEN}" \
        -H "Content-Type: application/json" 2>/dev/null) || response='{"results":[]}'

    printf '%s' "$$response" | jq -r '.results[0].id // empty'
}

# Create or update an item
# $$1 - endpoint (document_types, tags, custom_fields)
# $$2 - JSON item data
process_item() {
    endpoint="$$1"
    item="$$2"
    name=$$(printf '%s' "$$item" | jq -r '.name')

    existing_id=$$(get_existing_id "$$endpoint" "$$name")

    if [ -n "$$existing_id" ]; then
        if [ "$$SEED_MODE" = "update" ]; then
            log "Updating $$endpoint: $$name (id: $$existing_id)"
            if ! curl -sf -X PATCH "$${PAPERLESS_URL}/api/$${endpoint}/$${existing_id}/" \
                -H "Authorization: Token $${PAPERLESS_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "$$item" > /dev/null 2>&1; then
                error "Failed to update $$endpoint: $$name"
                return 1
            fi
            log "Updated $$endpoint: $$name"
        else
            log "Skipping existing $$endpoint: $$name (mode: skip)"
        fi
    else
        log "Creating $$endpoint: $$name"
        if ! curl -sf -X POST "$${PAPERLESS_URL}/api/$${endpoint}/" \
            -H "Authorization: Token $${PAPERLESS_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$$item" > /dev/null 2>&1; then
            error "Failed to create $$endpoint: $$name"
            return 1
        fi
        log "Created $$endpoint: $$name"
    fi
}

# Process all items for a given type
process_items() {
    item_type="$$1"
    endpoint="$$1"

    log "Processing $$item_type..."

    # Check if the key exists in the JSON file
    if ! jq -e ".$${item_type}" "$$SEED_DATA_FILE" > /dev/null 2>&1; then
        log "No $$item_type found in seed data"
        return 0
    fi

    # Get count of items
    count=$$(jq ".$${item_type} | length" "$$SEED_DATA_FILE")
    log "Found $$count $$item_type to process"

    # Process each item by index to avoid subshell issues
    i=0
    while [ "$$i" -lt "$$count" ]; do
        item=$$(jq -c ".$${item_type}[$$i]" "$$SEED_DATA_FILE")
        if [ -n "$$item" ] && [ "$$item" != "null" ]; then
            process_item "$$endpoint" "$$item" || true
        fi
        i=$$((i + 1))
    done

    log "Finished processing $$item_type"
}

main() {
    log "=== Paperless Metadata Seeder ==="
    log "URL: $${PAPERLESS_URL}"
    log "Mode: $${SEED_MODE}"
    log "Seed file: $${SEED_DATA_FILE}"

    check_dependencies

    if [ -z "$$PAPERLESS_TOKEN" ]; then
        error "PAPERLESS_TOKEN is required"
        exit 1
    fi

    if [ ! -f "$$SEED_DATA_FILE" ]; then
        error "Seed data file not found: $${SEED_DATA_FILE}"
        exit 1
    fi

    wait_for_paperless

    # Process each type
    process_items "document_types"
    process_items "tags"
    process_items "custom_fields"

    log "=== Seeding completed ==="
}

main "$$@"
