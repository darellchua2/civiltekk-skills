"""
DOCX-specific validator for Word document XML files.
"""

from .base import BaseSchemaValidator


class DOCXSchemaValidator(BaseSchemaValidator):
    """Validator for DOCX documents."""

    ELEMENT_RELATIONSHIP_TYPES = {
        "numbering": "numbering",
        "styles": "styles",
        "fontTable": "font",
        "settings": "settings",
        "webSettings": "webSettings",
    }

    def validate(self):
        """Run all DOCX validations."""
        if not self._validate_xml():
            return False

        if not self._validate_namespaces():
            return False

        if not self._validate_unique_ids():
            return False

        if not self._validate_file_references():
            return False

        if not self._validate_all_relationship_ids():
            return False

        if not self._validate_content_types():
            return False

        return True
