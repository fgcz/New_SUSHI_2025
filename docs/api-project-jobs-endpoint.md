# Project Jobs API Endpoint

This document describes the medium-priority Project Jobs API endpoint that has been implemented.

## Implemented Endpoint

### GET `/api/v1/projects/:projectNumber/jobs`

Returns jobs for a specific project with pagination and filtering support. This endpoint is designed for high performance even with projects containing thousands of jobs.

#### Request

```bash
GET /api/v1/projects/1001/jobs
Authorization: Bearer <jwt_token>
```

#### Query Parameters

| Parameter | Type | Default | Max | Description |
|-----------|------|---------|-----|-------------|
| `page` | integer | 1 | - | Page number for pagination |
| `per` | integer | 50 | 200 | Number of jobs per page |
| `status` | string | - | - | Filter by job status (e.g., "COMPLETED", "FAILED", "RUNNING") |
| `user` | string | - | - | Filter by username |
| `dataset_id` | integer | - | - | Filter by specific dataset ID |
| `from_date` | string | - | - | Filter by start date (YYYY-MM-DD format) |
| `to_date` | string | - | - | Filter by end date (YYYY-MM-DD format) |

#### Response Example

**Basic request with pagination:**
```bash
GET /api/v1/projects/1001/jobs?page=1&per=20
```

```json
{
  "jobs": [
    {
      "id": 19,
      "submit_job_id": 34347,
      "status": "COMPLETED",
      "user": "degottardiraphael",
      "dataset": {
        "id": 28,
        "name": "Spatial_VisiumHD_analysis_result"
      },
      "time": {
        "start_time": "2025-04-04T14:13:36+02:00",
        "end_time": "2025-04-04T14:56:04+02:00"
      },
      "created_at": "2025-04-04T14:13:28+02:00"
    },
    {
      "id": 18,
      "submit_job_id": 34337,
      "status": "FAILED",
      "user": "degottardiraphael",
      "dataset": {
        "id": 27,
        "name": "Spatial_VisiumHD_mb_data"
      },
      "time": {
        "start_time": "2025-04-04T10:15:53+02:00",
        "end_time": "2025-04-04T10:58:50+02:00"
      },
      "created_at": "2025-04-04T10:15:37+02:00"
    }
  ],
  "total_count": 156,
  "page": 1,
  "per": 20,
  "project_number": 1001,
  "filters": {}
}
```

**Request with filters:**
```bash
GET /api/v1/projects/1001/jobs?status=FAILED&user=masaomi&from_date=2025-04-01&to_date=2025-04-30&page=1&per=50
```

```json
{
  "jobs": [
    {
      "id": 1,
      "submit_job_id": 33738,
      "status": "FAILED",
      "user": "masaomi",
      "dataset": {
        "id": 2,
        "name": "Testing_test_EzPyzApp"
      },
      "time": {
        "start_time": "2025-04-01T10:30:04+02:00",
        "end_time": "2025-04-01T10:30:38+02:00"
      },
      "created_at": "2025-04-01T10:29:41+02:00"
    }
  ],
  "total_count": 1,
  "page": 1,
  "per": 50,
  "project_number": 1001,
  "filters": {
    "status": "FAILED",
    "user": "masaomi",
    "from_date": "2025-04-01",
    "to_date": "2025-04-30"
  }
}
```

#### Field Descriptions

**Job Object:**
- `id`: Job ID
- `submit_job_id`: Submission job ID (from job scheduler)
- `status`: Job status (e.g., "COMPLETED", "FAILED", "RUNNING", "PENDING")
- `user`: Username who submitted the job
- `dataset`: Associated dataset object (or null if dataset is not available)
  - `id`: Dataset ID
  - `name`: Dataset name
- `time`: Time information
  - `start_time`: Job start time in ISO8601 format
  - `end_time`: Job end time in ISO8601 format (optional, null if job is still running)
- `created_at`: Job creation time in ISO8601 format

**Response Metadata:**
- `total_count`: Total number of jobs matching the filters
- `page`: Current page number
- `per`: Number of jobs per page
- `project_number`: Project number
- `filters`: Active filters applied to the query

