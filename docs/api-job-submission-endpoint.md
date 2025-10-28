# Job Submission API Endpoint

This document describes the Job Submission API endpoints for submitting and managing analysis jobs.

## Overview

The Job Submission API allows users to:
- Submit new analysis jobs using SUSHI applications
- Generate job scripts automatically
- Create output datasets linked to jobs
- Track job status and retrieve job information

## Base URL

```
/api/v1/jobs
```

## Authentication

- **JWT Token**: Required unless authentication is explicitly disabled via `SKIP_AUTHENTICATION` environment variable
- **Header**: `Authorization: Bearer <token>`

---

## Endpoints

### 1. Submit New Job

**POST** `/api/v1/jobs`

Submits a new analysis job for processing. This endpoint:
1. Validates the input dataset and application
2. Generates a job script based on the application and parameters
3. Creates an output dataset to store results
4. Registers the job in the database with status "CREATED"

#### Request Body

```json
{
  "job": {
    "dataset_id": 9,
    "app_name": "FastqcApp",
    "parameters": {
      "cores": 8,
      "ram": 15,
      "scratch": 100,
      "paired": false,
      "showNativeReports": false
    },
    "next_dataset_name": "FastQC_result",
    "next_dataset_comment": "Quality control analysis"
  }
}
```

#### Request Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `dataset_id` | Integer | Yes | ID of the input dataset |
| `app_name` | String | Yes | Name of the SUSHI application (e.g., "FastqcApp") |
| `parameters` | Object | No | Application-specific parameters |
| `next_dataset_name` | String | No | Name for the output dataset (auto-generated if not provided) |
| `next_dataset_comment` | String | No | Comment/description for the output dataset |

#### Response (201 Created)

```json
{
  "job": {
    "id": 1,
    "status": "CREATED",
    "user": "sushi_lover",
    "input_dataset_id": 9,
    "next_dataset_id": 10,
    "created_at": "2025-10-24T12:34:56Z"
  },
  "output_dataset": {
    "id": 10,
    "name": "FastQC_result"
  },
  "message": "Job submitted successfully"
}
```

#### Error Responses

**422 Unprocessable Entity** - Invalid parameters

```json
{
  "errors": [
    "Dataset not found: 999"
  ]
}
```

**422 Unprocessable Entity** - Invalid application

```json
{
  "errors": [
    "Application not found: InvalidApp"
  ]
}
```

**500 Internal Server Error** - Unexpected error

```json
{
  "error": "Job submission failed",
  "message": "Error details..."
}
```

---

### 2. Get Job Details

**GET** `/api/v1/jobs/:id`

Retrieves detailed information about a specific job.

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | Integer (URL) | Yes | Job ID |

#### Response (200 OK)

```json
{
  "job": {
    "id": 1,
    "status": "CREATED",
    "user": "sushi_lover",
    "input_dataset_id": 9,
    "next_dataset_id": 10,
    "created_at": "2025-10-24T12:34:56Z",
    "script_path": "/path/to/job_script.sh",
    "submit_job_id": null,
    "start_time": null,
    "end_time": null,
    "updated_at": "2025-10-24T12:34:56Z"
  }
}
```

#### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | Integer | Job ID |
| `status` | String | Job status (CREATED, RUNNING, COMPLETED, FAILED, etc.) |
| `user` | String | Username who submitted the job |
| `input_dataset_id` | Integer | ID of the input dataset |
| `next_dataset_id` | Integer | ID of the output dataset |
| `script_path` | String | Path to the generated job script |
| `submit_job_id` | Integer | External job manager ID (if submitted) |
| `start_time` | String | Job start timestamp (ISO8601) |
| `end_time` | String | Job end timestamp (ISO8601) |
| `created_at` | String | Record creation timestamp (ISO8601) |
| `updated_at` | String | Record update timestamp (ISO8601) |

#### Error Response

**404 Not Found** - Job doesn't exist

```json
{
  "error": "Job not found"
}
```

---

### 3. List Jobs

**GET** `/api/v1/jobs`

Returns a list of jobs with optional filtering and pagination.

