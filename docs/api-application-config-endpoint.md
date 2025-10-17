# Application Configuration API

## Overview

The Application Configuration API provides access to SUSHI application metadata, parameters, and form field definitions. This API dynamically parses `*App.rb` files from the `lib/apps/` directory to extract configuration without requiring database migrations or individual YAML files.

## Base URL

```
/api/v1/application_configs
```

## Authentication

- **JWT Token**: Required unless authentication is explicitly disabled via `SKIP_AUTHENTICATION` environment variable
- **Header**: `Authorization: Bearer <token>`

## Endpoints

### 1. List Available Applications

**GET** `/api/v1/application_configs`

Returns a list of all available SUSHI applications.

#### Response

```json
{
  "applications": [
    {
      "name": "Fastqc"
    },
    {
      "name": "CellRanger"
    }
  ],
  "total_count": 2
}
```

#### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `applications` | Array | List of available applications |
| `applications[].name` | String | Application name |
| `total_count` | Integer | Total number of applications |

---

### 2. Get Application Configuration

**GET** `/api/v1/application_configs/:app_name`

Returns detailed configuration for a specific application.

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `app_name` | String (URL) | Yes | Application name (case-insensitive) |

#### Example Request

```bash
curl -X GET "http://localhost:3000/api/v1/application_configs/Fastqc" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

#### Response

```json
{
  "application": {
    "name": "Fastqc",
    "class_name": "FastqcApp",
    "category": "QC",
    "description": "A quality control tool for NGS reads Web-site with docu and a tutorial video",
    "required_columns": [
      "Name",
      "Read1"
    ],
    "required_params": [
      "paired",
      "showNativeReports"
    ],
    "form_fields": [
      {
        "name": "cores",
        "type": "select",
        "default_value": 8,
        "options": [8, 1, 2, 4, 8]
      },
      {
        "name": "ram",
        "type": "select",
        "default_value": 15,
        "description": "GB",
        "options": [15, 30, 62]
      },
      {
        "name": "paired",
        "type": "boolean",
        "default_value": false
      },
      {
        "name": "specialOptions",
        "type": "text",
        "default_value": ""
      }
    ],
    "modules": [
      "QC/FastQC",
      "Dev/R",
      "Tools/Picard"
    ],
    "inherit_tags": [],
    "inherit_columns": ["Order Id"]
  }
}
```

#### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `application.name` | String | Display name of the application |
| `application.class_name` | String | Ruby class name (e.g., "FastqcApp") |
| `application.category` | String | Analysis category (e.g., "QC", "Map", "SingleCell") |
| `application.description` | String | HTML description of the application |
| `application.required_columns` | Array | Required dataset columns |
| `application.required_params` | Array | Required parameter names |
| `application.form_fields` | Array | Form field definitions |
| `application.modules` | Array | Required system modules |
| `application.inherit_tags` | Array | Tags to inherit from parent dataset |
| `application.inherit_columns` | Array | Columns to inherit from parent dataset |

#### Form Field Types

| Type | Description | Example |
|------|-------------|---------|
| `select` | Drop-down selection | cores, ram |
| `multi_select` | Multiple selection | transcriptTypes |
| `boolean` | Checkbox | paired, markDuplicates |
| `text` | Text input | specialOptions, cmdOptions |
| `integer` | Integer input | expectedCells |
| `number` | Numeric input | nReads |
| `section` | Section header | Used for grouping fields |

#### Form Field Properties

```json
{
  "name": "cores",
  "type": "select",
  "default_value": 8,
  "description": "Number of CPU cores",
  "options": [8, 1, 2, 4, 8],
  "multi_selection": false,
  "selected": [],
  "section_header": "Resource Allocation"
}
```

| Property | Type | Description |
|----------|------|-------------|
| `name` | String | Parameter name |
| `type` | String | Field type (see above) |
| `default_value` | Any | Default value for the field |
| `description` | String | Optional help text |
| `options` | Array | Available options for select/multi_select |
| `multi_selection` | Boolean | Allow multiple selections |
| `selected` | Array | Default selected options for multi_select |
| `section_header` | String | Section header text |
| `horizontal_rule` | Boolean | Display horizontal separator |

---

## Error Responses

### 404 Not Found

Application not found:

```json
{
  "error": "Application not found",
  "app_name": "NonExistentApp"
}
```

### 401 Unauthorized

Missing or invalid JWT token:

```json
{
  "error": "Unauthorized - JWT token required"
}
```

### 500 Internal Server Error

Server error during application parsing:

```json
{
  "error": "Internal server error",
  "message": "Error details..."
}
```

---

## Security Features

1. **Input Sanitization**: Application names are sanitized to prevent directory traversal attacks
2. **Case-Insensitive Lookup**: Application names are matched case-insensitively
3. **JWT Authentication**: All requests require valid JWT tokens (unless disabled)
4. **Error Handling**: Graceful error handling with appropriate status codes

---

## Implementation Details

### Application Parser

The `ApplicationConfigParser` service:

1. Loads `*App.rb` files from `backend/lib/apps/`
2. Instantiates the application class
3. Extracts configuration from instance variables:
   - `@name`, `@analysis_category`, `@description`
   - `@required_columns`, `@required_params`
   - `@params` (parsed into form fields)
   - `@modules`, `@inherit_tags`, `@inherit_columns`

### Form Field Inference

Field types are automatically inferred from parameter values:

- **Array values** → `select` or `multi_select` (based on metadata)
- **Boolean values** → `boolean`
- **Numeric values** → `integer` or `number`
- **String values** → `text`
- **Section headers** → `section` (based on `hr-header` metadata)

### Example: Adding New Applications

To add a new application:

1. Copy the `*App.rb` file to `backend/lib/apps/`
2. Ensure it inherits from `SushiFabric::SushiApp`
3. The API will automatically discover and parse it

No database migrations or YAML files required!

---

## Usage Examples

### JavaScript (fetch)

```javascript
// List all applications
const response = await fetch('/api/v1/application_configs', {
  headers: {
    'Authorization': `Bearer ${token}`
  }
});
const data = await response.json();
console.log(data.applications);

// Get specific application config
const configResponse = await fetch('/api/v1/application_configs/Fastqc', {
  headers: {
    'Authorization': `Bearer ${token}`
  }
});
const config = await configResponse.json();
console.log(config.application.form_fields);
```

### cURL

```bash
# List applications
curl -X GET "http://localhost:3000/api/v1/application_configs" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"

# Get Fastqc configuration
curl -X GET "http://localhost:3000/api/v1/application_configs/Fastqc" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### Python (requests)

```python
import requests

# Setup
base_url = "http://localhost:3000/api/v1"
headers = {"Authorization": f"Bearer {token}"}

# List applications
response = requests.get(f"{base_url}/application_configs", headers=headers)
apps = response.json()['applications']

# Get specific config
response = requests.get(f"{base_url}/application_configs/Fastqc", headers=headers)
config = response.json()['application']

# Build dynamic form from form_fields
for field in config['form_fields']:
    print(f"Field: {field['name']} (Type: {field['type']})")
    if 'options' in field:
        print(f"  Options: {field['options']}")
```

---

## Related APIs

- [Dataset Tree API](./api-datasets-endpoints.md) - Dataset hierarchy and relationships
- [Project Jobs API](./api-project-jobs-endpoint.md) - Job execution and monitoring

---

## Notes

- Application names are case-insensitive (e.g., "fastqc" matches "Fastqc")
- The parser handles complex parameter metadata including descriptions, multi-selection, and section headers
- Form field definitions are suitable for dynamic UI generation
- No database storage required - all data is parsed on-demand from Ruby files

