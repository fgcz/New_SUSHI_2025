# Job Submission API Implementation Plan

## Overview

This document describes the implementation plan and architecture for the Job Submission API in the new SUSHI system. The goal is to enable programmatic job submission through a REST API, separate from the UI implementation, and clearly define the responsibilities between SUSHI API and the Job Manager component.

**Primary Goal**: Use DataSet information and SUSHIApp classes to generate job scripts and register job metadata in the database (up to `status="CREATED"`).

---

## Architecture Philosophy

### Separation of Concerns

The new SUSHI architecture clearly separates job processing into two distinct components:

#### 1. SUSHI API (This Implementation Scope)

**Responsibilities:**
- Generate job scripts using SUSHIApp instances
- Save scripts to designated directory (`submit_job_script_dir`)
- Register metadata in database:
  - Create output DataSet (with parent_id, project info, etc.)
  - Create Job record (script_path, input_dataset_id, next_dataset_id, user)
  - **Important**: Set `status="CREATED"` only (do not execute)
  - Leave `submit_job_id` as null (Job Manager will set this)

**Does NOT:**
- Submit jobs to execution systems (SLURM, AWS Batch, etc.)
- Monitor job execution
- Update job status beyond "CREATED"

#### 2. Job Manager (Separate Module - Outside SUSHI Scope)

**Responsibilities:**
- Poll database for `status="CREATED"` jobs
- Submit jobs to execution systems:
  - SLURM (`sbatch`)
  - AWS Batch
  - GCP Cloud Run Jobs
  - Azure Batch
  - Other job queue systems
- Manage job status:
  - Update `status`: CREATED → RUNNING → COMPLETED/FAILED
  - Set `submit_job_id`: External job system ID
  - Record `start_time`, `end_time`: Execution timestamps

---

## Design Benefits

1. **Platform Independence**: SUSHI is agnostic to job execution systems
2. **Scalability**: Job Manager can be scaled independently
3. **Flexibility**: Job system changes don't affect SUSHI core
4. **Testability**: SUSHI API can be tested without external dependencies
5. **Clear Responsibilities**: Each component has well-defined role

---

## Job Lifecycle

```
┌─────────────────────────────────────────────────────┐
│ Phase 1: SUSHI API (This Implementation)            │
├─────────────────────────────────────────────────────┤
│ 1. User → POST /api/v1/jobs                         │
│ 2. Retrieve DataSet information                     │
│ 3. Instantiate SUSHIApp class                       │
│ 4. Generate job script                              │
│ 5. Register in database:                            │
│    - Output DataSet                                 │
│    - Job (status="CREATED", submit_job_id=null)     │
└─────────────────────────────────────────────────────┘
                    ↓ (DB: jobs table)
┌─────────────────────────────────────────────────────┐
│ Phase 2: Job Manager (Separate Module)              │
├─────────────────────────────────────────────────────┤
│ 1. Poll DB (detect status="CREATED")               │
│ 2. Submit to job system                            │
│ 3. Update DB:                                      │
│    - status="RUNNING"                              │
│    - submit_job_id set                             │
│ 4. Detect completion                               │
│ 5. Update DB:                                      │
│    - status="COMPLETED" or "FAILED"                │
│    - end_time set                                  │
└─────────────────────────────────────────────────────┘
```

---

## Old SUSHI Analysis

### Job Submission Flow in Old SUSHI

1. **Controller**: `run_application_controller.rb#submit_jobs`
   - Receives HTTP request and formats parameters
   - Calls `SubmitJob.perform_later()`

2. **ActiveJob**: `app/jobs/submit_job.rb`
   - Background job processing
   - Loads, instantiates, and configures SushiApp
   - Executes `sushi_app.run`

3. **SushiApp**: `lib/sushi_fabric/lib/sushi_fabric/sushiApp.rb` (~1300 lines)
   - Job script generation
   - Dataset creation
   - Job record saving
   - Direct SLURM submission (`sbatch`)

### New SUSHI Structure

1. **Controller**: `app/controllers/api/v1/jobs_controller.rb#create`
   - Receives API request and formats parameters
   - Calls `JobSubmissionService`
   - Equivalent to old `run_application_controller.rb#submit_jobs`

2. **Service**: `app/services/job_submission_service.rb`
   - Orchestrates job submission process
   - Loads and configures SushiApp
   - Generates scripts, creates datasets, saves job records
   - Equivalent to `SubmitJob` + part of `sushiApp.rb`

