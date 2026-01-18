#!/usr/bin/env python3
"""
Paperless-ngx pre-consume script for automatic PDF password removal.

This script is executed by Paperless-ngx before document consumption and performs
the following operations:

1. Checks if the incoming document is a PDF file
2. If the PDF is encrypted, attempts to decrypt it using passwords from the
   PAPERLESS_PDF_PASSWORDS environment variable
3. Extracts any embedded PDF attachments to the consume directory for separate
   processing by Paperless-ngx

USAGE:
    This script is configured via the PAPERLESS_PRE_CONSUME_SCRIPT environment
    variable in Paperless-ngx. It receives the document path through the
    DOCUMENT_WORKING_PATH environment variable set by Paperless-ngx.

CONFIGURATION:
    Environment Variables:
        PAPERLESS_PDF_PASSWORDS: Comma-separated list of passwords to try when
                                  decrypting PDF files. Stored in 1Password and
                                  injected via Kubernetes ExternalSecret.
                                  Example: "password1,password2,password3"

        DOCUMENT_WORKING_PATH:    Set automatically by Paperless-ngx. Contains
                                  the path to the document being processed.

        PAPERLESS_CONSUMPTION_DIR: The consume directory where extracted PDF
                                   attachments will be placed for processing.
                                   Defaults to "/usr/src/paperless/consume".

EXIT CODES:
    0: Success - document processing can continue
       - PDF was not encrypted
       - PDF was successfully decrypted
       - File is not a PDF (skipped silently)

    1: Failure - document will NOT be consumed, file remains in consume directory
       - PDF is encrypted but no passwords are configured
       - PDF is encrypted but none of the configured passwords work
       - Critical error during PDF processing

BEHAVIOR:
    - Non-PDF files are silently skipped (exit 0)
    - Non-encrypted PDFs pass through unchanged (exit 0)
    - Successfully decrypted PDFs are saved back to the working path (exit 0)
    - Failed decryption stops consumption, file stays in consume dir (exit 1)
    - Embedded PDF attachments are extracted to consume dir for processing

DEPENDENCIES:
    - pikepdf: PDF manipulation library (included in paperless-ngx image)

BASED ON:
    https://github.com/mahescho/paperless-ngx-rmpw

    Modified to:
    - Read passwords from environment variable instead of file
    - Exit with code 1 on decryption failure to stop consumption
    - Add comprehensive error handling and logging
    - Optimize PDF file handling (single open operation)

EXAMPLE LOG OUTPUT (successful decryption):
    INFO: Processing: document.pdf
    INFO: 2 password(s) available
    INFO: PDF decrypted successfully
    INFO: Pre-consume script completed

EXAMPLE LOG OUTPUT (failed decryption):
    INFO: Processing: encrypted.pdf
    INFO: 2 password(s) available
    WARNING: None of the provided passwords worked
    ERROR: Could not decrypt PDF - stopping consumption
    ERROR: Pre-consume script failed - document will not be consumed
"""

from __future__ import annotations

import os
import sys
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import pikepdf

try:
    import pikepdf
except ImportError:
    print("ERROR: pikepdf module not found")
    sys.exit(1)


def is_pdf(file_path: str) -> bool:
    """
    Check if the given file path has a .pdf extension.

    Args:
        file_path: Path to the file to check.

    Returns:
        True if the file has a .pdf extension (case-insensitive), False otherwise.
    """
    if not file_path:
        return False
    return os.path.splitext(file_path.lower())[1] == ".pdf"


def get_passwords_from_env() -> list[str]:
    """
    Read comma-separated passwords from the PAPERLESS_PDF_PASSWORDS environment variable.

    The passwords are expected to be stored in 1Password and injected via
    Kubernetes ExternalSecret as a comma-separated string.

    Returns:
        List of password strings, empty list if no passwords configured.

    Example:
        If PAPERLESS_PDF_PASSWORDS="pass1,pass2,pass3"
        Returns: ["pass1", "pass2", "pass3"]
    """
    passwords_str = os.environ.get("PAPERLESS_PDF_PASSWORDS", "")
    if not passwords_str:
        return []
    return [p.strip() for p in passwords_str.split(",") if p.strip()]


def try_open_pdf(
    file_path: str, passwords: list[str]
) -> tuple[pikepdf.Pdf | None, bool]:
    """
    Attempt to open a PDF file, trying passwords if the file is encrypted.

    This function first tries to open the PDF without a password. If that fails
    with a PasswordError, it iterates through the provided passwords until one
    works or all have been tried.

    Args:
        file_path: Path to the PDF file to open.
        passwords: List of passwords to try if the PDF is encrypted.

    Returns:
        A tuple of (pdf_object, was_encrypted):
        - pdf_object: The opened pikepdf.Pdf object, or None if opening failed.
        - was_encrypted: True if the PDF was encrypted, False otherwise.

    Note:
        The caller is responsible for closing the returned PDF object.
        The PDF is opened with allow_overwriting_input=True to enable
        saving back to the same file.
    """
    # First try without password
    try:
        pdf = pikepdf.open(file_path, allow_overwriting_input=True)
        return pdf, False
    except pikepdf.PasswordError:
        pass
    except Exception as e:
        print(f"ERROR: Could not open PDF: {e}")
        return None, False

    # PDF is encrypted, try passwords
    if not passwords:
        print("WARNING: PDF is encrypted but no passwords configured")
        return None, True

    for password in passwords:
        try:
            pdf = pikepdf.open(
                file_path, password=password, allow_overwriting_input=True
            )
            return pdf, True
        except pikepdf.PasswordError:
            continue
        except Exception as e:
            print(f"ERROR: Failed to open PDF with password: {e}")
            continue

    print("WARNING: None of the provided passwords worked")
    return None, True


