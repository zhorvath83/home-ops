#!/bin/bash
# =============================================================================
# Paperless-ngx Pre-Consume Script
# =============================================================================
#
# This script processes PDF files before Paperless-ngx consumption:
#
# 1. PASSWORD REMOVAL: Decrypts password-protected PDFs using passwords from
#    the PAPERLESS_PDF_PASSWORDS environment variable (comma-separated).
#
# 2. BLANK PAGE REMOVAL: Removes blank/nearly blank pages using Ghostscript
#    ink coverage analysis and qpdf page manipulation.
#
# 3. ATTACHMENT EXTRACTION: Extracts embedded PDF attachments to the consume
#    directory for separate processing by Paperless-ngx.
#
# 4. LOSSLESS OPTIMIZATION: Applies maximum lossless compression to reduce
#    file size while preserving quality.
#
# EXIT CODES:
#   0: Success - document processing can continue
#   1: Failure - document will NOT be consumed, file remains in consume dir
#
# ENVIRONMENT VARIABLES:
#   DOCUMENT_WORKING_PATH:      Set by Paperless-ngx, path to document
#   PAPERLESS_CONSUMPTION_DIR:  Consume directory (default: /usr/src/paperless/consume)
#   PAPERLESS_PDF_PASSWORDS:    Comma-separated passwords for encrypted PDFs
#   BLANK_PAGE_THRESHOLD:       Ink coverage threshold (default: 0.3)
#
# DEPENDENCIES (all included in paperless-ngx image):
#   - qpdf: PDF manipulation and optimization
#   - gs (Ghostscript): Ink coverage analysis for blank detection
#   - pdfinfo: PDF page count
#   - file: File type detection
#
# =============================================================================

set -e -o pipefail
export LC_ALL=C

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

IN="${DOCUMENT_WORKING_PATH}"
CONSUME_DIR="${PAPERLESS_CONSUMPTION_DIR:-/usr/src/paperless/consume}"

# Ink coverage threshold for blank page detection
# Lower value = more aggressive blank detection
# 0.3 works well for most scanners

# | Ink coverage | Jelentés
# |--------------|-----------------------------------------
# | 0.0          | Teljesen üres (fehér) oldal
# | 0.1 - 0.5    | Szinte üres, esetleg halvány vízjel, scanner árnyék
# | 0.5 - 2.0    | Kevés tartalom (pl. csak fejléc/lábléc)
# | 2.0 - 10.0   | Normál szöveges oldal

THRESHOLD="${BLANK_PAGE_THRESHOLD:-0.3}"

# -----------------------------------------------------------------------------
# Logging functions
# -----------------------------------------------------------------------------

log_info() {
    echo "[INFO] $*" >&2
}