3. **SushiApp**: `lib/sushi_fabric.rb` (~200 lines, simplified)
   - Minimal stub implementation
   - Basic functionality only
   - Reduced from 1300 lines to 200 lines

---

## Comparison: Old vs New

| Aspect | Old SUSHI | New SUSHI |
|--------|-----------|-----------|
| Job Submission | SUSHI directly executes `sbatch` | Job Manager executes (SUSHI only registers in DB) |
| Architecture | Monolithic (1300 lines) | Separation of concerns (Controller/Service/Domain) |
| Platform | SLURM fixed | Platform independent |
| Testing | External dependencies | No external dependencies (up to script generation) |
| Responsibility | Mixed (UI + Job execution + Management) | Clear separation (API + Job Manager) |

---

## Implementation Details

### Phase 1: Prerequisites and Setup

**1.1 Dataset Verification**
- Verify p35611/ventricles_100k exists in DB
  - Expected dataset_id: 9
  - Location: `/srv/gstore/projects/p35611/ventricles_100k/test_masa_dataset.tsv`

**1.2 Configuration**
- `backend/config/application.rb`:
  - `gstore_dir`: `/srv/gstore`
  - `submit_job_script_dir`: `tmp/job_scripts`
  - `scratch_dir`: `/scratch`

### Phase 2: API Implementation

**2.1 JobsController** (`app/controllers/api/v1/jobs_controller.rb`)
- `POST /api/v1/jobs` - Submit new job
- `GET /api/v1/jobs/:id` - Get job details
- `GET /api/v1/jobs` - List jobs (with filtering/pagination)

**2.2 JobSubmissionService** (`app/services/job_submission_service.rb`)
- Load and instantiate SushiApp
- Configure with parameters
- Generate job script
- Create output dataset
- Save job record

**2.3 SushiFabric Extension** (`lib/sushi_fabric.rb`)
- `set_input_dataset`: Load dataset from database
- `set_default_parameters`: Set app-specific defaults
- `generate_job_script`: Create bash script
- `prepare_result_dir`: Calculate result directory path

### Phase 3: Routes Configuration

**3.1 routes.rb**
```ruby
resources :jobs, only: [:create, :show, :index]
```

### Phase 4: Testing

**4.1 RSpec Tests** (`spec/requests/api/v1/jobs_controller_spec.rb`)
- Valid job submission
- Invalid dataset_id handling
- Invalid app_name handling
- Job listing and filtering

**4.2 Manual Test Script** (`backend/test_job_submission.sh`)
- Automated testing using curl
- Verifies all steps from dataset check to script generation

---

## Success Criteria

### SUSHI API Goals (This Implementation Scope)

1. ✅ POST /api/v1/jobs successfully submits jobs
2. ✅ Job record is created in database with:
   - `status="CREATED"` (initial state)
   - `submit_job_id=null` (Job Manager will set this)
   - `script_path` correctly recorded
   - `input_dataset_id`, `next_dataset_id` set
3. ✅ Output DataSet is created in database with:
   - `parent_id` set to input_dataset_id
   - Project information correctly set
4. ✅ Job script file is generated with:
   - Saved to `submit_job_script_dir`
   - Executable permissions (755) set
5. ✅ Test succeeds with FastqcApp using real dataset (ventricles_100k)

### Job Manager Goals (Separate Module - Outside SUSHI Scope)

- Retrieve jobs with `status="CREATED"` from DB
- Submit to job systems (SLURM/AWS/GCP/Azure, etc.)
- Update `status`: "RUNNING" → "COMPLETED"/"FAILED"
- Set `submit_job_id`, `start_time`, `end_time`

**Note**: Job Manager implementation/testing is outside this task scope

---

## Implementation Simplifications

To avoid excessive complexity, the following simplifications are made:

