"""File routes - gStore directory browsing."""

from fastapi import APIRouter, HTTPException

from app.api.deps import CurrentUserDep

router = APIRouter()


# Mock file system structure
MOCK_FILE_SYSTEM: dict[str, list[dict]] = {
    # Root level
    "": [
        {"name": "p1001", "type": "folder", "last_modified": "2026-01-27 10:30:00", "size": None},
        {"name": "p2220", "type": "folder", "last_modified": "2026-01-26 14:15:00", "size": None},
    ],
    # Project p1001
    "p1001": [
        {"name": "FastQC_2026-01-15", "type": "folder", "last_modified": "2026-01-15 09:30:00", "size": None},
        {"name": "RNAseq_Results_2026-01-20", "type": "folder", "last_modified": "2026-01-20 14:45:00", "size": None},
        {"name": "README.txt", "type": "file", "last_modified": "2026-01-10 08:00:00", "size": 1240},
    ],
    # FastQC folder
    "p1001/FastQC_2026-01-15": [
        {"name": "sample1_fastqc.html", "type": "file", "last_modified": "2026-01-15 09:32:00", "size": 245780},
        {"name": "sample2_fastqc.html", "type": "file", "last_modified": "2026-01-15 09:33:00", "size": 251200},
        {"name": "multiqc_report.html", "type": "file", "last_modified": "2026-01-15 09:35:00", "size": 1048576},
    ],
    # RNAseq folder
    "p1001/RNAseq_Results_2026-01-20": [
        {"name": "counts.tsv", "type": "file", "last_modified": "2026-01-20 14:30:00", "size": 524288},
        {"name": "differential_expression.xlsx", "type": "file", "last_modified": "2026-01-20 14:40:00", "size": 89500},
        {"name": "analysis", "type": "folder", "last_modified": "2026-01-20 14:45:00", "size": None},
    ],
    # Analysis subfolder (2 levels deep)
    "p1001/RNAseq_Results_2026-01-20/analysis": [
        {"name": "volcano_plot.png", "type": "file", "last_modified": "2026-01-20 14:42:00", "size": 156000},
        {"name": "heatmap.png", "type": "file", "last_modified": "2026-01-20 14:43:00", "size": 234000},
    ],
    # Project p2220 (minimal)
    "p2220": [
        {"name": "DataSteward_UZH", "type": "folder", "last_modified": "2026-01-27 09:15:14", "size": None},
        {"name": "HumanCtrl_Fastqc_2026-01-26", "type": "folder", "last_modified": "2026-01-26 14:15:33", "size": None},
    ],
}


@router.get("/")
def get_directory_contents(
    current_user: CurrentUserDep,
    path: str = "",
) -> dict:
    """Get directory contents for gStore file browser.

    MOCK: Returns hardcoded directory structure.
    Real implementation would query the gStore/file system.

    Args:
        path: Directory path (e.g., "p1001/FastQC_2026-01-15")

    Returns:
        Directory contents with items, current path, and parent path.
    """
    # Normalize path (remove leading/trailing slashes)
    normalized_path = path.strip("/")

    # Get items for this path
    items = MOCK_FILE_SYSTEM.get(normalized_path)

    if items is None:
        raise HTTPException(status_code=404, detail=f"Path not found: {path}")

    # Sort by name (folders first, then files)
    sorted_items = sorted(
        items,
        key=lambda x: (0 if x["type"] == "folder" else 1, x["name"]),
    )

    # Calculate parent path
    path_parts = normalized_path.split("/") if normalized_path else []
    parent_path = "/".join(path_parts[:-1]) if len(path_parts) > 1 else None

    return {
        "current_path": normalized_path or "/",
        "parent_path": parent_path,
        "total_items": len(sorted_items),
        "items": sorted_items,
    }


@router.get("/download")
def get_download_url(
    current_user: CurrentUserDep,
    path: str,
) -> dict:
    """Get download URL for a file.

    MOCK: Returns a placeholder URL.
    Real implementation would generate a presigned URL or stream the file.
    """
    return {
        "download_url": f"/api/files/stream?path={path}",
        "filename": path.split("/")[-1] if "/" in path else path,
    }
