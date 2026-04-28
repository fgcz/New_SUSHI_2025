"""Serializers for converting SushiApp to API response format."""

from sushi_apps.base import SushiApp


def serialize_app_config(app: SushiApp) -> dict:
    """Convert app definition to frontend config format."""
    # Group parameters by their group id
    grouped: dict[str, list[dict]] = {}
    ungrouped: list[dict] = []

    for param in app.params_definition:
        group_id = param.get("group")
        field = _param_to_field(param)
        if group_id:
            if group_id not in grouped:
                grouped[group_id] = []
            grouped[group_id].append(field)
        else:
            ungrouped.append(field)

    # Build param_groups with fields
    result_groups = []
    for group in app.param_groups:
        group_id = group["id"]
        result_groups.append({
            "id": group_id,
            "title": group.get("title", group_id),
            "description": group.get("description", ""),
            "fields": grouped.get(group_id, []),
        })

    # Add ungrouped params as "Other" if any exist
    if ungrouped:
        result_groups.append({
            "id": "other",
            "title": "Other Parameters",
            "description": "",
            "fields": ungrouped,
        })

    return {
        "application": {
            "name": app.name,
            "category": app.category,
            "description": app.description,
            "required_columns": app.required_columns,
            "required_params": app.required_params,
            "param_groups": result_groups,
        }
    }


def _param_to_field(param: dict) -> dict:
    """Convert param definition to frontend field format."""
    field = {
        "name": param["name"],
        "type": param.get("type", "text"),
        "default_value": param.get("default"),
        "description": param.get("description", ""),
    }

    # Optional attributes
    if "options" in param:
        field["options"] = param["options"]
    if param.get("required"):
        field["required"] = True
    if param.get("multi_select"):
        field["multi_select"] = True
    if param.get("file_upload"):
        field["file_upload"] = True
    if param.get("disabled"):
        field["disabled"] = True
    if param.get("hidden"):
        field["hidden"] = True
    if "min" in param:
        field["min"] = param["min"]
    if "max" in param:
        field["max"] = param["max"]
    if "placeholder" in param:
        field["placeholder"] = param["placeholder"]

    return field