#### Query Parameters

| Parameter | Type | Default | Max | Description |
|-----------|------|---------|-----|-------------|
| `page` | Integer | 1 | - | Page number for pagination |
| `per` | Integer | 50 | 200 | Number of jobs per page |
| `status` | String | - | - | Filter by job status |
| `user` | String | - | - | Filter by username |

#### Response (200 OK)

```json
{
  "jobs": [
    {
      "id": 3,
      "status": "CREATED",
      "user": "alice",
      "input_dataset_id": 15,
      "next_dataset_id": 16,
      "created_at": "2025-10-24T14:00:00Z"
    },
    {
      "id": 2,
      "status": "RUNNING",
      "user": "bob",
      "input_dataset_id": 12,
      "next_dataset_id": 13,
      "created_at": "2025-10-24T13:30:00Z"
    }
  ],
  "total_count": 25,
  "page": 1,
  "per": 50
}
```

---

## Usage Examples

### cURL

```bash
# Submit a job
curl -X POST http://localhost:4050/api/v1/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "job": {
      "dataset_id": 9,
      "app_name": "FastqcApp",
      "parameters": {
        "cores": 8,
        "ram": 15,
        "scratch": 100
      },
      "next_dataset_name": "FastQC_result"
    }
  }'

# Get job details
curl http://localhost:4050/api/v1/jobs/1

# List all jobs
curl http://localhost:4050/api/v1/jobs

# Filter jobs by status
curl http://localhost:4050/api/v1/jobs?status=RUNNING

# Filter jobs by user
curl http://localhost:4050/api/v1/jobs?user=alice
```

### Python (requests)

```python
import requests

API_BASE_URL = 'http://localhost:4050/api/v1'

# Submit a job
response = requests.post(
    f'{API_BASE_URL}/jobs',
    json={
        'job': {
            'dataset_id': 9,
            'app_name': 'FastqcApp',
            'parameters': {
                'cores': 8,
                'ram': 15,
                'scratch': 100
            },
            'next_dataset_name': 'FastQC_result'
        }
    }
)

if response.status_code == 201:
    job_data = response.json()
    job_id = job_data['job']['id']
    print(f"Job submitted: {job_id}")
    
    # Get job details
    job_response = requests.get(f'{API_BASE_URL}/jobs/{job_id}')
    print(job_response.json())
else:
    print(f"Error: {response.json()}")
```

---

## Job Submission Flow

1. **Client submits job** via POST `/api/v1/jobs`
2. **API validates** input dataset and application
3. **API loads** the SUSHI application class
4. **API configures** application with user parameters
5. **API generates** job script file
6. **API creates** output dataset record
7. **API saves** job record with status "CREATED"
8. **Job Manager** (external) picks up jobs and executes them
9. **Job Manager** updates job status (RUNNING, COMPLETED, FAILED)

---

## Job Status Values

| Status | Description |
|--------|-------------|
| `CREATED` | Job has been created and is waiting to be picked up |
| `RUNNING` | Job is currently executing |
| `COMPLETED` | Job finished successfully |
| `FAILED` | Job failed during execution |
| `CANCELLED` | Job was cancelled by user or system |

---

## Implementation Details

### Controller
- `backend/app/controllers/api/v1/jobs_controller.rb`

### Service
- `backend/app/services/job_submission_service.rb`

### Routes
- `backend/config/routes.rb`

### Related Models
- `Job` - Job records
- `DataSet` - Input and output datasets
- `Sample` - Dataset samples

---

## Testing

### Automated Tests
```bash
cd backend
bundle exec rspec spec/requests/api/v1/jobs_controller_spec.rb
```

### Manual Testing
```bash
cd backend
./test_job_submission.sh
```

---

## Notes

- Job scripts are generated in `tmp/job_scripts/` directory by default
- Output datasets are automatically created and linked to jobs
- Job parameters are stored in the output dataset's `job_parameters` field
- The actual job execution is handled by an external Job Manager (not part of this API)
- Jobs remain in "CREATED" status until picked up by the Job Manager


