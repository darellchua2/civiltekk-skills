"""
Redlining validator for tracked changes in DOCX documents.
"""

from .base import BaseSchemaValidator


class RedliningValidator(BaseSchemaValidator):
    """Validator for tracked changes in Word documents."""

    def __init__(self, unpacked_dir, original_file=None, verbose=False, author="Claude"):
        super().__init__(unpacked_dir, original_file, verbose)
        self.author = author

    def validate(self):
        """Validate tracked changes are consistent."""
        from helpers.simplify_redlines import get_tracked_change_authors, _get_authors_from_docx

        if not self.original_file:
            print("Warning: No original file provided, skipping redlining validation")
            return True

        modified_xml = self.unpacked_dir / "word" / "document.xml"
        modified_authors = get_tracked_change_authors(modified_xml)

        if not modified_authors:
            print("No tracked changes found")
            return True

        original_authors = _get_authors_from_docx(self.original_file)

        new_changes = {}
        for author, count in modified_authors.items():
            original_count = original_authors.get(author, 0)
            diff = count - original_count
            if diff > 0:
                new_changes[author] = diff

        if not new_changes:
            print("No new tracked changes detected")
            return True

        if len(new_changes) == 1 and self.author in new_changes:
            if self.verbose:
                print(f"PASSED - Only {self.author} added tracked changes")
            return True

        print(f"FAILED - Multiple authors added changes: {new_changes}")
        return False
