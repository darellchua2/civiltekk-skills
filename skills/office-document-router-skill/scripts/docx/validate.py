"""
Command line tool to validate Office document XML files.

Performs lightweight structural validation without full schema files (too heavy).
Checks:
- XML well-formedness
- Namespace declarations
- Unique ID constraints
- File reference integrity

Usage:
    python validate.py <path> [--original <original_file>]

The first argument can be either:
- An unpacked directory containing Office document XML files
- A packed Office file (.docx/.pptx/.xlsx) which will be unpacked to a temp directory
"""

import argparse
import sys
import tempfile
import zipfile
from pathlib import Path

from validators import DOCXSchemaValidator, PPTXSchemaValidator, RedliningValidator


def main():
    parser = argparse.ArgumentParser(description="Validate Office document XML files")
    parser.add_argument(
        "path",
        help="Path to unpacked directory or packed Office file (.docx/.pptx/.xlsx)",
    )
    parser.add_argument(
        "--original",
        required=False,
        default=None,
        help="Path to original file (.docx/.pptx/.xlsx). If omitted, structural validation only.",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable verbose output",
    )
    parser.add_argument(
        "--auto-repair",
        action="store_true",
        help="Automatically repair common issues (hex IDs, whitespace preservation)",
    )
    parser.add_argument(
        "--author",
        default="Claude",
        help="Author name for redlining validation (default: Claude)",
    )
    args = parser.parse_args()

    path = Path(args.path)
    if not path.exists():
        print(f"Error: {path} does not exist", file=sys.stderr)
        sys.exit(1)

    original_file = None
    if args.original:
        original_file = Path(args.original)
        if not original_file.is_file():
            print(f"Error: {original_file} is not a file", file=sys.stderr)
            sys.exit(1)
        if original_file.suffix.lower() not in [".docx", ".pptx", ".xlsx"]:
            print(f"Error: {original_file} must be a .docx, .pptx, or .xlsx file", file=sys.stderr)
            sys.exit(1)

    file_extension = (original_file or path).suffix.lower()
    if file_extension not in [".docx", ".pptx", ".xlsx"]:
        print(f"Error: Cannot determine file type from {path}", file=sys.stderr)
        sys.exit(1)

    if path.is_file() and path.suffix.lower() in [".docx", ".pptx", ".xlsx"]:
        temp_dir = tempfile.mkdtemp()
        with zipfile.ZipFile(path, "r") as zf:
            zf.extractall(temp_dir)
        unpacked_dir = Path(temp_dir)
    else:
        if not path.is_dir():
            print(f"Error: {path} is not a directory or Office file", file=sys.stderr)
            sys.exit(1)
        unpacked_dir = path

    match file_extension:
        case ".docx":
            validators = [
                DOCXSchemaValidator(unpacked_dir, original_file, verbose=args.verbose),
            ]
            if original_file:
                validators.append(
                    RedliningValidator(unpacked_dir, original_file, verbose=args.verbose, author=args.author)
                )
        case ".pptx":
            validators = [
                PPTXSchemaValidator(unpacked_dir, original_file, verbose=args.verbose),
            ]
        case _:
            print(f"Error: Validation not supported for file type {file_extension}", file=sys.stderr)
            sys.exit(1)

    if args.auto_repair:
        total_repairs = sum(v.repair() for v in validators)
        if total_repairs:
            print(f"Auto-repaired {total_repairs} issue(s)")

    success = all(v.validate() for v in validators)

    if success:
        print("All validations PASSED!")

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