1. **Job Script Generation**: Minimal template instead of complete SLURM script
2. **gstore Copy**: Optional file copying (directory structure only)
3. **process_mode**: Support DATASET mode only initially
4. **Validation**: Basic checks only
5. **Job Submission**: SUSHI API does not execute (Job Manager's responsibility)

---

## Files Created/Modified

### Created Files

```
backend/app/controllers/api/v1/jobs_controller.rb
backend/app/services/job_submission_service.rb
backend/spec/requests/api/v1/jobs_controller_spec.rb
backend/test_job_submission.sh
docs/api-job-submission-endpoint.md
docs/job-submission-implementation-plan.md (this file)
```

### Modified Files

```
backend/config/routes.rb
  - Added: resources :jobs, only: [:create, :show, :index]

backend/config/application.rb
  - Added: gstore_dir, submit_job_script_dir, scratch_dir configuration

backend/lib/sushi_fabric.rb
  - Extended: Added methods for dataset loading, script generation

backend/app/models/data_set.rb
  - Modified: belongs_to :user, optional: true
  - Modified: save(validate: false) to avoid password validation issues
```

---

## API Endpoints

### POST /api/v1/jobs

Submit a new job for processing.

**Request:**
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

**Response (201 Created):**
```json
{
  "job": {
    "id": 1,
    "status": "CREATED",
    "user": "masaomi",
    "input_dataset_id": 9,
    "next_dataset_id": 280,
    "created_at": "2025-10-28T12:34:56Z"
  },
  "output_dataset": {
    "id": 280,
    "name": "FastQC_result"
  },
  "message": "Job submitted successfully"
}
```

### GET /api/v1/jobs/:id

Get detailed information about a specific job.

### GET /api/v1/jobs

List jobs with optional filtering (status, user) and pagination.

---

## Testing Strategy

### Unit Tests (RSpec)

```bash
cd backend
bundle exec rspec spec/requests/api/v1/jobs_controller_spec.rb
```

Tests cover:
- Job creation with valid parameters
- Error handling for invalid dataset/app
- Job retrieval and listing
- Filtering and pagination

### Integration Tests (Manual)

```bash
cd backend
./test_job_submission.sh
```

Tests verify:
1. Dataset exists and is accessible
2. Job submission returns success
3. Job details are retrievable
4. Output dataset is created
5. Job script file exists

### Expected Results

- Job record in database with `status="CREATED"`
- Output DataSet linked to input DataSet
- Job script file saved to `tmp/job_scripts/`
- All fields (script_path, input_dataset_id, next_dataset_id) populated

---

## Database Schema

### Job Table Fields

```ruby
- id                  # Primary key
- script_path         # Path to generated job script (SUSHI sets)
- status              # Job status (SUSHI: "CREATED", Job Manager: others)
- user                # Username who submitted (SUSHI sets)
- input_dataset_id    # Input dataset ID (SUSHI sets)
- next_dataset_id     # Output dataset ID (SUSHI sets)
- submit_job_id       # External job system ID (Job Manager sets)
- start_time          # Job start timestamp (Job Manager sets)
- end_time            # Job end timestamp (Job Manager sets)
- created_at          # Record creation time
- updated_at          # Record update time
```

**Key Point**: SUSHI only sets fields marked "SUSHI sets". Job Manager handles execution-related fields.

---

## Known Issues and Solutions

### Issue: User Password Validation Error

**Problem**: `undefined method 'password' for an instance of User`

**Cause**: Devise's `:validatable` module validates user when saving DataSet with associated user.

**Solution**: 
1. Made `belongs_to :user, optional: true` in DataSet model
2. Used `save(validate: false)` when creating output DataSet
3. Alternative: Pass `user: nil` to DataSet.save_dataset_to_database

---

## Future Enhancements

### Optional Features (Can be added later)

1. **Full SLURM Integration** (in Job Manager)
   - Complete sbatch script generation
   - Resource allocation optimization

2. **Multiple Process Modes**
   - SAMPLE mode support
   - BATCH mode support

3. **gstore File Operations**
   - Automatic file copying
   - Directory structure creation

4. **Job Statistics Endpoint**
   ```
   GET /api/v1/projects/:project_number/jobs/stats
   ```

5. **Background Job Processing**
   - Use ActiveJob/Sidekiq for async processing
   - Refactor JobSubmissionService to be called from background job

---

## References

### Documentation

- [API Job Submission Endpoint](./api-job-submission-endpoint.md)
- [API Project Jobs Endpoint](./api-project-jobs-endpoint.md)
- [API Datasets Endpoints](./api-datasets-endpoints.md)

### Old SUSHI Code References

- `old_sushi/master/app/controllers/run_application_controller.rb`
- `old_sushi/master/app/jobs/submit_job.rb`
- `old_sushi/master/lib/sushi_fabric/lib/sushi_fabric/sushiApp.rb`

---

## Conclusion

This implementation provides a clean, testable, and platform-independent job submission API. By separating SUSHI's responsibilities (script generation, metadata registration) from Job Manager's responsibilities (job execution, status management), the system achieves better modularity, testability, and flexibility.

The API-first approach allows testing without UI implementation and provides a foundation for future enhancements while maintaining clear architectural boundaries.

---

**Document Version**: 1.0  
**Last Updated**: 2025-10-28  
**Status**: Implementation Complete - Testing in Progress