#### Performance Optimizations

This endpoint is designed for high performance with large datasets:

1. **Pagination**: Default 50 jobs per page, maximum 200 per page
2. **Efficient Database Queries**: Uses eager loading to avoid N+1 queries
3. **Reduced Response Size**: Large fields like `submit_command` and file paths are intentionally excluded
4. **Indexed Queries**: Database indexes on `status` field for fast filtering
5. **Early Returns**: Empty result handling to avoid unnecessary queries

#### Error Responses

- `403 Forbidden`: When the project is not accessible to the current user
  ```json
  {
    "error": "Project not accessible"
  }
  ```

- `404 Not Found`: When the project does not exist (only after authorization check)
  ```json
  {
    "error": "Project not found"
  }
  ```

- `401 Unauthorized`: When JWT authentication is required and the token is invalid or missing

---

## Usage Examples

### JavaScript (Fetch API)

```javascript
const API_BASE_URL = 'http://localhost:3000/api/v1';
const token = localStorage.getItem('jwt_token');

// Get paginated jobs for a project
async function getProjectJobs(projectNumber, options = {}) {
  const params = new URLSearchParams({
    page: options.page || 1,
    per: options.per || 50,
    ...(options.status && { status: options.status }),
    ...(options.user && { user: options.user }),
    ...(options.dataset_id && { dataset_id: options.dataset_id }),
    ...(options.from_date && { from_date: options.from_date }),
    ...(options.to_date && { to_date: options.to_date })
  });
  
  const response = await fetch(
    `${API_BASE_URL}/projects/${projectNumber}/jobs?${params}`,
    {
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      }
    }
  );
  
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }
  
  return await response.json();
}

// Usage examples

// Get first page of jobs
getProjectJobs(1001)
  .then(data => {
    console.log('Total jobs:', data.total_count);
    console.log('Jobs:', data.jobs);
  })
  .catch(error => console.error('Error:', error));

// Get completed jobs only
getProjectJobs(1001, { status: 'COMPLETED', per: 100 })
  .then(data => console.log('Completed jobs:', data.jobs))
  .catch(error => console.error('Error:', error));

// Get jobs by specific user
getProjectJobs(1001, { user: 'alice', page: 1 })
  .then(data => console.log('User jobs:', data.jobs))
  .catch(error => console.error('Error:', error));

// Get jobs for a date range
getProjectJobs(1001, {
  from_date: '2025-04-01',
  to_date: '2025-04-30',
  status: 'FAILED'
})
  .then(data => console.log('Failed jobs in April:', data.jobs))
  .catch(error => console.error('Error:', error));

// Get jobs for a specific dataset
getProjectJobs(1001, { dataset_id: 123 })
  .then(data => console.log('Dataset jobs:', data.jobs))
  .catch(error => console.error('Error:', error));
```

### cURL

```bash
# Set token in environment variable
TOKEN="your_jwt_token_here"

# Get paginated jobs
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/projects/1001/jobs?page=1&per=20"

# Filter by status
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/projects/1001/jobs?status=COMPLETED"

# Filter by user
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/projects/1001/jobs?user=alice"

# Filter by date range
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/projects/1001/jobs?from_date=2025-04-01&to_date=2025-04-30"

# Combine multiple filters
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/projects/1001/jobs?status=FAILED&user=masaomi&page=1&per=50"

# Filter by dataset
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/projects/1001/jobs?dataset_id=123"
```

### Python (requests)

