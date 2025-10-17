# Dataset API Endpoints

This document describes the high-priority Dataset API endpoints that have been implemented.

## Implemented Endpoints

### 1. GET `/api/v1/datasets/:id/tree`

Returns the tree structure containing the parent tree (up to root) and all children (recursively) of the specified dataset.

#### Request
```bash
GET /api/v1/datasets/281/tree
Authorization: Bearer <jwt_token>
```

#### Response Example
```json
[
  {
    "id": 279,
    "name": "Grandparent Dataset",
    "comment": "Root level",
    "parent": "#"
  },
  {
    "id": 280,
    "name": "Parent Dataset",
    "parent": 279
  },
  {
    "id": 281,
    "name": "Current Dataset",
    "parent": 280
  },
  {
    "id": 282,
    "name": "Child Dataset",
    "parent": 281
  }
]
```

#### Field Descriptions
- `id`: Dataset ID
- `name`: Dataset name
- `comment`: Comment (optional, only included when present)
- `parent`: Parent dataset ID (root nodes use `"#"`)

#### Error Responses
- `404 Not Found`: When the dataset is not found
- `401 Unauthorized`: When JWT authentication is required and the token is invalid or missing

---

### 2. GET `/api/v1/datasets/:id/runnable_apps`

Returns runnable applications grouped by category based on the dataset's headers.

#### Request
```bash
GET /api/v1/datasets/281/runnable_apps
Authorization: Bearer <jwt_token>
```

#### Response Example
```json
[
  {
    "category": "QC",
    "applications": ["FastqcApp", "MultiQCApp"]
  },
  {
    "category": "Mapping",
    "applications": ["BwaApp", "BowtieApp", "StarApp"]
  },
  {
    "category": "Misc",
    "applications": ["CustomApp"]
  }
]
```

#### Field Descriptions
- `category`: Application category (e.g., "QC", "Mapping", "singleCell", "genomics")
- `applications`: Array of runnable application names in this category

#### Runnable Application Determination
An application is considered runnable when the dataset's headers satisfy the `required_columns` of the `SushiApplication`.

#### Error Responses
- `404 Not Found`: When the dataset is not found
- `401 Unauthorized`: When JWT authentication is required and the token is invalid or missing

---

### 3. GET `/api/v1/datasets/:id/samples`

Returns all samples contained in the dataset.

#### Request
```bash
GET /api/v1/datasets/281/samples
Authorization: Bearer <jwt_token>
```

#### Response Example
```json
[
  {
    "Name": "Sample1",
    "Read1": "path/to/read1.fastq",
    "Read2": "path/to/read2.fastq",
    "Concentration": "100"
  },
  {
    "Name": "Sample2",
    "Read1": "path/to/read1_2.fastq",
    "Read2": "path/to/read2_2.fastq",
    "Concentration": "150"
  }
]
```

#### Field Descriptions
Samples have a dynamic structure. The fields of each sample depend on the dataset's headers.
Common fields:
- `Name`: Sample name (typically always present)
- Other fields vary depending on the dataset schema

#### Features
- Each sample can have different column structures
- An empty array indicates the dataset contains no samples

#### Error Responses
- `404 Not Found`: When the dataset is not found
- `401 Unauthorized`: When JWT authentication is required and the token is invalid or missing

---

## Authentication

All endpoints require JWT authentication (except in development environments where authentication is skipped).

### Obtaining a JWT Token

```bash
POST /api/v1/auth/login
Content-Type: application/json

{
  "login": "your_username",
  "password": "your_password"
}
```

Response:
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": 1,
    "login": "your_username",
    "email": "your@email.com"
  }
}
```

### Using the Token

Include the obtained token in the Authorization header:

```bash
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

---

## Usage Examples

### JavaScript (Fetch API)

```javascript
const API_BASE_URL = 'http://localhost:3000/api/v1';
const token = localStorage.getItem('jwt_token');

// Get dataset tree
async function getDatasetTree(datasetId) {
  const response = await fetch(`${API_BASE_URL}/datasets/${datasetId}/tree`, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    }
  });
  
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }
  
  return await response.json();
}

// Get runnable applications
async function getRunnableApps(datasetId) {
  const response = await fetch(`${API_BASE_URL}/datasets/${datasetId}/runnable_apps`, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    }
  });
  
  return await response.json();
}

// Get dataset samples
async function getDatasetSamples(datasetId) {
  const response = await fetch(`${API_BASE_URL}/datasets/${datasetId}/samples`, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    }
  });
  
  return await response.json();
}

// Usage example
const datasetId = 281;

getDatasetTree(datasetId)
  .then(tree => console.log('Dataset tree:', tree))
  .catch(error => console.error('Error:', error));

getRunnableApps(datasetId)
  .then(apps => console.log('Runnable apps:', apps))
  .catch(error => console.error('Error:', error));

getDatasetSamples(datasetId)
  .then(samples => console.log('Samples:', samples))
  .catch(error => console.error('Error:', error));
```

### cURL

```bash
# Set token in environment variable
TOKEN="your_jwt_token_here"

# Get tree
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/v1/datasets/281/tree

# Get runnable applications
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/v1/datasets/281/runnable_apps

# Get samples
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/v1/datasets/281/samples
```

---

## Testing

The implemented endpoints are fully tested.

### Running Tests

```bash
cd backend
bundle exec rspec spec/requests/api/v1/datasets_controller_spec.rb
```

### Test Coverage

- ✅ Authentication tests (both JWT-required and authentication-skipped scenarios)
- ✅ Happy path tests (basic functionality of each endpoint)
- ✅ Error handling (404 errors, etc.)
- ✅ Data structure validation
- ✅ Edge cases (empty data, etc.)

---

## Implementation Details

### Controller
- `backend/app/controllers/api/v1/datasets_controller.rb`

### Routes
- `backend/config/routes.rb`

### Tests
- `backend/spec/requests/api/v1/datasets_controller_spec.rb`

### Related Models
- `DataSet` - Dataset information
- `Sample` - Sample information
- `SushiApplication` - Application information

---

## Related APIs

### Implemented - Medium Priority
- `GET /api/v1/projects/:project_number/jobs` - List jobs for a project with pagination and filtering
  - See [api-project-jobs-endpoint.md](./api-project-jobs-endpoint.md) for detailed documentation

### Future Plans - Low Priority APIs (Not yet implemented)
- `GET /api/v1/application-config/:appName` - Application configuration field information

These APIs will be implemented as needed.

