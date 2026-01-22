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
# 4. OCR + PDF/A CONVERSION (optional): When PRECONSUME_PDF_OCR=true:
#    - Deskew: Corrects skewed pages
#    - Rotate: Auto-rotates pages to correct orientation
#    - Clean: Removes background noise for better OCR
#    - OCR: Adds searchable text layer (replaces existing OCR)
#    - PDF/A-2b: Converts to archival format
#
# 5. LOSSLESS OPTIMIZATION: When OCR is disabled, applies qpdf compression.
#
# EXIT CODES:
#   0: Success - document processing can continue
#   1: Failure - document will NOT be consumed, file remains in consume dir
#
# ENVIRONMENT VARIABLES:
#   DOCUMENT_WORKING_PATH:      Set by Paperless-ngx, path to document
#   PAPERLESS_CONSUMPTION_DIR:  Consume directory (default: /usr/src/paperless/consume)
#   PAPERLESS_PDF_PASSWORDS:    Comma-separated passwords for encrypted PDFs
#   BLANK_PAGE_THRESHOLD:       Ink coverage threshold (default: 0.5)
#   PRECONSUME_PDF_OCR:         Enable OCR+PDF/A (default: true)
#   PRECONSUME_OCR_LANGUAGE:    OCR language (default: from PAPERLESS_OCR_LANGUAGE or "hun")
#
# DEPENDENCIES (all included in paperless-ngx image):
#   - qpdf: PDF manipulation and optimization
#   - gs (Ghostscript): Ink coverage analysis for blank detection
#   - pdfinfo: PDF page count
#   - file: File type detection
#   - ocrmypdf: OCR and PDF/A conversion
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
# 0.5 works well for most scanners
THRESHOLD="${BLANK_PAGE_THRESHOLD:-0.5}"

# OCR + PDF/A conversion switch (default: enabled)
# Set to "false", "no", "0", or "off" to disable
ENABLE_OCR="${PRECONSUME_PDF_OCR:-true}"

# OCR language - fallback chain: PRECONSUME_OCR_LANGUAGE -> PAPERLESS_OCR_LANGUAGE -> hun
OCR_LANGUAGE="${PRECONSUME_OCR_LANGUAGE:-${PAPERLESS_OCR_LANGUAGE:-hun}}"

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
# Helper: Check if pre-consume OCR is enabled
# -----------------------------------------------------------------------------

is_preconsume_ocr_enabled() {
    case "${ENABLE_OCR,,}" in
        false|no|0|off)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
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
            log_info "Page ${i}: ink=${ink_coverage} - keeping"
        else
            log_info "Page ${i}: ink=${ink_coverage} - removing (blank)"
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

    if [[ -z "${attachments}" ]]; then
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
# Function: Pre-consume OCR and PDF/A conversion
# -----------------------------------------------------------------------------
# Performs OCR with deskew, rotation, cleaning, and converts to PDF/A-2b.
# Replaces any existing OCR text layer.

perform_preconsume_ocr() {
    local pdf_file="$1"
    local ocr_output
    local ocr_exit_code

    log_info "Starting pre-consume OCR processing (language: ${OCR_LANGUAGE})"

    # ocrmypdf options:
    # --deskew: Correct skewed pages
    # --rotate-pages: Auto-rotate pages to correct orientation
    # --clean: Clean pages before OCR (removes background noise)
    # --redo-ocr: Replace existing OCR text layer
    # --output-type pdfa-2: Convert to PDF/A-2b archival format
    # --language: OCR language
    # --invalidate-digital-signatures: Required if PDF has signatures
    # --skip-big 50: Skip pages larger than 50 megapixels (prevents memory issues)
    # --optimize 1: Light optimization (lossless)

    # Capture output and exit code separately (pipe would lose exit code)
    ocr_output=$(ocrmypdf \
        --deskew \
        --rotate-pages \
        --clean \
        --redo-ocr \
        --output-type pdfa-2 \
        --language "${OCR_LANGUAGE}" \
        --invalidate-digital-signatures \
        --skip-big 50 \
        --optimize 1 \
        "${pdf_file}" "${pdf_file}" 2>&1) || ocr_exit_code=$?

    # Log output if any
    if [[ -n "${ocr_output}" ]]; then
        while IFS= read -r line; do
            log_info "pre-consume ocrmypdf: ${line}"
        done <<< "${ocr_output}"
    fi

    if [[ ${ocr_exit_code:-0} -eq 0 ]]; then
        log_info "Pre-consume OCR and PDF/A conversion completed"
        return 0
    else
        log_warn "Pre-consume OCR processing failed (exit code: ${ocr_exit_code}) - continuing with original"
        return 0
    fi
}

# -----------------------------------------------------------------------------
# Function: Optimize PDF (lossless) - only when OCR is disabled
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

    if qpdf "${pdf_file}" \
        --recompress-flate \
        --compression-level=9 \
        --object-streams=generate \
        --compress-streams=y \
        --remove-unreferenced-resources=yes \
        --coalesce-contents \
        --replace-input 2>/dev/null; then
        log_info "Optimization completed"
    else
        log_warn "Optimization failed - continuing with original"
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

# Step 4: Pre-consume OCR + PDF/A conversion OR lossless optimization
if is_preconsume_ocr_enabled; then
    log_info "Pre-consume OCR is enabled"
    perform_preconsume_ocr "${IN}"
else
    log_info "Pre-consume OCR is disabled - applying lossless optimization only"
    optimize_pdf "${IN}"
fi

log_info "Pre-consume script completed successfully"
exit 0
