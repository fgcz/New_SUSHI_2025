# Job Submission API - UI Integration Guide

## Overview

The Job Submission API has been implemented and is ready for frontend integration. This API enables users to submit bioinformatics analysis jobs, track their status, and manage output datasets through the SUSHI web interface.

**Key Capability**: The API handles job script generation and metadata registration. Actual job execution is managed by a separate Job Manager component (not part of this API).

## Available Endpoints

### 1. Submit a Job

**POST** `/api/v1/jobs`

Submit a new job for analysis. This endpoint will:
- Generate a job script based on the selected SushiApp
- Create an output dataset linked to the input dataset
- Register job metadata in the database with status "CREATED"

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
      "paired": false
    },
    "next_dataset_name": "FastQC_result",
    "next_dataset_comment": "Quality control analysis"
  }
}
```

**Parameters:**
- `dataset_id` (required): ID of the input dataset
- `app_name` (required): Name of the SushiApp class (e.g., "FastqcApp", "STARApp")
- `parameters` (required): Hash of application-specific parameters
- `next_dataset_name` (optional): Name for the output dataset (auto-generated if not provided)
- `next_dataset_comment` (optional): Description for the output dataset

#### Response (Success - 201 Created)

```json
{
  "job": {
    "id": 211,
    "status": "CREATED",
    "user": "anonymous",
    "input_dataset_id": 9,
    "next_dataset_id": 281,
    "created_at": "2025-10-28T10:05:49Z"
  },
  "output_dataset": {
    "id": 281,
    "name": "FastQC_result"
  },
  "message": "Job submitted successfully"
}
```

#### Response (Error - 422 Unprocessable Entity)

```json
{
  "errors": [
    "Dataset not found: 999",
    "Application not found: InvalidApp"
  ]
}
```

### 2. Get Job Details

**GET** `/api/v1/jobs/:id`

Retrieve detailed information about a specific job.

#### Response Example

```json
{
  "job": {
    "id": 211,
    "status": "CREATED",
    "user": "anonymous",
    "input_dataset_id": 9,
    "next_dataset_id": 281,
    "created_at": "2025-10-28T10:05:49Z",
    "updated_at": "2025-10-28T10:05:49Z",
    "script_path": "/srv/sushi/.../job_scripts/FastqcApp_9_20251028110549108.sh",
    "submit_job_id": null,
    "start_time": null,
    "end_time": null
  }
}
```

**Job Status Values:**
- `CREATED` - Job registered, script generated, waiting for execution
- `SUBMITTED` - Sent to job queue (managed by Job Manager)
- `RUNNING` - Currently executing (managed by Job Manager)
- `COMPLETED` - Successfully finished (managed by Job Manager)
- `FAILED` - Execution failed (managed by Job Manager)

### 3. List Jobs

**GET** `/api/v1/jobs?page=1&per=20`

Retrieve a paginated list of jobs.

#### Query Parameters

- `page` (optional, default: 1): Page number
- `per` (optional, default: 20): Number of jobs per page

#### Response Example

```json
{
  "jobs": [
    {
      "id": 211,
      "status": "CREATED",
      "user": "anonymous",
      "input_dataset_id": 9,
      "next_dataset_id": 281,
      "created_at": "2025-10-28T10:05:49Z"
    },
    {
      "id": 210,
      "status": "COMPLETED",
      "user": "masaomi",
      "input_dataset_id": 9,
      "next_dataset_id": 278,
      "created_at": "2025-06-18T18:13:50Z"
    }
  ],
  "total_count": 211,
  "page": 1,
  "per": 20
}
```

## Related Endpoints

### Get Dataset Information

**GET** `/api/v1/datasets/:id`

Retrieve dataset details including samples, headers, and runnable applications.

This endpoint is useful for:
- Displaying input dataset information before job submission
- Showing available applications for a dataset
- Getting dataset parameters

### Get Application Configuration

**GET** `/api/v1/application_configs/:app_name`

Retrieve application configuration including required parameters and their default values.

This endpoint is useful for:
- Generating dynamic forms for application parameters
- Showing parameter descriptions and constraints
- Pre-filling default values

## UI Implementation Checklist

### Job Submission Flow

- [ ] Dataset selection interface
  - [ ] Display dataset name, samples count, project info
  - [ ] Show dataset headers and sample data
- [ ] Application selection interface
  - [ ] Filter applications by dataset compatibility
  - [ ] Display application name and description
- [ ] Parameter input form
  - [ ] Dynamic form generation based on app configuration
  - [ ] Input validation (required fields, data types, ranges)
  - [ ] Default value pre-filling
- [ ] Job submission button with loading state
- [ ] Success notification with job ID and output dataset link
- [ ] Error handling with user-friendly messages

### Job Management Interface

- [ ] Job list view (table or card layout)
  - [ ] Display job ID, status, user, created date
  - [ ] Link to input/output datasets
  - [ ] Status badges with appropriate colors
  - [ ] Sorting and filtering options
- [ ] Job details view (modal or dedicated page)
  - [ ] Full job information
  - [ ] Link to job script file
  - [ ] Execution timeline (if available)
  - [ ] Error messages (if failed)
- [ ] Pagination controls
- [ ] Real-time status updates (polling or WebSocket)

### User Experience Considerations

- [ ] Confirmation dialog before job submission
- [ ] Estimated resource usage display (cores, RAM, scratch space)
- [ ] Previous job parameters as templates
- [ ] Bulk job submission for multiple datasets

## User Flow Example

```
1. User navigates to Datasets page
   └─> GET /api/v1/datasets

