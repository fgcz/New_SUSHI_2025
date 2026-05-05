"""Sample repository for sample-related database operations."""

from sqlmodel import Session, select

from app.models import Sample
from app.repositories.base import BaseRepository
from app.utils.sample_parser import parse_sample_data


class SampleRepository(BaseRepository[Sample]):
    """Repository for Sample model operations."""

    def __init__(self, session: Session):
        super().__init__(session, Sample)

    def get_by_dataset_id(self, dataset_id: int) -> list[Sample]:
        """Get all samples for a dataset."""
        statement = select(Sample).where(Sample.data_set_id == dataset_id)
        return list(self.session.exec(statement).all())

    def parse_key_value(self, key_value: str | None) -> dict:
        """Parse sample key_value field to Python dict.

        Handles both JSON and Ruby hash formats for backwards compatibility.

        Args:
            key_value: Serialized string (JSON or Ruby hash format)

        Returns:
            Parsed dictionary
        """
        return parse_sample_data(key_value)

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

    def get_data_paths(self, dataset_id: int) -> list[str]:
        """Extract unique data folder paths from sample file paths.

        Scans all samples for [File] and [Link] tagged headers,
        extracts directory paths, and returns unique dataset-level paths
        (first 2 path segments: p{project}/{dataset_folder}).

        Returns:
            List of unique data paths, e.g., ["p1234/Analysis_A", "p1234/Analysis_B"]
        """
        samples = self.get_samples_as_dicts(dataset_id)
        sample_paths: set[str] = set()

        for sample in samples:
            for header, value in sample.items():
                # Check for [File] or [Link] tagged headers
                if "[File]" in header or "[Link]" in header:
                    if not value:
                        continue
                    # Files can be comma-separated
                    file_list = str(value).split(",")
                    for file_path in file_list:
                        file_path = file_path.strip()
                        if "/" in file_path:
                            # Get directory path
                            dir_path = "/".join(file_path.split("/")[:-1])
                            if dir_path:
                                sample_paths.add(dir_path)

        # Extract dataset-level paths (first 2 segments: p1234/DatasetName)
        dataset_paths: set[str] = set()
        for path in sample_paths:
            segments = path.split("/")
            if len(segments) >= 2:
                dataset_paths.add("/".join(segments[:2]))
            elif len(segments) == 1:
                dataset_paths.add(segments[0])

        return sorted(dataset_paths)
