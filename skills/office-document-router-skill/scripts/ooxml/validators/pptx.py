"""
PPTX-specific validator for PowerPoint presentation XML files.
"""

from .base import BaseSchemaValidator


class PPTXSchemaValidator(BaseSchemaValidator):
    """Validator for PPTX presentations."""

    ELEMENT_RELATIONSHIP_TYPES = {
        "slideMaster": "slideMaster",
        "slideLayout": "slideLayout",
        "notesMaster": "notesMaster",
        "notesSlide": "notesSlide",
        "handoutMaster": "handoutMaster",
        "theme": "theme",
        "tableStyles": "tableStyles",
    }

    def validate(self):
        """Run all PPTX validations."""
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
