"""Sample data parser with backwards compatibility for Ruby hash format.

The samples table stores key-value data as serialized strings. Historical data
uses Ruby's hash format ({"key"=>"value"}), while new data uses JSON.

This parser handles both formats transparently.
"""

import json
import re
from typing import Any


def parse_sample_data(key_value: str | None) -> dict[str, Any]:
    """Parse sample data from either JSON or Ruby hash format.

    Args:
        key_value: Serialized string from samples.key_value column.
            Can be JSON: '{"key": "value"}'
            Or Ruby hash: '{"key"=>"value"}'

    Returns:
        Parsed dictionary. Empty dict if input is None or empty.

    Examples:
        >>> parse_sample_data('{"name": "sample1"}')
        {'name': 'sample1'}
        >>> parse_sample_data('{"name"=>"sample1"}')
        {'name': 'sample1'}
        >>> parse_sample_data(None)
        {}
    """
    if not key_value or not key_value.strip():
        return {}

    key_value = key_value.strip()

    # Try JSON first (new format)
    try:
        result = json.loads(key_value)
        if isinstance(result, dict):
            return result
        # If it parsed but isn't a dict, fall through to Ruby parser
    except json.JSONDecodeError:
        pass

    # Try Ruby hash format
    return _parse_ruby_hash(key_value)


def _parse_ruby_hash(ruby_str: str) -> dict[str, Any]:
    """Parse Ruby hash string format.

    Ruby hashes look like: {"key"=>"value", "num"=>123, "flag"=>true}

    Supports:
    - String values (quoted)
    - Numeric values (int/float)
    - Boolean values (true/false)
    - nil values (converted to None)
    - Nested hashes
    - Arrays

    Args:
        ruby_str: Ruby hash string

    Returns:
        Parsed dictionary

    Raises:
        ValueError: If parsing fails
    """
    if not ruby_str.startswith("{") or not ruby_str.endswith("}"):
        raise ValueError(f"Invalid Ruby hash format: {ruby_str[:50]}...")

    # Remove outer braces
    inner = ruby_str[1:-1].strip()

    if not inner:
        return {}

    result = {}
    pos = 0

    while pos < len(inner):
        # Skip whitespace and commas
        while pos < len(inner) and inner[pos] in " \t\n,":
            pos += 1

        if pos >= len(inner):
            break

        # Parse key
        key, pos = _parse_ruby_value(inner, pos)

        # Skip whitespace
        while pos < len(inner) and inner[pos] in " \t\n":
            pos += 1

        # Expect =>
        if inner[pos : pos + 2] != "=>":
            raise ValueError(f"Expected '=>' at position {pos}")
        pos += 2

        # Skip whitespace
        while pos < len(inner) and inner[pos] in " \t\n":
            pos += 1

        # Parse value
        value, pos = _parse_ruby_value(inner, pos)

        result[str(key)] = value

    return result


def _parse_ruby_value(s: str, pos: int) -> tuple[Any, int]:
    """Parse a single Ruby value starting at position pos.

    Returns:
        Tuple of (parsed_value, new_position)
    """
    # Skip whitespace
    while pos < len(s) and s[pos] in " \t\n":
        pos += 1

    if pos >= len(s):
        raise ValueError("Unexpected end of input")

    char = s[pos]

    # String (double or single quoted)
    if char in '"\'':
        return _parse_ruby_string(s, pos)

    # Hash
    if char == "{":
        return _parse_ruby_nested_hash(s, pos)

    # Array
    if char == "[":
        return _parse_ruby_array(s, pos)

    # Symbol (Ruby :symbol - treat as string)
    if char == ":":
        return _parse_ruby_symbol(s, pos)

    # nil, true, false, or number
    return _parse_ruby_literal(s, pos)


def _parse_ruby_string(s: str, pos: int) -> tuple[str, int]:
    """Parse a quoted string."""
    quote = s[pos]
    pos += 1
    result = []

    while pos < len(s):
        char = s[pos]

        if char == "\\":
            # Escape sequence
            pos += 1
            if pos < len(s):
                escaped = s[pos]
                if escaped == "n":
                    result.append("\n")
                elif escaped == "t":
                    result.append("\t")
                elif escaped == "r":
                    result.append("\r")
                else:
                    result.append(escaped)
                pos += 1
        elif char == quote:
            pos += 1
            return "".join(result), pos
        else:
            result.append(char)
            pos += 1

    raise ValueError("Unterminated string")