def extract_pdf_attachments(pdf: pikepdf.Pdf, consume_path: str) -> None:
    """
    Extract embedded PDF attachments from a PDF file to the consume directory.

    Some PDF files contain embedded PDF attachments (e.g., invoice PDFs with
    attached supporting documents). This function extracts those attachments
    to the Paperless-ngx consume directory so they can be processed separately.

    Only PDF attachments are extracted; other file types are skipped.

    Args:
        pdf: An opened pikepdf.Pdf object to extract attachments from.
        consume_path: Path to the Paperless-ngx consume directory where
                      extracted attachments will be saved.

    Note:
        - Non-PDF attachments are skipped with an info message.
        - If a file with the same name already exists, a numeric suffix
          is added (e.g., document_1.pdf, document_2.pdf).
        - Extraction errors for individual attachments don't stop processing
          of other attachments.
    """
    try:
        attachments = pdf.attachments
    except Exception as e:
        print(f"ERROR: Could not access PDF attachments: {e}")
        return

    if not attachments:
        return

    print(f"INFO: Found {len(attachments)} attachment(s)")

    for attachment_name in attachments:
        try:
            attachment = attachments.get(attachment_name)
            if attachment is None:
                continue

            target_filename = attachment.filename

            if not is_pdf(target_filename):
                print(f"INFO: Skipping non-PDF attachment: {target_filename}")
                continue

            target_path = os.path.join(consume_path, target_filename)

            # Avoid overwriting existing files by adding numeric suffix
            if os.path.exists(target_path):
                base, ext = os.path.splitext(target_filename)
                counter = 1
                while os.path.exists(target_path):
                    target_path = os.path.join(consume_path, f"{base}_{counter}{ext}")
                    counter += 1

            with open(target_path, "wb") as output_file:
                output_file.write(attachment.obj["/EF"]["/F"].read_bytes())
            print(f"INFO: Extracted attachment: {target_path}")

        except Exception as e:
            print(f"ERROR: Failed to extract attachment {attachment_name}: {e}")


def process_pdf(file_path: str, consume_path: str, passwords: list[str]) -> bool:
    """
    Process a single PDF file: decrypt if needed and extract attachments.

    This is the main processing function that:
    1. Attempts to open the PDF (with password if encrypted)
    2. Saves the decrypted version back to the file if it was encrypted
    3. Extracts any embedded PDF attachments

    Args:
        file_path: Path to the PDF file to process.
        consume_path: Path to the consume directory for extracted attachments.
        passwords: List of passwords to try for encrypted PDFs.

    Returns:
        True if processing succeeded (PDF not encrypted, or successfully decrypted).
        False if the PDF is encrypted and could not be decrypted.

    Note:
        When returning False, the pre-consume script will exit with code 1,
        causing Paperless-ngx to skip the document. The file will remain in
        the consume directory for later retry after adding the correct password.
    """
    pdf, was_encrypted = try_open_pdf(file_path, passwords)

    if pdf is None:
        if was_encrypted:
            print("ERROR: Could not decrypt PDF - stopping consumption")
        return not was_encrypted  # False if encrypted but couldn't decrypt

    try:
        # Save decrypted version if it was encrypted
        if was_encrypted:
            pdf.save(file_path, deterministic_id=True)
            print("INFO: PDF decrypted successfully")

        # Extract any embedded PDF attachments
        extract_pdf_attachments(pdf, consume_path)

        return True

    except Exception as e:
        print(f"ERROR: Failed to process PDF: {e}")
        return False
    finally:
        pdf.close()


def main() -> None:
    """
    Main entry point for the pre-consume script.

    This function is called by Paperless-ngx before document consumption.
    It reads the document path from DOCUMENT_WORKING_PATH environment variable,
    validates the input, and processes the PDF if applicable.

    Exit Codes:
        0: Success or non-PDF file (continue with consumption)
        1: Failed to decrypt encrypted PDF (stop consumption)

    Environment Variables Used:
        DOCUMENT_WORKING_PATH: Path to the document being processed (set by Paperless)
        PAPERLESS_CONSUMPTION_DIR: Consume directory path (defaults to standard path)
        PAPERLESS_PDF_PASSWORDS: Comma-separated passwords for encrypted PDFs
    """
    src_file_path = os.environ.get("DOCUMENT_WORKING_PATH")
    consume_path = os.environ.get(
        "PAPERLESS_CONSUMPTION_DIR", "/usr/src/paperless/consume"
    )

    # Quick validation - silent exit for non-PDF files (exit 0, continue consumption)
    if not src_file_path:
        return

    if not is_pdf(src_file_path):
        return

    if not os.path.exists(src_file_path):
        print(f"ERROR: File does not exist: {src_file_path}")
        return

    print(f"INFO: Processing: {os.path.basename(src_file_path)}")

    passwords = get_passwords_from_env()
    if passwords:
        print(f"INFO: {len(passwords)} password(s) available")

    success = process_pdf(src_file_path, consume_path, passwords)

    if success:
        print("INFO: Pre-consume script completed")
    else:
        print("ERROR: Pre-consume script failed - document will not be consumed")
        sys.exit(1)


if __name__ == "__main__":
    main()