log_warn() {
    echo "[WARNING] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

# Exit silently if no file provided
if [[ -z "${IN}" ]]; then
    exit 0
fi

# Check if file exists
if [[ ! -f "${IN}" ]]; then
    log_error "File does not exist: ${IN}"
    exit 0
fi

# Check file type - skip non-PDFs silently
FILE_TYPE=$(file -b "${IN}")
if [[ "${FILE_TYPE%%,*}" != "PDF document" ]]; then
    exit 0
fi

FILENAME=$(basename "${IN}")
log_info "Processing: ${FILENAME}"

# -----------------------------------------------------------------------------
# Function: Decrypt PDF
# -----------------------------------------------------------------------------
# Attempts to decrypt password-protected PDFs using configured passwords.
# Returns 0 if PDF was decrypted or wasn't encrypted, 1 if decryption failed.

decrypt_pdf() {
    local pdf_file="$1"

    # Check if PDF is encrypted
    # qpdf --requires-password exit codes:
    #   0 = password IS required
    #   2 = not encrypted
    #   3 = encrypted but accessible (empty password)
    qpdf --requires-password "${pdf_file}" 2>/dev/null
    local exit_code=$?

    if [[ ${exit_code} -eq 2 ]]; then
        log_info "PDF is not encrypted"
        return 0
    elif [[ ${exit_code} -eq 3 ]]; then
        log_info "PDF is encrypted but accessible (empty password)"
        return 0
    elif [[ ${exit_code} -ne 0 ]]; then
        # Other unexpected error - continue anyway
        log_warn "Could not determine encryption status (exit code: ${exit_code})"
        return 0
    fi

    # exit_code = 0 means password IS required
    log_info "PDF is password-protected"

    # Get passwords from environment
    local passwords_str="${PAPERLESS_PDF_PASSWORDS:-}"
    if [[ -z "${passwords_str}" ]]; then
        log_error "PDF is encrypted but no passwords configured"
        return 1
    fi

    # Split passwords by comma
    IFS=',' read -ra PASSWORDS <<< "${passwords_str}"
    log_info "${#PASSWORDS[@]} password(s) available"

    # Try each password
    for password in "${PASSWORDS[@]}"; do
        password=$(echo "${password}" | xargs)  # Trim whitespace
        if [[ -z "${password}" ]]; then
            continue
        fi

        # Try to decrypt with this password
        if qpdf --password="${password}" --decrypt "${pdf_file}" --replace-input 2>/dev/null; then
            log_info "PDF decrypted successfully"
            return 0
        fi
    done

    log_error "None of the configured passwords worked"
    return 1
}

# -----------------------------------------------------------------------------
# Function: Remove blank pages
# -----------------------------------------------------------------------------
# Uses Ghostscript to analyze ink coverage per page and removes pages below
# the threshold. Preserves document if all pages would be removed.

remove_blank_pages() {
    local pdf_file="$1"

    # Get total page count
    local pages
    pages=$(pdfinfo "${pdf_file}" 2>/dev/null | awk '/Pages:/ {print $2}')

    if [[ -z "${pages}" ]] || [[ "${pages}" -eq 0 ]]; then
        log_warn "Could not determine page count"
        return 0
    fi

    log_info "Analyzing ${pages} page(s) for blank detection"

    # Analyze each page and collect non-blank page numbers
    local non_blank_pages=()

    for i in $(seq 1 "${pages}"); do
        # Get ink coverage (sum of CMYK values)
        local ink_coverage
        ink_coverage=$(gs -o - -dFirstPage="${i}" -dLastPage="${i}" \
            -sDEVICE=ink_cov "${pdf_file}" 2>/dev/null | \
            grep CMYK | awk 'BEGIN {sum=0} {sum += $1 + $2 + $3 + $4} END {printf "%.5f\n", sum}')

        if [[ -z "${ink_coverage}" ]]; then
            # If we can't analyze, keep the page
            non_blank_pages+=("${i}")
            continue
        fi

        # Compare with threshold using awk (bash can't do float comparison)
        if awk "BEGIN {exit !(${ink_coverage} > ${THRESHOLD})}"; then
            non_blank_pages+=("${i}")
            log_info "Page ${i}: ink=${ink_coverage} - keeping (threshold: ${THRESHOLD})"
        else
            log_info "Page ${i}: ink=${ink_coverage} - removing as blank (threshold: ${THRESHOLD})"
        fi
    done

    # Check if any pages remain
    if [[ ${#non_blank_pages[@]} -eq 0 ]]; then
        log_warn "All pages appear blank - keeping original document"
        return 0
    fi

    # Check if any pages were removed
    if [[ ${#non_blank_pages[@]} -eq "${pages}" ]]; then
        log_info "No blank pages detected"
        return 0
    fi

    # Build page range string (comma-separated)
    local page_range
    page_range=$(IFS=','; echo "${non_blank_pages[*]}")

    log_info "Keeping ${#non_blank_pages[@]} of ${pages} pages"

    # Use qpdf to extract non-blank pages
    if qpdf "${pdf_file}" --pages . "${page_range}" -- --replace-input 2>/dev/null; then
        log_info "Blank pages removed successfully"
    else
        log_warn "Failed to remove blank pages - continuing with original"
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Function: Extract PDF attachments
# -----------------------------------------------------------------------------
# Extracts embedded PDF files to the consume directory for separate processing.

extract_attachments() {
    local pdf_file="$1"

    # List attachments
    local attachments
    attachments=$(qpdf --list-attachments "${pdf_file}" 2>/dev/null) || true

    # Check if there are actual attachments (not just "has no embedded files" message)
    if [[ -z "${attachments}" ]] || [[ "${attachments}" == *"has no embedded files"* ]]; then
        return 0
    fi

    log_info "Found embedded attachments"

    # Process each attachment
    while IFS= read -r line; do
        # Extract key (attachment name) from the listing
        # Format: "key -> stream N"
        local key
        key=$(echo "${line}" | sed -n 's/^\([^ ]*\) -> .*/\1/p')

        if [[ -z "${key}" ]]; then
            continue
        fi

        # Check if it's a PDF
        if [[ ! "${key,,}" =~ \.pdf$ ]]; then
            log_info "Skipping non-PDF attachment: ${key}"
            continue
        fi

        # Determine output path (avoid overwriting)
        local output_path="${CONSUME_DIR}/${key}"
        if [[ -f "${output_path}" ]]; then
            local base ext counter=1
            base="${key%.*}"
            ext="${key##*.}"
            while [[ -f "${output_path}" ]]; do
                output_path="${CONSUME_DIR}/${base}_${counter}.${ext}"
                ((counter++))
            done
        fi

        # Extract attachment
        if qpdf --show-attachment="${key}" "${pdf_file}" > "${output_path}" 2>/dev/null; then
            log_info "Extracted attachment: ${output_path}"
        else
            log_warn "Failed to extract attachment: ${key}"
            rm -f "${output_path}" 2>/dev/null || true
        fi

    done <<< "${attachments}"

    return 0
}

# -----------------------------------------------------------------------------
# Function: Optimize PDF (lossless)
# -----------------------------------------------------------------------------
# Applies maximum lossless compression to reduce file size.
# Does NOT use lossy image optimization.

optimize_pdf() {
    local pdf_file="$1"

    log_info "Applying lossless optimization"

    # Lossless optimization flags:
    # --recompress-flate: Recompress flate streams with better compression
    # --compression-level=9: Maximum compression (1-9)
    # --object-streams=generate: Compress PDF objects into streams
    # --compress-streams=y: Ensure all streams are compressed
    # --remove-unreferenced-resources=yes: Remove unused resources
    # --coalesce-contents: Merge content streams

    # Use temp file instead of --replace-input for NFS compatibility
    local temp_file
    temp_file=$(mktemp /tmp/qpdf-optimize-XXXXXXXXXXXX.pdf)

    # Run qpdf optimization
    # Exit codes: 0 = success, 2 = error, 3 = success with warnings
    # Temporarily disable exit on error to capture exit code
    set +e
    qpdf "${pdf_file}" \
        --recompress-flate \
        --compression-level=9 \
        --object-streams=generate \
        --compress-streams=y \
        --remove-unreferenced-resources=yes \
        --coalesce-contents \
        "${temp_file}" 2>/dev/null
    local qpdf_exit=$?
    set -e

    if [[ ${qpdf_exit} -eq 0 || ${qpdf_exit} -eq 3 ]] && [[ -s "${temp_file}" ]]; then
        mv "${temp_file}" "${pdf_file}"
        log_info "Optimization completed"
    else
        log_warn "Optimization failed (exit code: ${qpdf_exit}) - continuing with original"
        rm -f "${temp_file}" 2>/dev/null || true
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Main processing
# -----------------------------------------------------------------------------

# Step 1: Decrypt if encrypted
if ! decrypt_pdf "${IN}"; then
    log_error "Pre-consume script failed - document will not be consumed"
    exit 1
fi

# Step 2: Remove blank pages
remove_blank_pages "${IN}"

# Step 3: Extract embedded PDF attachments
extract_attachments "${IN}"

# Step 4: Optimize (lossless compression)
optimize_pdf "${IN}"

log_info "Pre-consume script completed successfully"
exit 0
