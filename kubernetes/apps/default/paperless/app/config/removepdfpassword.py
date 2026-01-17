#!/usr/bin/env python3
"""
Paperless-ngx pre-consume script for automatic PDF password removal.

This script is executed before document consumption and:
1. Checks if the document is a PDF
2. If encrypted, attempts to decrypt using passwords from PAPERLESS_PDF_PASSWORDS env var
3. Extracts any PDF attachments to the consume directory for separate processing

Based on: https://github.com/mahescho/paperless-ngx-rmpw
Modified to read passwords from environment variable (comma-separated).
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
    """Check if file has .pdf extension."""
    if not file_path:
        return False
    return os.path.splitext(file_path.lower())[1] == ".pdf"


def get_passwords_from_env() -> list[str]:
    """Read comma-separated passwords from environment variable."""
    passwords_str = os.environ.get("PAPERLESS_PDF_PASSWORDS", "")
    if not passwords_str:
        return []
    return [p.strip() for p in passwords_str.split(",") if p.strip()]


def try_open_pdf(
    file_path: str, passwords: list[str]
) -> tuple[pikepdf.Pdf | None, bool]:
    """
    Try to open PDF, attempting passwords if encrypted.

    Returns tuple of (pdf_object or None, was_encrypted).
    Caller is responsible for closing the PDF.
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
    """Extract PDF attachments to consume directory for separate processing."""
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

            # Avoid overwriting existing files
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


def process_pdf(file_path: str, consume_path: str, passwords: list[str]) -> None:
    """Process a single PDF file - decrypt if needed and extract attachments."""
    pdf, was_encrypted = try_open_pdf(file_path, passwords)

    if pdf is None:
        if was_encrypted:
            print("ERROR: Could not decrypt PDF")
        return

    try:
        # Save decrypted version if it was encrypted
        if was_encrypted:
            pdf.save(file_path, deterministic_id=True)
            print("INFO: PDF decrypted successfully")

        # Extract attachments
        extract_pdf_attachments(pdf, consume_path)

    except Exception as e:
        print(f"ERROR: Failed to process PDF: {e}")
    finally:
        pdf.close()


def main() -> None:
    """Main entry point for pre-consume script."""
    src_file_path = os.environ.get("DOCUMENT_WORKING_PATH")
    consume_path = os.environ.get(
        "PAPERLESS_CONSUMPTION_DIR", "/usr/src/paperless/consume"
    )

    # Quick validation - silent exit for non-PDF files
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

    process_pdf(src_file_path, consume_path, passwords)

    print("INFO: Pre-consume script completed")


if __name__ == "__main__":
    main()