def _parse_ruby_nested_hash(s: str, pos: int) -> tuple[dict, int]:
    """Parse a nested hash, tracking brace depth."""
    start = pos
    depth = 0

    while pos < len(s):
        char = s[pos]

        if char in '"\'':
            # Skip string content
            quote = char
            pos += 1
            while pos < len(s):
                if s[pos] == "\\":
                    pos += 2
                elif s[pos] == quote:
                    pos += 1
                    break
                else:
                    pos += 1
        elif char == "{":
            depth += 1
            pos += 1
        elif char == "}":
            depth -= 1
            pos += 1
            if depth == 0:
                return _parse_ruby_hash(s[start:pos]), pos
        else:
            pos += 1

    raise ValueError("Unterminated hash")


def _parse_ruby_array(s: str, pos: int) -> tuple[list, int]:
    """Parse a Ruby array."""
    pos += 1  # Skip [
    result = []

    while pos < len(s):
        # Skip whitespace and commas
        while pos < len(s) and s[pos] in " \t\n,":
            pos += 1

        if pos >= len(s):
            raise ValueError("Unterminated array")

        if s[pos] == "]":
            pos += 1
            return result, pos

        value, pos = _parse_ruby_value(s, pos)
        result.append(value)

    raise ValueError("Unterminated array")


def _parse_ruby_symbol(s: str, pos: int) -> tuple[str, int]:
    """Parse a Ruby symbol (:name) as a string."""
    pos += 1  # Skip :
    match = re.match(r"[\w]+", s[pos:])
    if match:
        return match.group(), pos + len(match.group())
    raise ValueError(f"Invalid symbol at position {pos}")


def _parse_ruby_literal(s: str, pos: int) -> tuple[Any, int]:
    """Parse nil, true, false, or a number."""
    # Check for nil
    if s[pos : pos + 3] == "nil":
        return None, pos + 3

    # Check for true
    if s[pos : pos + 4] == "true":
        return True, pos + 4

    # Check for false
    if s[pos : pos + 5] == "false":
        return False, pos + 5

    # Try to parse as number
    match = re.match(r"-?\d+\.?\d*(?:[eE][+-]?\d+)?", s[pos:])
    if match:
        num_str = match.group()
        if "." in num_str or "e" in num_str.lower():
            return float(num_str), pos + len(num_str)
        return int(num_str), pos + len(num_str)

    raise ValueError(f"Cannot parse value at position {pos}: {s[pos:pos+20]}")


def extract_headers(samples: list[dict[str, Any]]) -> list[str]:
    """Extract unique column headers from parsed sample dicts.

    Sorted: Name first, then Factor fields, then others alphabetically.
    """
    all_keys: set[str] = set()
    for sample in samples:
        all_keys.update(sample.keys())

    name_headers, factor_headers, other_headers = [], [], []
    for key in all_keys:
        if key.lower() == "name":
            name_headers.append(key)
        elif "factor" in key.lower():
            factor_headers.append(key)
        else:
            other_headers.append(key)

    return sorted(name_headers) + sorted(factor_headers) + sorted(other_headers)


def extract_data_paths(samples: list[dict[str, Any]]) -> list[str]:
    """Extract unique dataset-level paths (first 2 segments) from sample [File]/[Link] fields."""
    sample_paths: set[str] = set()
    for sample in samples:
        for header, value in sample.items():
            if "[File]" not in header and "[Link]" not in header:
                continue
            if not value:
                continue
            for file_path in str(value).split(","):
                file_path = file_path.strip()
                if "/" in file_path:
                    dir_path = "/".join(file_path.split("/")[:-1])
                    if dir_path:
                        sample_paths.add(dir_path)

    dataset_paths: set[str] = set()
    for path in sample_paths:
        segments = path.split("/")
        dataset_paths.add("/".join(segments[:2]) if len(segments) >= 2 else segments[0])

    return sorted(dataset_paths)


def serialize_sample_data_ruby(data: dict[str, Any]) -> str:
    """Serialize sample data to Ruby Hash#inspect format for the legacy SUSHI database.

    The legacy DB stores key_value as a Ruby hash literal that Ruby reads back
    with eval(). Format must match Ruby's Hash#inspect exactly.
    Example: {"Name"=>"sample1", "Read1 [File]"=>"/path/file.gz"}
    """
    parts = []
    for k, v in data.items():
        key_s = '"' + str(k).replace("\\", "\\\\").replace('"', '\\"') + '"'
        if v is None:
            val_s = "nil"
        else:
            val_s = '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'
        parts.append(f"{key_s}=>{val_s}")
    return "{" + ", ".join(parts) + "}"


def serialize_sample_data(data: dict[str, Any]) -> str:
    """Serialize sample data to JSON format.

    New data should always be stored as JSON for consistency.

    Args:
        data: Dictionary to serialize

    Returns:
        JSON string
    """
    return json.dumps(data, separators=(",", ":"))
