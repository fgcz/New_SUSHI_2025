"""Sample repository for sample-related database operations."""

import ast
import re

from sqlmodel import Session, select

from app.models import Sample
from app.repositories.base import BaseRepository


class SampleRepository(BaseRepository[Sample]):
    """Repository for Sample model operations."""

    def __init__(self, session: Session):
        super().__init__(session, Sample)

    def get_by_dataset_id(self, dataset_id: int) -> list[Sample]:
        """Get all samples for a dataset."""
        statement = select(Sample).where(Sample.data_set_id == dataset_id)
        return list(self.session.exec(statement).all())

    def parse_key_value(self, key_value: str | None) -> dict:
        """Parse Ruby hash string to Python dict.

        The key_value field stores data as Ruby hash syntax:
        '{"Name"=>"Sample1", "Read1"=>"path/to/file"}'

        Args:
            key_value: Ruby hash string

        Returns:
            Parsed dictionary
        """
        if not key_value:
            return {}

        try:
            # Convert Ruby hash syntax to Python dict syntax
            # Replace => with : for dict conversion
            # Handle Ruby symbols (:key) and strings ("key")
            python_str = key_value.strip()

            # Replace Ruby hash rocket => with Python colon :
            python_str = re.sub(r'=>', ':', python_str)

            # Replace Ruby symbols :word with "word"
            python_str = re.sub(r':(\w+)', r'"\1"', python_str)

            # Handle nil -> None
            python_str = python_str.replace(':nil', 'None').replace('nil', 'None')

            # Handle true/false
            python_str = python_str.replace(':true', 'True').replace(':false', 'False')

            # Try to safely evaluate as Python literal
            return ast.literal_eval(python_str)
        except (ValueError, SyntaxError):
            # If parsing fails, return empty dict
            return {}

    def get_samples_as_dicts(self, dataset_id: int) -> list[dict]:
        """Get all samples for a dataset as parsed dictionaries."""
        samples = self.get_by_dataset_id(dataset_id)
        return [self.parse_key_value(s.key_value) for s in samples]

    def get_headers(self, dataset_id: int) -> list[str]:
        """Extract unique headers from all samples in a dataset.

        Returns headers sorted with Name first, then Factor fields,
        then other fields alphabetically.
        """
        samples = self.get_samples_as_dicts(dataset_id)

        # Collect all unique keys
        all_keys: set[str] = set()
        for sample in samples:
            all_keys.update(sample.keys())

        # Sort headers: Name first, then Factor fields, then others
        name_headers = []
        factor_headers = []
        other_headers = []

        for key in all_keys:
            if key.lower() == "name":
                name_headers.append(key)
            elif "factor" in key.lower():
                factor_headers.append(key)
            else:
                other_headers.append(key)

        # Sort each group alphabetically
        name_headers.sort()
        factor_headers.sort()
        other_headers.sort()

        return name_headers + factor_headers + other_headers