2. User clicks on a dataset (e.g., "ventricles_100k")
   └─> GET /api/v1/datasets/9
   └─> Display dataset details and available applications

3. User selects an application (e.g., "FastqcApp")
   └─> GET /api/v1/application_configs/FastqcApp (optional)
   └─> Show parameter form

4. User fills in parameters and clicks "Submit Job"
   └─> POST /api/v1/jobs
   └─> Show success message: "Job #211 created successfully"

5. User navigates to Jobs page to monitor progress
   └─> GET /api/v1/jobs?page=1&per=20
   └─> Display job list with status

6. User clicks on a job to see details
   └─> GET /api/v1/jobs/211
   └─> Show detailed information in modal or dedicated page
```

## Important Notes

### Authentication

- **JWT Required**: All endpoints require JWT authentication
- **Test Mode**: Set `SKIP_AUTHENTICATION=true` environment variable to bypass authentication during development
- **User Context**: Jobs are associated with the authenticated user

### Job Status Lifecycle

```
CREATED → SUBMITTED → RUNNING → COMPLETED
                              ↘ FAILED
```

- **CREATED**: Job record exists, script generated (handled by SUSHI API)
- **SUBMITTED, RUNNING, COMPLETED, FAILED**: Managed by external Job Manager
- **UI Consideration**: Poll job status periodically or implement WebSocket for real-time updates

### Application Parameters

- Each SushiApp has different required and optional parameters
- Use `GET /api/v1/application_configs/:app_name` to get parameter definitions
- Common parameters: `cores`, `ram`, `scratch`
- Application-specific parameters vary (e.g., `paired` for FastqcApp, `refBuild` for aligners)

### Dataset Relationships

- **Input Dataset**: The dataset being analyzed (selected by user)
- **Output Dataset**: Automatically created when job is submitted
- **Parent-Child Relationship**: Output dataset is linked to input dataset via `parent_id`
- **Navigation**: Users should be able to navigate between related datasets

### Error Handling

Common error scenarios:
- **Dataset not found**: Invalid dataset_id provided
- **Application not found**: Invalid app_name or app file missing
- **Invalid parameters**: Required parameters missing or incorrect type
- **Authentication failure**: JWT token missing or invalid

Always display user-friendly error messages and suggest corrective actions.

## Testing

### Manual Testing

A test script is available at `docs/examples/test_job_submission.sh` for manual API testing.

To run:
```bash
cd backend
bash ../docs/examples/test_job_submission.sh
```

### API Response Examples

All example requests and responses can be found in:
- `docs/api-job-submission-endpoint.md` - Detailed API specifications
- `docs/job-submission-implementation-plan.md` - Implementation architecture

## Technical Details

### Job Script Generation

- Scripts are generated based on SushiApp class definitions
- Stored in: `backend/tmp/job_scripts/` (configurable via `SUBMIT_JOB_SCRIPT_DIR`)
- Format: `{AppName}_{DatasetId}_{Timestamp}.sh`
- Scripts are executable bash files with proper shebang and error handling

### Output Dataset Structure

- Automatically created with predefined structure based on SushiApp
- Contains expected output file paths (will be created when job runs)
- Linked to input dataset for traceability
- Includes job parameters for reproducibility

### Performance Considerations

- Job list endpoint supports pagination (default: 20 per page)
- Consider implementing filtering by status, user, date range
- Lazy loading for large job lists
- Caching strategies for frequently accessed data

## Next Steps

1. **Review API Specifications**
   - Read `docs/api-job-submission-endpoint.md` for detailed specs
   - Test endpoints using the example script or Postman

2. **Design UI Components**
   - Create wireframes for job submission form
   - Design job list and detail views
   - Plan user flow and navigation

3. **Development**
   - Set up API client/service layer
   - Implement job submission form
   - Build job list and detail views
   - Add error handling and loading states

4. **Integration Testing**
   - Test with various SushiApps
   - Verify error scenarios
   - Test pagination and filtering
   - Validate data consistency

## Questions or Issues?

- **API Issues**: Check `backend/log/development.log` for detailed error messages
- **Documentation**: See `docs/` directory for comprehensive documentation
- **Contact**: [Your team contact information]

---

**Last Updated**: 2025-10-28  
**API Version**: v1  
**Status**: Ready for Integration ✅