```python
import requests
from datetime import date, timedelta

API_BASE_URL = 'http://localhost:3000/api/v1'
token = 'your_jwt_token_here'

headers = {
    'Authorization': f'Bearer {token}',
    'Content-Type': 'application/json'
}

def get_project_jobs(project_number, **filters):
    """Get jobs for a project with optional filters"""
    params = {
        'page': filters.get('page', 1),
        'per': filters.get('per', 50)
    }
    
    # Add optional filters
    if 'status' in filters:
        params['status'] = filters['status']
    if 'user' in filters:
        params['user'] = filters['user']
    if 'dataset_id' in filters:
        params['dataset_id'] = filters['dataset_id']
    if 'from_date' in filters:
        params['from_date'] = filters['from_date']
    if 'to_date' in filters:
        params['to_date'] = filters['to_date']
    
    response = requests.get(
        f'{API_BASE_URL}/projects/{project_number}/jobs',
        headers=headers,
        params=params
    )
    response.raise_for_status()
    return response.json()

# Usage examples
try:
    # Get all jobs
    data = get_project_jobs(1001)
    print(f"Total jobs: {data['total_count']}")
    
    # Get completed jobs
    data = get_project_jobs(1001, status='COMPLETED')
    print(f"Completed jobs: {len(data['jobs'])}")
    
    # Get jobs from last week
    last_week = (date.today() - timedelta(days=7)).isoformat()
    today = date.today().isoformat()
    data = get_project_jobs(1001, from_date=last_week, to_date=today)
    print(f"Jobs in last week: {len(data['jobs'])}")
    
except requests.exceptions.HTTPError as e:
    print(f"Error: {e}")
```

---

## Common Use Cases

### 1. Dashboard - Recent Job Activity
```javascript
// Get the 10 most recent jobs
getProjectJobs(projectNumber, { page: 1, per: 10 });
```

### 2. Job Monitoring - Failed Jobs
```javascript
// Get all failed jobs for investigation
getProjectJobs(projectNumber, { status: 'FAILED', per: 100 });
```

### 3. User Activity Report
```javascript
// Get all jobs by a specific user
getProjectJobs(projectNumber, { user: 'john_doe', per: 200 });
```

### 4. Dataset Pipeline Tracking
```javascript
// Get all jobs related to a specific dataset
getProjectJobs(projectNumber, { dataset_id: 456 });
```

### 5. Monthly Report
```javascript
// Get all jobs for a specific month
getProjectJobs(projectNumber, {
  from_date: '2025-04-01',
  to_date: '2025-04-30'
});
```

---

## Testing

The endpoint is fully tested with comprehensive test coverage.

### Running Tests

```bash
cd backend
bundle exec rspec spec/requests/api/v1/projects_controller_spec.rb
```

### Test Coverage

- ✅ Pagination tests (page, per parameters, limits)
- ✅ Filter tests (status, user, dataset_id, date range)
- ✅ Combined filter tests
- ✅ Authentication tests (JWT-required and authentication-skipped scenarios)
- ✅ Authorization tests (accessible/inaccessible projects)
- ✅ Error handling (403, 404 errors)
- ✅ Empty result handling
- ✅ Response format validation
- ✅ Data structure validation

---

## Implementation Details

### Controller
- `backend/app/controllers/api/v1/projects_controller.rb`

### Routes
- `backend/config/routes.rb`

### Tests
- `backend/spec/requests/api/v1/projects_controller_spec.rb`

### Related Models
- `Job` - Job information
- `DataSet` - Dataset information
- `Project` - Project information

---

## Future Enhancements (Optional)

These optimizations can be added if needed:

### 1. Database Indexes
Add additional indexes for frequently filtered columns:
```ruby
add_index :jobs, :user
add_index :jobs, :start_time
add_index :jobs, [:next_dataset_id, :status]
```

### 2. Job Details Endpoint
For retrieving complete job information including large fields:
```
GET /api/v1/jobs/:id/details
```

### 3. Job Statistics Endpoint
For dashboard summary information:
```
GET /api/v1/projects/:projectNumber/jobs/stats
```

Response:
```json
{
  "total": 1234,
  "by_status": {
    "COMPLETED": 1000,
    "FAILED": 150,
    "RUNNING": 84
  },
  "by_user": {
    "alice": 567,
    "bob": 432
  }
}
```

### 4. Caching
Implement caching for frequently accessed data (e.g., job statistics).

---

## Notes

- Large fields like `submit_command`, `script_path`, `stdout_path`, and `stderr_path` are intentionally excluded from the response to reduce payload size
- Jobs are ordered by `created_at` descending (most recent first)
- The endpoint handles projects with thousands of jobs efficiently through pagination
- Empty projects (no datasets) return an empty jobs array with `total_count: 0`

