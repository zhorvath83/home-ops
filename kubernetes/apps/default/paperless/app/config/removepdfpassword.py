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

import os
import sys

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


def is_pdf_encrypted(file_path: str) -> bool:
    """Check if PDF is password protected."""
    try:
        with pikepdf.open(file_path) as pdf:
            return pdf.is_encrypted
    except pikepdf.PasswordError:
        return True
    except Exception as e:
        print(f"ERROR: Could not open PDF to check encryption: {e}")
        return True


def pdf_has_attachments(file_path: str) -> bool:
    """Check if PDF contains embedded attachments."""
    try:
        with pikepdf.open(file_path) as pdf:
            return len(pdf.attachments) > 0
    except Exception as e:
        print(f"ERROR: Could not check PDF attachments: {e}")
        return False


def get_passwords_from_env() -> list[str]:
    """Read comma-separated passwords from environment variable."""
    passwords_str = os.environ.get("PAPERLESS_PDF_PASSWORDS", "")
    if not passwords_str:
        print("WARNING: PAPERLESS_PDF_PASSWORDS environment variable is empty")
        return []

    passwords = [p.strip() for p in passwords_str.split(",") if p.strip()]
    print(f"INFO: Loaded {len(passwords)} password(s) from environment")
    return passwords


def unlock_pdf(file_path: str, passwords: list[str]) -> bool:
    """
    Attempt to unlock PDF using provided passwords.

    Returns True if successfully unlocked, False otherwise.
    """
    if not passwords:
        print("ERROR: No passwords available to try")
        return False

    for password in passwords:
        try:
            with pikepdf.open(
                file_path, password=password, allow_overwriting_input=True
            ) as pdf:
                pdf.save(file_path, deterministic_id=True)
                print("INFO: PDF unlocked successfully")
                return True
        except pikepdf.PasswordError:
            continue
        except Exception as e:
            print(f"ERROR: Failed to process PDF with password: {e}")
            continue

    print("WARNING: None of the provided passwords worked")
    return False


def extract_pdf_attachments(file_path: str, consume_path: str) -> None:
    """Extract PDF attachments to consume directory for separate processing."""
    try:
        with pikepdf.open(file_path) as pdf:
            attachments = pdf.attachments
            for attachment_name in attachments:
                attachment = attachments.get(attachment_name)
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
                        target_path = os.path.join(
                            consume_path, f"{base}_{counter}{ext}"
                        )
                        counter += 1

                try:
                    with open(target_path, "wb") as output_file:
                        output_file.write(attachment.obj["/EF"]["/F"].read_bytes())
                    print(f"INFO: Extracted attachment: {target_path}")
                except Exception as e:
                    print(f"ERROR: Failed to extract attachment {target_filename}: {e}")

    except Exception as e:
        print(f"ERROR: Failed to process PDF attachments: {e}")


def main() -> None:
    """Main entry point for pre-consume script."""
    # Get the document path from Paperless environment
    src_file_path = os.environ.get("DOCUMENT_WORKING_PATH")
    consume_path = os.environ.get(
        "PAPERLESS_CONSUMPTION_DIR", "/usr/src/paperless/consume"
    )

    print(f"INFO: Pre-consume script started for: {src_file_path}")

    # Validate input
    if not src_file_path:
        print("INFO: No DOCUMENT_WORKING_PATH provided, skipping")
        return

    if not os.path.exists(src_file_path):
        print(f"ERROR: File does not exist: {src_file_path}")
        return

    if not is_pdf(src_file_path):
        print("INFO: Not a PDF file, skipping")
        return

    # Check if PDF is encrypted
    if is_pdf_encrypted(src_file_path):
        print("INFO: PDF is encrypted, attempting to decrypt")
        passwords = get_passwords_from_env()
        unlock_pdf(src_file_path, passwords)
    else:
        print("INFO: PDF is not encrypted")

    # Extract any PDF attachments
    if pdf_has_attachments(src_file_path):
        print("INFO: PDF has attachments, extracting")
        extract_pdf_attachments(src_file_path, consume_path)
    else:
        print("INFO: No attachments found")

    print("INFO: Pre-consume script completed")


if __name__ == "__main__":
    main()
