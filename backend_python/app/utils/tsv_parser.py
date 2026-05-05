"""TSV parser for dataset files.

Dataset TSV format:
- First rows are metadata (key-value pairs with tab separator)
- Empty line separates metadata from data
- Header row contains column names with optional tags: [File], [Link], [Factor], [B-Fabric]
- Data rows contain sample information

Example:
    Name\tMy Dataset
    Comment\tSample data
    Order Id\t12345,12346

    Sample Name [File]\tRead1 [File]\tCondition [Factor]\tOrder Id [B-Fabric]
    sample1\t/path/to/read1.fastq\tcontrol\t12345
    sample2\t/path/to/read2.fastq\ttreatment\t12346
"""

import csv
import re
from dataclasses import dataclass, field
from io import StringIO
from typing import Any


@dataclass
class ColumnInfo:
    """Information about a TSV column."""

    name: str
    tag: str | None = None  # File, Link, Factor, B-Fabric

    @property
    def is_file(self) -> bool:
        return self.tag == "File"

    @property
    def is_link(self) -> bool:
        return self.tag == "Link"

    @property
    def is_factor(self) -> bool:
        return self.tag == "Factor"

    @property
    def is_bfabric(self) -> bool:
        return self.tag == "B-Fabric"


@dataclass
class ParsedDataset:
    """Result of parsing a dataset TSV file."""

    # Metadata from header rows
    name: str | None = None
    comment: str | None = None
    order_ids: list[int] = field(default_factory=list)
    metadata: dict[str, str] = field(default_factory=dict)

    # Column information
    columns: list[ColumnInfo] = field(default_factory=list)

    # Sample data (list of dicts, one per row)
    samples: list[dict[str, Any]] = field(default_factory=list)

    # File columns for validation
    file_columns: list[str] = field(default_factory=list)

    @property
    def num_samples(self) -> int:
        return len(self.samples)


# Pattern to extract column tag: "Column Name [Tag]"
COLUMN_TAG_PATTERN = re.compile(r"^(.+?)\s*\[(\w+(?:-\w+)?)\]$")


def parse_tsv(content: str) -> ParsedDataset:
    """Parse a dataset TSV file.

    Args:
        content: TSV file content as string

    Returns:
        ParsedDataset with metadata and samples

    Raises:
        ValueError: If parsing fails
    """
    result = ParsedDataset()

    lines = content.strip().split("\n")
    if not lines:
        raise ValueError("Empty TSV file")

    # Find the separator between metadata and data
    # Metadata ends at first empty line or first line with multiple tabs
    data_start = 0
    for i, line in enumerate(lines):
        stripped = line.strip()

        # Empty line marks end of metadata
        if not stripped:
            data_start = i + 1
            break

        # Line with multiple tabs is likely the header row
        if stripped.count("\t") > 1:
            data_start = i
            break

        # Parse metadata row (key\tvalue format)
        if "\t" in stripped:
            parts = stripped.split("\t", 1)
            if len(parts) == 2:
                key, value = parts[0].strip(), parts[1].strip()
                _process_metadata(result, key, value)

    if data_start >= len(lines):
        # No data rows, just metadata
        return result

    # Skip any empty lines after metadata
    while data_start < len(lines) and not lines[data_start].strip():
        data_start += 1

    if data_start >= len(lines):
        return result

    # Parse header row
    header_line = lines[data_start]
    result.columns = _parse_header(header_line)
    result.file_columns = [c.name for c in result.columns if c.is_file]

    # Parse data rows
    data_lines = lines[data_start + 1 :]
    if data_lines:
        reader = csv.reader(StringIO("\n".join(data_lines)), delimiter="\t")
        for row in reader:
            if not row or not any(cell.strip() for cell in row):
                continue  # Skip empty rows

            sample = {}
            for i, col in enumerate(result.columns):
                if i < len(row):
                    sample[col.name] = row[i].strip()
                else:
                    sample[col.name] = ""

            result.samples.append(sample)

    return result


def _process_metadata(result: ParsedDataset, key: str, value: str) -> None:
    """Process a metadata key-value pair."""
    key_lower = key.lower().replace(" ", "_")

    if key_lower == "name":
        result.name = value
    elif key_lower == "comment":
        result.comment = value
    elif key_lower in ("order_id", "order_ids"):
        # Parse comma-separated order IDs
        result.order_ids = _parse_order_ids(value)
    else:
        # Store other metadata
        result.metadata[key] = value


def _parse_order_ids(value: str) -> list[int]:
    """Parse comma-separated order IDs."""
    if not value:
        return []

    order_ids = []
    for part in value.split(","):
        part = part.strip()
        if part.isdigit():
            order_ids.append(int(part))

    return order_ids


def _parse_header(line: str) -> list[ColumnInfo]:
    """Parse the header row to extract column names and tags."""
    columns = []

    for cell in line.split("\t"):
        cell = cell.strip()
        if not cell:
            continue

        # Check for tag pattern: "Column Name [Tag]"
        match = COLUMN_TAG_PATTERN.match(cell)
        if match:
            name = match.group(1).strip()
            tag = match.group(2)
            columns.append(ColumnInfo(name=name, tag=tag))
        else:
            columns.append(ColumnInfo(name=cell))

    return columns


def generate_tsv(dataset: ParsedDataset) -> str:
    """Generate TSV content from a ParsedDataset.

    Args:
        dataset: ParsedDataset to serialize

    Returns:
        TSV content as string
    """
    lines = []

    # Write metadata
    if dataset.name:
        lines.append(f"Name\t{dataset.name}")
    if dataset.comment:
        lines.append(f"Comment\t{dataset.comment}")
    if dataset.order_ids:
        lines.append(f"Order Id\t{','.join(str(x) for x in dataset.order_ids)}")
    for key, value in dataset.metadata.items():
        lines.append(f"{key}\t{value}")

    # Empty line separator
    lines.append("")

    # Header row
    header_parts = []
    for col in dataset.columns:
        if col.tag:
            header_parts.append(f"{col.name} [{col.tag}]")
        else:
            header_parts.append(col.name)
    lines.append("\t".join(header_parts))

    # Data rows
    for sample in dataset.samples:
        row = [str(sample.get(col.name, "")) for col in dataset.columns]
        lines.append("\t".join(row))

    return "\n".join(lines)
